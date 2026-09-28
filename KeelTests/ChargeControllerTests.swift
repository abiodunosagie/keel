import XCTest
@testable import Keel

// Records every limit the controller hands over instead of talking to powerd.
final class FakeBackend: ChargeBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var _applied: [Int?] = []
  private var _limit: Int?
  var failWith: Error?

  init(limit: Int? = nil) {
    _limit = limit
  }

  var applied: [Int?] { lock.withLock { _applied } }
  var isAvailable: Bool { true }
  var limitRange: ClosedRange<Int> { 80...100 }

  func currentLimit() throws -> Int? { lock.withLock { _limit } }

  func apply(limit: Int?) throws {
    if let failWith { throw failWith }
    lock.withLock {
      _applied.append(limit)
      _limit = limit
    }
  }
}

@MainActor
final class ChargeControllerTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "KeelTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private func battery(percent: Int, pluggedIn: Bool = true, charging: Bool = false) -> BatterySnapshot {
    BatterySnapshot(
      macOSPercent: percent, remainingCapacity: percent * 50, fullChargeCapacity: 5000, designCapacity: 6000,
      cycleCount: 1, isPluggedIn: pluggedIn, isCharging: charging, isFullyCharged: false, voltage: 12,
      amperage: 0, temperature: 30, systemLoad: nil, adapterWatts: nil, minutesToEmpty: nil, minutesToFull: nil
    )
  }

  private func waitForApply(_ backend: FakeBackend, count: Int) async {
    for _ in 0..<200 where backend.applied.count < count {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func testAppliesTheLimitOnceAndNotAgainWhenUnchanged() async {
    let backend = FakeBackend()
    var current = battery(percent: 60, charging: true)
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) { current }
    controller.refresh()
    await waitForApply(backend, count: 1)
    current = battery(percent: 61, charging: true)
    controller.refresh()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(backend.applied, [80])
    XCTAssertEqual(controller.appliedLimit, 80)
  }

  func testTopUpEndsWhenUnplugged() async {
    let backend = FakeBackend()
    var current = battery(percent: 85, charging: true)
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) { current }
    controller.refresh()
    await waitForApply(backend, count: 1)
    controller.startTopUp()
    await waitForApply(backend, count: 2)
    XCTAssertEqual(controller.state, .topUp)

    current = battery(percent: 99, pluggedIn: false)
    controller.refresh()
    await waitForApply(backend, count: 3)
    XCTAssertFalse(controller.isTopUpActive)
    XCTAssertEqual(backend.applied, [80, nil, 80])
  }

  func testSettingsArePersisted() {
    let store = SettingsStore(defaults: defaults)
    let controller = ChargeController(backend: FakeBackend(), store: store) { nil }
    controller.settings.limit = 97
    controller.settings.heatProtection = true
    XCTAssertEqual(store.load().limit, 97)
    XCTAssertTrue(store.load().heatProtection)
  }

  func testPauseChargingSetsTheLimitToTheCurrentLevel() {
    let controller = ChargeController(backend: FakeBackend(), store: SettingsStore(defaults: defaults)) {
      self.battery(percent: 88)
    }
    controller.refresh()
    controller.pauseCharging()
    XCTAssertEqual(controller.settings.limit, 88)
  }

  func testFailureIsReportedAndRetried() async {
    let backend = FakeBackend()
    backend.failWith = ChargeBackendError.unavailable
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) {
      self.battery(percent: 60)
    }
    controller.refresh()
    for _ in 0..<200 where controller.lastError == nil {
      try? await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertNotNil(controller.lastError)
    backend.failWith = nil
    controller.refresh()
    await waitForApply(backend, count: 1)
    XCTAssertEqual(backend.applied, [80])
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

final class BatteryReaderTests: XCTestCase {
  func testParsesTheMacOS27Registry() {
    // Shape copied from this Mac's AppleSmartBattery entry on macOS 27.0.
    let properties: [String: Any] = [
      "CurrentCapacity": 49, "CycleCount": 186, "ExternalConnected": false, "IsCharging": false,
      "FullyCharged": false, "Voltage": 11564, "Amperage": NSNumber(value: UInt64(18446744073709551380)),
      "AvgTimeToEmpty": 551, "AvgTimeToFull": 65535,
      "BatteryData": ["FullChargeCapacity": 5754, "RemainingCapacity": 2783, "DesignCapacity": 6249],
      "PowerTelemetryData": ["SystemLoad": 2764],
    ]
    let snapshot = BatteryReader.snapshot(from: properties, temperature: 32, adapterWatts: nil)
    XCTAssertEqual(snapshot.macOSPercent, 49)
    XCTAssertEqual(snapshot.hardwarePercent, 48.37, accuracy: 0.01)
    XCTAssertEqual(snapshot.health, 92.08, accuracy: 0.01)
    XCTAssertEqual(snapshot.amperage, -0.236, accuracy: 0.0001)
    XCTAssertEqual(snapshot.systemLoad ?? 0, 2.764, accuracy: 0.0001)
    XCTAssertEqual(snapshot.minutesToEmpty, 551)
    XCTAssertNil(snapshot.minutesToFull)
  }
}
