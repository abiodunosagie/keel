import Foundation
import IOKit.ps
import Observation

// Reads the battery on a timer and on every power change, runs ChargePolicy and hands the
// resulting limit to the backend. Only writes to the backend when the limit changes.
@MainActor
@Observable
final class ChargeController {
  static let refreshInterval: TimeInterval = 5

  private(set) var snapshot: BatterySnapshot?
  private(set) var state: ChargeState = .unavailable
  private(set) var appliedLimit: Int?
  private(set) var lastError: String?
  private(set) var isTopUpActive = false

  var settings: ChargeSettings {
    didSet {
      guard settings != oldValue else { return }
      store.save(settings)
      if settings.heatProtection != oldValue.heatProtection { heatGuard.reset() }
      refresh()
    }
  }

  let backend: ChargeBackend
  private let store: SettingsStore
  private let readBattery: @MainActor () -> BatterySnapshot?
  private var heatGuard = HeatGuard()
  private var hasApplied = false
  private var isApplying = false
  private var timer: Timer?
  private var powerSource: CFRunLoopSource?

  init(
    backend: ChargeBackend = NativeChargeBackend(),
    store: SettingsStore = SettingsStore(),
    readBattery: @escaping @MainActor () -> BatterySnapshot? = { BatteryReader.read() }
  ) {
    self.backend = backend
    self.store = store
    self.readBattery = readBattery
    self.settings = store.load()
  }

  var isAvailable: Bool { backend.isAvailable }

  var displayPercent: Double? {
    snapshot?.percent(useHardware: settings.useHardwarePercent)
  }

  func start() {
    store.recordOriginalLimitIfNeeded { [backend] in try backend.currentLimit() }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    observePowerSource()
  }

  func refresh() {
    guard let snapshot = readBattery() else {
      state = .unavailable
      return
    }
    let wasPluggedIn = self.snapshot?.isPluggedIn ?? snapshot.isPluggedIn
    self.snapshot = snapshot

    // Top Up lasts until the charger is unplugged once.
    if isTopUpActive, wasPluggedIn, !snapshot.isPluggedIn {
      isTopUpActive = false
    }
    guard backend.isAvailable else {
      state = .unavailable
      return
    }

    if settings.heatProtection, snapshot.isPluggedIn, !isTopUpActive {
      heatGuard.update(temperature: snapshot.temperature, limit: settings.maxTemperature, now: .now)
    } else {
      heatGuard.reset()
    }

    let decision = ChargePolicy.decide(
      snapshot: snapshot,
      settings: settings,
      topUp: isTopUpActive,
      heatPaused: heatGuard.isPaused,
      limitRange: backend.limitRange
    )
    state = decision.state
    apply(decision.limit)
  }

  func startTopUp() {
    isTopUpActive = true
    refresh()
  }

  func stopTopUp() {
    isTopUpActive = false
    refresh()
  }

  // Sets the limit to the level the battery is at now, so it neither charges nor discharges.
  func pauseCharging() {
    guard let snapshot else { return }
    isTopUpActive = false
    settings.limit = min(max(Int(snapshot.percent(useHardware: settings.useHardwarePercent).rounded(.down)),
                             backend.limitRange.lowerBound), backend.limitRange.upperBound)
  }

  // Puts macOS back the way it was before Keel first ran.
  func restoreOriginalLimit() throws {
    try backend.apply(limit: store.originalLimit)
    appliedLimit = store.originalLimit
  }

  private func apply(_ limit: Int?) {
    guard !isApplying, !hasApplied || limit != appliedLimit else { return }
    isApplying = true
    let backend = backend
    Task.detached(priority: .utility) {
      let result = Result { try backend.apply(limit: limit) }
      await MainActor.run {
        self.isApplying = false
        switch result {
        case .success:
          self.appliedLimit = limit
          self.hasApplied = true
          self.lastError = nil
        case .failure(let error):
          self.lastError = error.localizedDescription
        }
      }
    }
  }

  private func observePowerSource() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let controller = Unmanaged<ChargeController>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { controller.refresh() }
    }, context)?.takeRetainedValue() else {
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    powerSource = source
  }
}
