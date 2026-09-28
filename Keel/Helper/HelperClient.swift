import Foundation
import Observation
import ServiceManagement
import os

// Installs and talks to the privileged helper that switches the charger off for calibration,
// drives the MagSafe light and keeps the Mac awake with the lid closed.
@MainActor
@Observable
final class HelperClient: ChargerControl {
  enum Status: Equatable {
    case notInstalled
    case needsApproval
    case ready
    case failed(String)
  }

  private(set) var status: Status = .notInstalled

  private let service = SMAppService.daemon(plistName: HelperIdentity.plistName)
  private let log = Logger(subsystem: "com.abiodunosagie.Keel", category: "helper")
  private var connection: NSXPCConnection?

  var isReady: Bool { status == .ready }

  func refreshStatus() {
    switch service.status {
    case .enabled: status = .ready
    case .requiresApproval: status = .needsApproval
    case .notRegistered, .notFound: status = .notInstalled
    @unknown default: status = .notInstalled
    }
  }

  // After an update the helper launchd still runs may be the old build. Re-registering makes
  // launchd start the one inside the current Keel.app.
  // Helpers from version 2 on can exit on request, so launchd picks up the new binary without a
  // new approval. Version 1 can't, so it is re-registered (macOS then asks for approval again).
  func replaceIfOutdated() async {
    refreshStatus()
    guard isReady else {
      log.notice("Helper not ready: \(String(describing: self.status), privacy: .public)")
      return
    }
    let running = await version()
    log.notice("Helper running version \(running.map(String.init) ?? "none", privacy: .public), app expects \(HelperIdentity.version, privacy: .public)")
    guard let running else {
      // Registered but unreachable: an old helper from before an update, which the app can no
      // longer verify. Re-registering replaces it; macOS then asks for approval once.
      try? await service.unregister()
      install()
      return
    }
    guard running != HelperIdentity.version else { return }
    if running >= 2 {
      _ = await call { proxy, done in proxy.exitForUpdate { done(true) } } as Bool?
    } else {
      try? await service.unregister()
      install()
    }
    connection?.invalidate()
    connection = nil
  }

  func install() {
    do {
      try service.register()
      refreshStatus()
    } catch {
      refreshStatus()
      if status != .needsApproval {
        status = .failed(error.localizedDescription)
      }
    }
    if status == .needsApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  // Throws when macOS keeps the helper registered, so Remove Keel can stop before trashing the
  // app a root daemon still points at.
  func uninstall() async throws {
    connection?.invalidate()
    connection = nil
    defer { refreshStatus() }
    guard service.status != .notRegistered, service.status != .notFound else { return }
    try await service.unregister()
  }

  func version() async -> Int? {
    await call { proxy, done in proxy.version { done($0) } }
  }

  // Returns nil on success, otherwise why it failed.
  func setChargerConnected(_ connected: Bool) async -> String? {
    let result: (Bool, String?)? = await call { proxy, done in
      proxy.setChargerConnected(connected) { ok, message in done((ok, message)) }
    }
    guard let result else { return String(localized: "Keel's helper isn't running.") }
    return result.0 ? nil : (result.1 ?? String(localized: "The charger switch didn't respond."))
  }

  func isChargerConnected() async -> Bool? {
    await call { proxy, done in proxy.isChargerConnected { done($0) } }
  }

  @discardableResult
  func setMagSafeLight(_ light: MagSafeLight) async -> Bool {
    await call { proxy, done in proxy.setMagSafeLight(light) { done($0) } } ?? false
  }

  @discardableResult
  func setSleepDisabled(_ disabled: Bool) async -> Bool {
    await call { proxy, done in proxy.setSleepDisabled(disabled) { done($0) } } ?? false
  }

  func readChipPower() async -> ChipPower? {
    let result: ChipPower?? = await call { proxy, done in
      proxy.readChipPower { cpu, gpu, ane, ok in
        done(ok ? ChipPower(cpu: cpu, gpu: gpu, neuralEngine: ane) : nil)
      }
    }
    return result ?? nil
  }

  @discardableResult
  func setPowerMode(_ mode: PowerMode) async -> Bool {
    await call { proxy, done in proxy.setPowerMode(mode) { done($0) } } ?? false
  }

  // One XPC round trip. nil when the helper can't be reached or the connection drops.
  private func call<T: Sendable>(
    _ body: @escaping (HelperProtocol, @escaping @Sendable (T) -> Void) -> Void
  ) async -> T? {
    guard status == .ready else { return nil }
    let connection = currentConnection()
    return await withCheckedContinuation { continuation in
      let once = Once(continuation)
      let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) }
      guard let helper = proxy as? HelperProtocol else {
        once.resume(nil)
        return
      }
      body(helper) { once.resume($0) }
    }
  }

  private func currentConnection() -> NSXPCConnection {
    if let connection { return connection }
    let connection = NSXPCConnection(machServiceName: HelperIdentity.label, options: .privileged)
    // Only talk to a helper Keel's own team signed.
    connection.setCodeSigningRequirement(HelperIdentity.helperRequirement)
    connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
    connection.invalidationHandler = { [weak self] in
      Task { @MainActor in
        self?.connection = nil
        self?.refreshStatus()
      }
    }
    connection.resume()
    self.connection = connection
    return connection
  }
}

// Resumes a continuation exactly once, whichever of the reply or the error handler comes first.
private final class Once<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T?, Never>?

  init(_ continuation: CheckedContinuation<T?, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: T?) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: value)
  }
}
