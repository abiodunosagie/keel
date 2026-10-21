import Foundation
import IOKit.ps
import Observation
import os

// Things that happen which the owner may want a notification for.
enum ChargeEvent: Equatable, Sendable {
  case limitReached(Int)
  case heatPauseStarted(Double)
  case calibrationFinished
  case calibrationStopped(String)
  case chargerProblem(String)
  case temperatureHigh(Double)
  case overLimitOnLaunch(percent: Int, limit: Int, dischargesItself: Bool)
}

// The privileged side: the charger switch and the MagSafe light. HelperClient in the app, a
// fake in tests.
@MainActor
protocol ChargerControl: AnyObject {
  var isReady: Bool { get }
  // nil on success, otherwise why it failed.
  func setChargerConnected(_ connected: Bool) async -> String?
  func setMagSafeLight(_ light: MagSafeLight) async -> Bool
  func setSleepDisabled(_ disabled: Bool) async -> Bool
  // nil when the helper can't be asked.
  func isChargerConnected() async -> Bool?
  func isSleepDisabled() async -> Bool?
}

struct NetworkLimit: Equatable, Sendable {
  var network: String
  var limit: Int
}

// Reads the battery on a timer and on every power change, runs ChargePolicy and hands the result
// to macOS (the limit) and to the helper (the charger switch and the light).
@MainActor
@Observable
final class ChargeController {
  static let refreshInterval: TimeInterval = 5
  // Every this many refreshes, read back the limit macOS really holds and re-apply if something
  // else changed it.
  static let reconcileEvery = 12

  private(set) var snapshot: BatterySnapshot?
  private(set) var state: ChargeState = .unavailable
  private(set) var mode: ChargeMode = .normal
  private(set) var appliedLimit: Int?
  private(set) var lastError: String?
  private(set) var isAvailable = false
  private(set) var lastCalibration: Date?

  var settings: ChargeSettings {
    didSet {
      guard settings != oldValue else { return }
      store.save(settings)
      if settings.heatProtection != oldValue.heatProtection { heatGuard.reset() }
      refresh()
    }
  }

  var options: AppOptions {
    didSet {
      guard options != oldValue else { return }
      store.save(options)
      refresh()
    }
  }

  // A limit picked by the Wi-Fi network (Automation). A manual limit change clears it until the
  // network changes again.
  var networkLimit: NetworkLimit? {
    didSet {
      guard networkLimit != oldValue else { return }
      refresh()
    }
  }

  // The settings the rules actually use: the network's limit when one applies.
  var effectiveSettings: ChargeSettings {
    guard let networkLimit else { return settings }
    var copy = settings
    copy.limit = networkLimit.limit
    return copy
  }

  var onEvent: ((ChargeEvent) -> Void)?
  // Every reading, and whether Keel itself is running the Mac on battery right now.
  var onRefresh: ((BatterySnapshot, _ drainExpected: Bool) -> Void)?
  weak var charger: ChargerControl?

  private let backend: ChargeBackend
  private let store: SettingsStore
  private let readBattery: @MainActor () -> BatterySnapshot?
  private let clock: @MainActor () -> Date
  private let log = Logger(subsystem: "com.abiodunosagie.Keel", category: "charge")
  private var heatGuard = HeatGuard()
  private var hardwareOffset = HardwareOffset()
  private var applied: AppliedLimit = .unknown
  private var applyTask: Task<Void, Never>?
  private var pendingLimit: Int??
  private var chargerConnected = true
  private var light: MagSafeLight = .system
  private var refreshCount = 0
  private var temperatureAlertArmed = true
  private var effects: [UUID: Task<Void, Never>] = [:]
  // Set once Keel is quitting or being removed; no more limit writes after that.
  private var isStopped = false
  // Touched from deinit, which is not main-actor isolated; both are only set on the main thread.
  private nonisolated(unsafe) var timer: Timer?
  private nonisolated(unsafe) var powerSource: CFRunLoopSource?
  private let sleepGuard = SleepGuard()

