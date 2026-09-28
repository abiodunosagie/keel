import XCTest
@testable import Keel

// Records every limit the controller hands over instead of talking to powerd.
final class FakeBackend: ChargeBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var _applied: [Int?] = []
  private var _limit: Int?
  private var _failWith: Error?

  init(limit: Int? = nil) {
    _limit = limit
  }

  var applied: [Int?] { lock.withLock { _applied } }
  var failWith: Error? {
    get { lock.withLock { _failWith } }
    set { lock.withLock { _failWith = newValue } }
  }

  var isAvailable: Bool { true }
  var limitRange: ClosedRange<Int> { 80...100 }

  func currentLimit() throws -> Int? { lock.withLock { _limit } }

  // Something other than Keel changing the limit.
  func setExternally(_ limit: Int?) { lock.withLock { _limit = limit } }

  func apply(limit: Int?) throws {
    try lock.withLock {
      if let _failWith { throw _failWith }
      _applied.append(limit)
      _limit = limit
    }
  }
}

@MainActor
final class FakeCharger: ChargerControl {
  var isReady = true
  var connectedCalls: [Bool] = []
  var lights: [MagSafeLight] = []
  var failure: String?

  var connected = true

  func setChargerConnected(_ connected: Bool) async -> String? {
    connectedCalls.append(connected)
    if failure == nil { self.connected = connected }
    return failure
  }

  func isChargerConnected() async -> Bool? { connected }

  func setMagSafeLight(_ light: MagSafeLight) async -> Bool {
    lights.append(light)
    return true
  }

  func setSleepDisabled(_ disabled: Bool) async -> Bool { true }
}

