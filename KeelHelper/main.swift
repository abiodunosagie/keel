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

  // pmset -g prints "SleepDisabled  1" while sleep is off.
  static var isSleepDisabled: Bool {
    guard let output = Shell.run("/usr/bin/pmset", ["-g"])?.output else { return false }
    return output.split(separator: "\n").contains { line in
      let fields = line.split(whereSeparator: \.isWhitespace)
      return fields.count >= 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
    }
  }

  static func setPowerMode(_ mode: PowerMode) -> Bool {
    pmset(["-a", "powermode", String(mode.rawValue)])
  }

  private static func pmset(_ arguments: [String]) -> Bool {
    Shell.run("/usr/bin/pmset", arguments)?.status == 0
  }
}

// One powermetrics sample. Fixed arguments; the output is parsed, never passed on raw.
enum ChipPowerReader {
  static let intervalMilliseconds = 500

  static func sample() -> (cpu: Double, gpu: Double, ane: Double)? {
    let arguments = ["-n", "1", "-i", "\(intervalMilliseconds)", "--samplers", "cpu_power,gpu_power,ane_power",
                     "-f", "plist"]
    guard let result = Shell.run("/usr/bin/powermetrics", arguments, timeout: 10), result.status == 0 else {
      return nil
    }
    // The plist ends with a NUL; keep what comes before it.
    let text = result.output.split(separator: "\0", maxSplits: 1).first.map(String.init) ?? result.output
    guard let data = text.data(using: .utf8),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      return nil
    }
    return ChipPowerParsing.parse(root, intervalMilliseconds: intervalMilliseconds)
  }
}

// Never let the battery run below this while the helper holds the charger off, whatever the
// app asked for.
enum SafetyFloor {
  static let percent = HelperIdentity.batteryFloor

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
  let queue = DispatchQueue(label: "com.abiodunosagie.Keel.Helper")
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

  func isSleepDisabled(reply: @escaping (Bool) -> Void) {
    trustCaller()
    queue.async { reply(PowerSettings.isSleepDisabled) }
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

  func readChipPower(reply: @escaping (Double, Double, Double, Bool) -> Void) {
    trustCaller()
    // Its own queue: a half-second sample must not hold up the charger switch.
    DispatchQueue.global(qos: .utility).async {
      guard let power = ChipPowerReader.sample() else {
        reply(0, 0, 0, false)
        return
      }
      reply(power.cpu, power.gpu, power.ane, true)
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

// An update replaces this file while the old helper still runs, and the app then can't verify
// the old process's signature. So the helper restores everything and exits as soon as its file
// is replaced; launchd starts the new one on the next connection.
let service = HelperService()

// Only a delete or rename counts: that is what replacing the app does. A touch or an
// attribute change (which any process of the user could make) must not restart the helper.
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
let descriptor = open(executable, O_EVTONLY)
let watcher = DispatchSource.makeFileSystemObjectSource(
  fileDescriptor: descriptor, eventMask: [.delete, .rename], queue: service.queue
)
watcher.setEventHandler {
  restoreDefaults()
  exit(0)
}
if descriptor >= 0 { watcher.resume() }
let listener = NSXPCListener(machServiceName: HelperIdentity.label)
listener.delegate = service
listener.resume()
dispatchMain()