  init(
    backend: ChargeBackend = NativeChargeBackend(),
    store: SettingsStore = SettingsStore(),
    clock: @escaping @MainActor () -> Date = { .now },
    readBattery: @escaping @MainActor () -> BatterySnapshot? = { BatteryReader.read() }
  ) {
    self.backend = backend
    self.store = store
    self.clock = clock
    self.readBattery = readBattery
    self.settings = store.load()
    self.options = store.loadOptions()
    self.lastCalibration = store.lastCalibration
  }

  // The power-source callback holds an unretained pointer to this controller, so it must be
  // removed before the controller goes away.
  deinit {
    timer?.invalidate()
    if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
  }

  var limitRange: ClosedRange<Int> { backend.limitRange }

  // Shown instead of the controls on a Mac without the macOS charge limit.
  var unavailableReason: String {
    ChargeBackendError.unavailable.errorDescription ?? ""
  }

  // The limit to draw on the mark, nil when macOS has no charge limit to hold.
  var displayLimit: Int? {
    isAvailable ? effectiveSettings.limit : nil
  }

  var displayPercent: Double? {
    snapshot?.percent(useHardware: settings.useHardwarePercent)
  }

  var isTopUpActive: Bool { mode == .topUp }

  var calibrationStep: CalibrationStep? {
    if case .calibration(let step) = mode { return step }
    return nil
  }

  // Starts the loop. Asking powerd whether the limit is supported, and what it was before Keel,
  // are round trips, so they run off the main thread.
  func start() async {
    let backend = backend
    let store = store
    let supported = await Task.detached(priority: .userInitiated) { () -> Bool in
      guard backend.isAvailable else { return false }
      store.recordOriginalLimitIfNeeded { try backend.currentLimit() }
      return true
    }.value
    isAvailable = supported
    if store.calibrationWasRunning {
      store.calibrationWasRunning = false
      onEvent?(.calibrationStopped(String(localized: "Keel was closed during calibration, so it stopped.")))
    }
    refresh()
    announceIfOverLimit()
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
    let previous = self.snapshot
    self.snapshot = snapshot
    hardwareOffset.update(macOS: snapshot.macOSPercent, hardware: snapshot.hardwarePercent)
    endFinishedModes(previous: previous, current: snapshot)
    guard isAvailable else {
      state = .unavailable
      return
    }
    stopCalibrationIfHelperGone()

    if settings.heatProtection, snapshot.isPluggedIn, mode == .normal {
      let wasPaused = heatGuard.isPaused
      heatGuard.update(temperature: snapshot.temperature, limit: settings.maxTemperature, now: clock())
      if heatGuard.isPaused, !wasPaused, let temperature = snapshot.temperature {
        onEvent?(.heatPauseStarted(temperature))
      }
    } else {
      heatGuard.reset()
    }

    let decision = ChargePolicy.decide(
      snapshot: snapshot, settings: effectiveSettings, mode: mode, heatPaused: heatGuard.isPaused,
      hardwareOffset: hardwareOffset.value, limitRange: limitRange
    )
    if state == .charging, decision.state == .paused, mode == .normal, let limit = decision.limit {
      onEvent?(.limitReached(limit))
    }
    state = decision.state
    checkTemperature(snapshot)
    onRefresh?(snapshot, state == .discharging || calibrationStep == .dischargeLow)
    apply(decision.limit)
    setCharger(connected: decision.chargerConnected)
    updateLight()
    updateSleep()
    reconcileIfDue()
  }

  // AlDente's "overcharged on launch" notice: the battery is well above the limit when Keel
  // starts, for example after the Mac charged to 100% while switched off.
  private func announceIfOverLimit() {
    guard options.overLimitAlert, let snapshot, isAvailable else { return }
    let target = ChargePolicy.target(settings: effectiveSettings, hardwareOffset: hardwareOffset.value, limitRange: limitRange)
    guard target < limitRange.upperBound, snapshot.macOSPercent > target + 2 else { return }
    onEvent?(.overLimitOnLaunch(percent: snapshot.macOSPercent, limit: target,
                                dischargesItself: settings.automaticDischarge))
  }