@MainActor
final class ChargeControllerTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!
  private var backend: FakeBackend!
  private var battery = makeBattery(percent: 60, charging: true)
  private var now = Date(timeIntervalSince1970: 1_000_000)

  override func setUp() async throws {
    try await super.setUp()
    suiteName = "KeelTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    backend = FakeBackend()
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    try await super.tearDown()
  }

  private func makeController() async -> ChargeController {
    let controller = ChargeController(
      backend: backend, store: SettingsStore(defaults: defaults), clock: { [unowned self] in now }
    ) { [unowned self] in battery }
    await controller.start()
    await controller.settle()
    return controller
  }

  private func refresh(_ controller: ChargeController) async {
    controller.refresh()
    await controller.settle()
  }

  func testAppliesTheLimitOnceAndNotAgainWhenUnchanged() async {
    let controller = await makeController()
    battery = makeBattery(percent: 61, charging: true)
    await refresh(controller)
    XCTAssertEqual(backend.applied, [80])
    XCTAssertEqual(controller.appliedLimit, 80)
  }

  func testTopUpEndsWhenUnplugged() async {
    battery = makeBattery(percent: 85, charging: true)
    let controller = await makeController()
    controller.startTopUp()
    await controller.settle()
    XCTAssertEqual(controller.state, .topUp)

    battery = makeBattery(percent: 99, pluggedIn: false)
    await refresh(controller)
    XCTAssertFalse(controller.isTopUpActive)
    XCTAssertEqual(backend.applied, [80, nil, 80])
  }

  func testTopUpNeedsTheCharger() async {
    battery = makeBattery(percent: 60, pluggedIn: false)
    let controller = await makeController()
    controller.startTopUp()
    XCTAssertFalse(controller.isTopUpActive)
  }

  func testQuittingDuringTopUpLeavesTheSteadyLimit() async {
    battery = makeBattery(percent: 85, charging: true)
    let controller = await makeController()
    controller.startTopUp()
    await controller.prepareForQuit()
    XCTAssertEqual(backend.applied.last, 80)
    await refresh(controller)
    XCTAssertEqual(backend.applied.last, 80, "no writes after quitting")
  }

  func testQuittingWithoutKeepingTheLimitRemovesIt() async {
    let controller = await makeController()
    controller.options.keepLimitWhenClosed = false
    await controller.prepareForQuit()
    XCTAssertEqual(backend.applied.last, .some(nil))
  }

  func testReappliesWhenSomethingElseChangesTheLimit() async {
    let controller = await makeController()
    backend.setExternally(95)
    for _ in 0..<ChargeController.reconcileEvery {
      await refresh(controller)
    }
    XCTAssertEqual(backend.applied, [80, 80])
  }

  func testReappliesWhenSomethingElseRemovesTheLimit() async {
    let controller = await makeController()
    backend.setExternally(nil)
    for _ in 0..<ChargeController.reconcileEvery {
      await refresh(controller)
    }
    XCTAssertEqual(backend.applied, [80, 80])
  }

  func testChargerBookkeepingFollowsTheHelper() async {
    let charger = FakeCharger()
    battery = makeBattery(percent: 100)
    let controller = await makeController()
    controller.charger = charger
    controller.startCalibration()
    await refresh(controller)
    XCTAssertEqual(charger.connectedCalls, [false])
    // The helper reconnects on its own at its floor; the next read-back notices.
    charger.connected = true
    for _ in 0..<ChargeController.reconcileEvery {
      await refresh(controller)
    }
    XCTAssertEqual(charger.connectedCalls, [false, false], "Keel cuts it again while calibration still wants it cut")
  }

  func testDischargeStopsAtTheLimit() async {
    battery = makeBattery(percent: 90, amperage: -1.5)
    let controller = await makeController()
    controller.settings.automaticDischarge = false
    await controller.settle()
    XCTAssertEqual(backend.applied.last, 90)
    controller.startDischarge()
    await controller.settle()
    XCTAssertEqual(backend.applied.last, 80)
    battery = makeBattery(percent: 80)
    await refresh(controller)
    XCTAssertEqual(controller.mode, .normal)
  }

  func testCalibrationNeedsTheHelper() async {
    let controller = await makeController()
    XCTAssertNotNil(controller.calibrationBlocker)
    controller.startCalibration()
    XCTAssertNil(controller.calibrationStep)
  }

  func testCalibrationCutsAndRestoresTheCharger() async {
    let charger = FakeCharger()
    battery = makeBattery(percent: 100)
    let controller = await makeController()
    controller.charger = charger
    controller.startCalibration()
    await refresh(controller)
    XCTAssertEqual(controller.calibrationStep, .dischargeLow)
    await controller.settle()
    XCTAssertEqual(charger.connectedCalls, [false])

    battery = makeBattery(percent: 10, amperage: -2)
    await refresh(controller)
    await controller.settle()
    XCTAssertEqual(controller.calibrationStep, .rechargeFull)
    XCTAssertEqual(charger.connectedCalls, [false, true])
  }

  func testCalibrationStopsWhenTheChargerSwitchFails() async {
    let charger = FakeCharger()
    charger.failure = "The charger switch didn't respond."
    battery = makeBattery(percent: 100)
    let controller = await makeController()
    controller.charger = charger
    var events: [ChargeEvent] = []
    controller.onEvent = { events.append($0) }
    controller.startCalibration()
    await refresh(controller)
    await controller.settle()
    XCTAssertNil(controller.calibrationStep)
    XCTAssertEqual(events, [.calibrationStopped("The charger switch didn't respond.")])
  }

  func testFailedReconnectIsRetried() async {
    let charger = FakeCharger()
    battery = makeBattery(percent: 100)
    let controller = await makeController()
    controller.charger = charger
    controller.startCalibration()
    await refresh(controller)
    await controller.settle()
    XCTAssertEqual(charger.connectedCalls, [false])

    charger.failure = "The charger switch didn't respond."
    battery = makeBattery(percent: 10)
    await refresh(controller)
    await controller.settle()
    XCTAssertNil(controller.calibrationStep)

    charger.failure = nil
    await refresh(controller)
    await controller.settle()
    XCTAssertEqual(charger.connectedCalls.first, false)
    XCTAssertEqual(charger.connectedCalls.last, true)
    XCTAssertTrue(charger.connected, "the reconnect is retried until the charger is back")
  }

  func testCalibrationStopsWhenTheHelperGoesAway() async {
    let charger = FakeCharger()
    battery = makeBattery(percent: 100)
    let controller = await makeController()
    controller.charger = charger
    controller.startCalibration()
    await refresh(controller)
    charger.isReady = false
    await refresh(controller)
    XCTAssertNil(controller.calibrationStep)
  }

  func testInterruptedCalibrationIsReportedOnLaunch() async {
    SettingsStore(defaults: defaults).calibrationWasRunning = true
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) { [unowned self] in
      battery
    }
    var events: [ChargeEvent] = []
    controller.onEvent = { events.append($0) }
    await controller.start()
    XCTAssertEqual(events.count, 1)
    XCTAssertNil(controller.calibrationStep)
  }

  func testSettingsArePersisted() async {
    let store = SettingsStore(defaults: defaults)
    let controller = await makeController()
    controller.settings.limit = 97
    controller.settings.heatProtection = true
    controller.options.magSafeLight = .auto
    XCTAssertEqual(store.load().limit, 97)
    XCTAssertTrue(store.load().heatProtection)
    XCTAssertEqual(store.loadOptions().magSafeLight, .auto)
  }

  func testPauseChargingSetsTheLimitToTheCurrentLevel() async {
    battery = makeBattery(percent: 88)
    let controller = await makeController()
    controller.pauseCharging()
    XCTAssertEqual(controller.settings.limit, 88)
  }

  func testCannotPauseBelowEighty() async {
    battery = makeBattery(percent: 45)
    let controller = await makeController()
    XCTAssertFalse(controller.canPauseHere)
  }

  func testFailureIsReportedAndRetried() async {
    backend.failWith = ChargeBackendError.unavailable
    let controller = await makeController()
    XCTAssertNotNil(controller.lastError)
    backend.failWith = nil
    await refresh(controller)
    XCTAssertEqual(backend.applied, [80])
    XCTAssertNil(controller.lastError)
  }

  func testLimitReachedIsAnnounced() async {
    let controller = await makeController()
    var events: [ChargeEvent] = []
    controller.onEvent = { events.append($0) }
    battery = makeBattery(percent: 80)
    await refresh(controller)
    XCTAssertEqual(events, [.limitReached(80)])
  }

  func testMagSafeLightFollowsTheState() async {
    let charger = FakeCharger()
    let controller = await makeController()
    controller.charger = charger
    controller.options.magSafeLight = .auto
    await controller.settle()
    battery = makeBattery(percent: 80)
    await refresh(controller)
    await controller.settle()
    XCTAssertEqual(charger.lights, [.orange, .green])
  }

  func testOriginalLimitIsRecordedOnce() {
    let store = SettingsStore(defaults: defaults)
    store.recordOriginalLimitIfNeeded { 85 }
    store.recordOriginalLimitIfNeeded { 90 }
    XCTAssertEqual(store.originalLimit, 85)
  }

  func testOriginalLimitIsNotRecordedWhenReadingFails() {
    let store = SettingsStore(defaults: defaults)
    store.recordOriginalLimitIfNeeded { throw ChargeBackendError.unavailable }
    store.recordOriginalLimitIfNeeded { nil }
    XCTAssertNil(store.originalLimit)
    store.recordOriginalLimitIfNeeded { 90 }
    XCTAssertNil(store.originalLimit)
  }
}
