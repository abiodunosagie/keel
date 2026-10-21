import XCTest
@testable import Keel

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

  func testMissingBatteryDataDoesNotDivideByZero() {
    let snapshot = BatteryReader.snapshot(from: ["CurrentCapacity": 50], temperature: nil, adapterWatts: nil)
    XCTAssertEqual(snapshot.hardwarePercent, 50)
    XCTAssertEqual(snapshot.health, 0)
  }
}

final class ParserTests: XCTestCase {
  func testPowerModeFromPmset() {
    let output = "System-wide power settings:\nCurrently in use:\n standby              1\n powermode            1\n"
    XCTAssertEqual(PowerModeReader.parse(output), .low)
    XCTAssertNil(PowerModeReader.parse("nothing here"))
  }

  func testSystemProcessesGetPlainNames() {
    // Translated names keep the process name in brackets, so this holds in every language.
    XCTAssertNotEqual(EnergyApp.displayName(for: "WindowServer"), "WindowServer")
    XCTAssertTrue(EnergyApp.displayName(for: "WindowServer").contains("(WindowServer)"))
    XCTAssertTrue(EnergyApp.displayName(for: "kernel_task").contains("(kernel_task)"))
    XCTAssertEqual(EnergyApp.displayName(for: "Xcode"), "Xcode")
  }

  func testEnergyAppsUseTheSecondSample() {
    let output = """
    Processes: 1
    POWER COMMAND
    0.0   first
    POWER COMMAND
    12.5  Xcode
    3.1   Google Chrome
    0.0   idle
    """
    XCTAssertEqual(EnergyApp.parse(output, limit: 5), [
      EnergyApp(name: "Xcode", impact: 12.5), EnergyApp(name: "Google Chrome", impact: 3.1),
    ])
  }
}

@MainActor
final class SchedulerTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() async throws {
    try await super.setUp()
    suiteName = "KeelSchedulerTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    try await super.tearDown()
  }

  func testRunsADueTaskOnceAndRecordsIt() async {
    var now = Date(timeIntervalSince1970: 1_000_000)
    let backend = FakeBackend()
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) {
      makeBattery(percent: 70, charging: true)
    }
    await controller.start()
    let scheduler = Scheduler(controller: controller, helper: nil, defaults: defaults) { now }
    scheduler.start()
    scheduler.save(ScheduledTask(action: .setLimit(95), repeats: .never, start: now.addingTimeInterval(30)))

    now = now.addingTimeInterval(60)
    scheduler.check()
    XCTAssertEqual(controller.settings.limit, 95)
    XCTAssertEqual(scheduler.history.map(\.outcome), [.onTime])
    XCTAssertFalse(scheduler.tasks[0].isActive)

    now = now.addingTimeInterval(60)
    scheduler.check()
    XCTAssertEqual(scheduler.history.count, 1)
  }

  func testTasksSurviveARelaunch() {
    let controller = ChargeController(backend: FakeBackend(), store: SettingsStore(defaults: defaults)) { nil }
    let first = Scheduler(controller: controller, helper: nil, defaults: defaults)
    first.save(ScheduledTask(action: .topUp, repeats: .weekdays, start: .now))
    let second = Scheduler(controller: controller, helper: nil, defaults: defaults)
    XCTAssertEqual(second.tasks.map(\.action), [.topUp])
  }
}

final class PowerLogTests: XCTestCase {
  func testReadsChargeAndSourceFromPmsetLog() {
    let log = """
    2026-09-27 08:06:13 +0100 Sleep               \tEntering DarkWake state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:41%)
    2026-09-27 11:46:51 +0100 Wake                \tWake from Hibernate [CDNVA] : due to lid charger Using AC (Charge:1%)
    2026-09-27 12:00:00 +0100 Assertions          \tPID 123 Created PreventUserIdleSystemSleep
    """
    let samples = PowerLog.parse(log)
    XCTAssertEqual(samples.map(\.percent), [41, 1])
    XCTAssertEqual(samples.map(\.pluggedIn), [false, true])
    XCTAssertNil(samples[0].watts)
    XCTAssertEqual(samples[0].date, Date(timeIntervalSince1970: 1_790_492_773))
  }
}

final class ChargerReadingTests: XCTestCase {
  func testReadsTheAdapterAndPowerIn() {
    // Shape copied from this Mac on the 87 W USB-C adapter.
    let properties: [String: Any] = [
      "CurrentCapacity": 42, "ExternalConnected": true, "IsCharging": true,
      "AdapterDetails": ["Name": "87W USB-C Power Adapter", "Manufacturer": "Apple Inc.", "Watts": 86,
                         "AdapterVoltage": 20000, "Current": 4290],
      "PowerTelemetryData": ["SystemLoad": 11244, "SystemPowerIn": 81108],
      "ChargerData": ["NotChargingReason": 0, "SlowChargingReason": 0],
    ]
    let snapshot = BatteryReader.snapshot(from: properties, temperature: nil, adapterWatts: 86)
    XCTAssertEqual(snapshot.charger, ChargerInfo(name: "87W USB-C Power Adapter", manufacturer: "Apple Inc.",
                                                 watts: 86, volts: 20, amps: 4.29))
    XCTAssertEqual(snapshot.powerIn ?? 0, 81.108, accuracy: 0.001)
  }

  func testNoChargerWhenUnplugged() {
    let properties: [String: Any] = ["ExternalConnected": false, "AdapterDetails": ["Watts": 86]]
    XCTAssertNil(BatteryReader.snapshot(from: properties, temperature: nil, adapterWatts: nil).charger)
  }
}