  // One alert per crossing; it re-arms once the battery is 2 °C below the limit.
  private func checkTemperature(_ snapshot: BatterySnapshot) {
    guard options.temperatureAlert, let temperature = snapshot.temperature else { return }
    if temperature >= options.temperatureAlertLimit, temperatureAlertArmed {
      temperatureAlertArmed = false
      onEvent?(.temperatureHigh(temperature))
    } else if temperature < options.temperatureAlertLimit - 2 {
      temperatureAlertArmed = true
    }
  }

  // MARK: Actions

  func startTopUp() {
    guard snapshot?.isPluggedIn == true else { return }
    mode = .topUp
    refresh()
  }

  func stopTopUp() {
    guard mode == .topUp else { return }
    mode = .normal
    refresh()
  }

  // Runs on battery down to the limit once. Only meaningful when the battery is above it.
  func startDischarge() {
    guard canDischarge else { return }
    mode = .discharge
    refresh()
  }

  func stopDischarge() {
    guard mode == .discharge else { return }
    mode = .normal
    refresh()
  }

  var canDischarge: Bool {
    guard let snapshot, snapshot.isPluggedIn, mode == .normal else { return false }
    return snapshot.macOSPercent > ChargePolicy.target(settings: effectiveSettings, hardwareOffset: hardwareOffset.value,
                                                       limitRange: limitRange)
  }

  // Sets the limit to the level the battery is at now, so it neither charges nor discharges.
  // macOS has no limit below 80%, so under 80% this can't hold the level.
  func pauseCharging() {
    guard let snapshot else { return }
    mode = .normal
    networkLimit = nil
    let limit = ChargePolicy.limitHoldingCurrentLevel(
      snapshot: snapshot, settings: effectiveSettings, hardwareOffset: hardwareOffset.value, limitRange: limitRange
    )
    // Setting a new limit refreshes through didSet; an unchanged one still needs the mode change applied.
    if limit == settings.limit { refresh() } else { settings.limit = limit }
  }

  var canPauseHere: Bool {
    guard let snapshot else { return false }
    return snapshot.macOSPercent >= limitRange.lowerBound
  }

  func setLimit(_ limit: Int) {
    networkLimit = nil
    settings.limit = limitRange.clamped(limit)
  }

  // Nil when calibration can start, otherwise why not.
  var calibrationBlocker: String? {
    guard isAvailable else { return String(localized: "This Mac has no built-in charge limit.") }
    guard charger?.isReady == true else { return String(localized: "Install Keel Helper first (Settings > General).") }
    guard snapshot?.isPluggedIn == true else { return String(localized: "Plug in the charger to start calibration.") }
    return nil
  }

  func startCalibration() {
    guard calibrationBlocker == nil else { return }
    mode = .calibration(.chargeFull)
    store.calibrationWasRunning = true
    refresh()
  }

  func stopCalibration(reason: String? = nil) {
    guard calibrationStep != nil else { return }
    mode = .normal
    store.calibrationWasRunning = false
    if let reason { onEvent?(.calibrationStopped(reason)) }
    refresh()
  }

  // Called when Keel quits. Leaves macOS on the steady limit, never on a temporary one, or
  // removes the limit when the owner chose not to keep it while Keel is closed.
  func prepareForQuit() async {
    await stopWriting()
    await settle()
    let limit: Int?
    if options.keepLimitWhenClosed, let snapshot {
      limit = ChargePolicy.decide(
        snapshot: snapshot, settings: effectiveSettings, mode: .normal, heatPaused: false,
        hardwareOffset: hardwareOffset.value, limitRange: limitRange
      ).limit
    } else {
      limit = nil
    }
    let backend = backend
    _ = await Task.detached { try? backend.apply(limit: limit) }.value
    if calibrationStep != nil { store.calibrationWasRunning = false }
  }

