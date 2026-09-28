import Foundation
import IOKit

// Keel's privileged helper. launchd starts it on demand when the app connects to its Mach
// service. It runs as root because writing SMC keys and pmset settings needs root.

// CHIE 0x08 cuts the charger inside the Mac, 0x00 restores it.
enum Charger {
  private static let key = "CHIE"
  private static let disconnectedByte: UInt8 = 0x08

  @discardableResult
  static func set(connected: Bool) -> Bool {
    guard let smc = KeelSMC.shared() else { return false }
    return smc.writeBytes(Data([connected ? 0x00 : disconnectedByte]), forKey: key)
  }

  static var isConnected: Bool {
    guard let byte = KeelSMC.shared()?.bytes(forKey: key, type: nil)?.first else { return true }
    return byte & disconnectedByte == 0
  }
}

enum MagSafe {
  @discardableResult
  static func set(_ light: MagSafeLight) -> Bool {
    guard let smc = KeelSMC.shared() else { return false }
    return smc.writeBytes(Data([UInt8(light.rawValue)]), forKey: "ACLC")
  }
}

// Fixed pmset calls only; nothing the app sends reaches the command line except these values.
enum PowerSettings {
  @discardableResult
  static func setSleepDisabled(_ disabled: Bool) -> Bool {
    pmset(["-a", "disablesleep", disabled ? "1" : "0"])
  }

  static func setPowerMode(_ mode: PowerMode) -> Bool {
    pmset(["-a", "powermode", String(mode.rawValue)])
  }

  private static func pmset(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }
}

// Never let the battery run below this while the helper holds the charger off, whatever the
// app asked for.
enum SafetyFloor {
  static let percent = 10

  // Fails closed: a battery that can't be read counts as empty.
  static var isAtOrBelow: Bool {
    guard let current = batteryPercent() else { return true }
    return current <= percent
  }

  static func batteryPercent() -> Int? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(service, "CurrentCapacity" as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? NSNumber)?.intValue
  }
}

// Puts everything the helper can change back to normal.
func restoreDefaults() {
  Charger.set(connected: true)
  MagSafe.set(.system)
  PowerSettings.setSleepDisabled(false)
}

final class HelperService: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
  // All state and all writes happen on this queue.
  private let queue = DispatchQueue(label: "com.abiodunosagie.Keel.Helper")
  // Only connections that have delivered a message count: XPC only delivers messages from
  // peers that pass the code-signing requirement, so an unsigned process that connects and
  // stays silent can never keep the helper from restoring everything when Keel goes away.
  private var trusted = Set<ObjectIdentifier>()
  private var watchdog: DispatchSourceTimer?

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.setCodeSigningRequirement(HelperIdentity.clientRequirement)
    connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
    connection.exportedObject = self
    let id = ObjectIdentifier(connection)
    connection.invalidationHandler = { [weak self] in self?.connectionEnded(id) }
    connection.resume()
    return true
  }

  // Called at the top of every method: the caller has passed the signing requirement.
  private func trustCaller() {
    guard let connection = NSXPCConnection.current() else { return }
    let id = ObjectIdentifier(connection)
    queue.sync { _ = trusted.insert(id) }
  }

  func version(reply: @escaping (Int) -> Void) {
    trustCaller()
    reply(HelperIdentity.version)
  }

  func setChargerConnected(_ connected: Bool, reply: @escaping (Bool, String?) -> Void) {
    trustCaller()
    queue.async {
      if !connected, SafetyFloor.isAtOrBelow {
        reply(false, "The battery is at \(SafetyFloor.percent)% or lower, or can't be read. Keel won't run it lower.")
        return
      }
      guard Charger.set(connected: connected) else {
        reply(false, "The charger switch didn't respond.")
        return
      }
      connected ? self.stopWatchdog() : self.startWatchdog()
      reply(true, nil)
    }
  }

  func isChargerConnected(reply: @escaping (Bool) -> Void) {
    trustCaller()
    queue.async { reply(Charger.isConnected) }
  }

  func setMagSafeLight(_ light: MagSafeLight, reply: @escaping (Bool) -> Void) {
    trustCaller()
    guard [MagSafeLight.system, .green, .orange].contains(light) else {
      reply(false)
      return
    }
    queue.async { reply(MagSafe.set(light)) }
  }

  func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
    trustCaller()
    queue.async { reply(PowerSettings.setSleepDisabled(disabled)) }
  }

  func exitForUpdate(reply: @escaping () -> Void) {
    trustCaller()
    queue.async {
      restoreDefaults()
      reply()
      // Give the reply a moment to reach the app before the process goes away.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }
  }

  func setPowerMode(_ mode: PowerMode, reply: @escaping (Bool) -> Void) {
    trustCaller()
    // An out-of-range raw value from a hostile client never reaches pmset.
    guard PowerMode.allCases.contains(mode) else {
      reply(false)
      return
    }
    queue.async { reply(PowerSettings.setPowerMode(mode)) }
  }

  // When the app quits or crashes, everything goes back to normal so the Mac never keeps
  // draining, or stays awake, with nobody watching.
  private func connectionEnded(_ id: ObjectIdentifier) {
    queue.async {
      guard self.trusted.remove(id) != nil, self.trusted.isEmpty else { return }
      restoreDefaults()
      self.stopWatchdog()
    }
  }

  private func startWatchdog() {
    guard watchdog == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler { [weak self] in
      guard SafetyFloor.isAtOrBelow else { return }
      Charger.set(connected: true)
      self?.stopWatchdog()
    }
    watchdog = timer
    timer.resume()
  }

  private func stopWatchdog() {
    watchdog?.cancel()
    watchdog = nil
  }
}

// A fresh start means nobody is steering yet, so everything goes back to normal.
restoreDefaults()

signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
  restoreDefaults()
  exit(0)
}
termination.resume()

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperIdentity.label)
listener.delegate = service
listener.resume()
dispatchMain()