  // Stops new limit writes and waits for one in flight, so a final write can't be overtaken by
  // an older one landing after it.
  private func stopWriting() async {
    isStopped = true
    timer?.invalidate()
    timer = nil
    pendingLimit = nil
    await settle()
  }

  // Puts macOS back the way it was before Keel first ran.
  func restoreOriginalLimit() async {
    await stopWriting()
    mode = .normal
    let backend = backend
    let original = store.originalLimit
    _ = await Task.detached { try? backend.apply(limit: original) }.value
    applied = .unknown
  }

  // Test hook: waits for an in-flight limit write to finish.
  // Waits until the limit write and every helper call or read-back started so far have
  // finished. Quitting uses it; tests use it instead of guessing with sleeps.
  func settle() async {
    while true {
      if let task = applyTask {
        await task.value
      } else if let effect = effects.values.first {
        await effect.value
      } else {
        return
      }
    }
  }

  // Runs a side effect as a tracked task so settle() can wait for it.
  private func track(_ body: @escaping @MainActor () async -> Void) {
    let id = UUID()
    effects[id] = Task { [weak self] in
      await body()
      self?.effects[id] = nil
    }
  }

  // MARK: Private

  private func endFinishedModes(previous: BatterySnapshot?, current: BatterySnapshot) {
    let unplugged = previous?.isPluggedIn == true && !current.isPluggedIn
    switch mode {
    case .topUp where unplugged:
      mode = .normal
    case .discharge:
      let target = ChargePolicy.target(settings: effectiveSettings, hardwareOffset: hardwareOffset.value, limitRange: limitRange)
      if unplugged || current.macOSPercent <= target { mode = .normal }
    case .calibration(let step):
      let target = ChargePolicy.target(settings: effectiveSettings, hardwareOffset: hardwareOffset.value, limitRange: limitRange)
      switch Calibration.advance(step, snapshot: current, target: target, now: clock()) {
      case .stay: break
      case .next(let next): mode = .calibration(next)
      case .finished:
        mode = .normal
        store.calibrationWasRunning = false
        store.lastCalibration = clock()
        lastCalibration = store.lastCalibration
        onEvent?(.calibrationFinished)
      case .aborted:
        mode = .normal
        store.calibrationWasRunning = false
        onEvent?(.calibrationStopped(String(localized: "The charger was unplugged, so calibration stopped.")))
      }
    default:
      break
    }
  }

  // One write at a time. A change that arrives mid-write is applied as soon as it finishes.
  private func apply(_ limit: Int?) {
    guard !isStopped, applied != .known(limit) else { return }
    guard applyTask == nil else {
      pendingLimit = .some(limit)
      return
    }
    let backend = backend
    applyTask = Task { [weak self] in
      let result = await Task.detached(priority: .utility) { Result { try backend.apply(limit: limit) } }.value
      guard let self else { return }
      self.applyTask = nil
      switch result {
      case .success:
        self.applied = .known(limit)
        self.appliedLimit = limit
        self.lastError = nil
      case .failure(let error):
        self.log.error("Applying limit failed: \(error.localizedDescription, privacy: .public)")
        self.lastError = (error as? ChargeBackendError)?.errorDescription
          ?? String(localized: "macOS didn't accept the charge limit. Keel will try again.")
      }
      if let pending = self.pendingLimit {
        self.pendingLimit = nil
        self.apply(pending)
      }
    }
  }

  private func reconcileIfDue() {
    refreshCount += 1
    guard refreshCount % Self.reconcileEvery == 0, applyTask == nil, case .known(let expected) = applied else {
      return
    }
    let backend = backend
    track { [weak self] in
      let read = await Task.detached(priority: .utility) { Result { try backend.currentLimit() } }.value
      // A failed read proves nothing; "no limit" (nil) is a real answer and is compared.
      guard let self, case .success(let actual) = read, actual != expected, self.applyTask == nil else { return }
      self.log.notice("macOS limit changed outside Keel, re-applying")
      self.applied = .unknown
      self.refresh()
    }
    // The helper may have reconnected the charger on its own (its 10% floor), so the
    // bookkeeping is checked against the real switch too.
    if let charger, charger.isReady {
      track { [weak self] in
        guard let connected = await charger.isChargerConnected(), let self else { return }
        self.chargerConnected = connected
      }
      // Same for sleep: if the helper restarted and restored it, Keel sends it again.
      track { [weak self] in
        guard let disabled = await charger.isSleepDisabled(), let self else { return }
        self.sleepGuard.reconcile(lidSleepDisabled: disabled)
      }
    }
  }

  private func setCharger(connected: Bool) {
    guard connected != chargerConnected, let charger, charger.isReady else { return }
    chargerConnected = connected
    track { [weak self] in
      guard let failure = await charger.setChargerConnected(connected) else { return }
      guard let self else { return }
      // The switch didn't move, so the bookkeeping goes back to what is really true and the
      // next refresh tries again.
      self.chargerConnected = !connected
      if self.calibrationStep != nil {
        self.stopCalibration(reason: failure)
      }
    }
  }

  // A restarted helper has put the charger, light and sleep back to the system defaults; forget
  // what Keel last sent so the next refresh sends it again.
  func helperRestarted() {
    chargerConnected = true
    light = .system
    sleepGuard.reconcile(lidSleepDisabled: false)
    refresh()
  }

  // Calibration can't run on without the helper: stop it rather than leave the charger in an
  // unknown state. The helper reconnects the charger itself when it stops.
  private func stopCalibrationIfHelperGone() {
    guard calibrationStep != nil, charger?.isReady != true else { return }
    chargerConnected = true
    stopCalibration(reason: String(localized: "Keel Helper stopped, so calibration stopped."))
  }

  // Green when held at the limit, orange while moving toward it, as AlDente does. With the
  // option off the light belongs to macOS.
  private func updateLight() {
    guard let charger, charger.isReady else { return }
    let wanted: MagSafeLight
    switch (options.magSafeLight, state) {
    case (.system, _): wanted = .system
    case (.auto, .paused): wanted = .green
    case (.auto, .charging), (.auto, .discharging), (.auto, .topUp), (.auto, .heatProtect),
         (.auto, .calibration), (.auto, .macOSOverride):
      wanted = .orange
    case (.auto, .onBattery), (.auto, .unavailable): wanted = .system
    }
    guard wanted != light else { return }
    light = wanted
    track { _ = await charger.setMagSafeLight(wanted) }
  }

  // Calibration keeps the Mac awake throughout; "keep awake until the limit" only while it is
  // still moving toward the limit on the charger.
  private func updateSleep() {
    let calibrating = calibrationStep != nil
    let movingToLimit = options.keepAwakeUntilLimit && (state == .charging || state == .discharging)
    sleepGuard.set(awake: calibrating || movingToLimit)
    if let charger, charger.isReady, sleepGuard.needsLidSleepChange(to: calibrating) {
      track { _ = await charger.setSleepDisabled(calibrating) }
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

// What Keel last told macOS: unknown until the first write succeeds (and again after something
// else changed it), then the limit or nil for "no limit".
private enum AppliedLimit: Equatable {
  case unknown
  case known(Int?)
}

// The gap between the macOS and hardware percentages, in whole points. It only moves when the
// raw gap is clearly past the half-point boundary, so gauge jitter can't flip the limit.
struct HardwareOffset: Equatable {
  private(set) var value = 0
  private var initialized = false

  mutating func update(macOS: Int, hardware: Double) {
    let raw = Double(macOS) - hardware
    if !initialized || abs(raw - Double(value)) > 0.75 {
      value = Int(raw.rounded())
      initialized = true
    }
  }
}
