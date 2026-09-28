import XCTest
@testable import Keel

final class CalendarMatchingTests: XCTestCase {
  func testKeywordsAreTrimmedAndLowercased() {
    XCTAssertEqual(Automation.keywords(" Flight, trip ,,Conference "), ["flight", "trip", "conference"])
  }

  func testMatchesTitlesCaseInsensitively() {
    let keywords = ["flight", "trip"]
    XCTAssertTrue(Automation.matches("Flight to Lisbon", keywords: keywords))
    XCTAssertTrue(Automation.matches("Road TRIP", keywords: keywords))
    XCTAssertFalse(Automation.matches("Standup", keywords: keywords))
  }
}

@MainActor
final class NetworkLimitTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() async throws {
    try await super.setUp()
    suiteName = "KeelNetworkTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    try await super.tearDown()
  }

  func testNetworkLimitWinsUntilAManualChange() async {
    let backend = FakeBackend()
    let controller = ChargeController(backend: backend, store: SettingsStore(defaults: defaults)) {
      makeBattery(percent: 70, charging: true)
    }
    await controller.start()
    await controller.settle()
    XCTAssertEqual(backend.applied.last, 80)

    controller.networkLimit = NetworkLimit(network: "Office", limit: 90)
    await controller.settle()
    XCTAssertEqual(backend.applied.last, 90)
    XCTAssertEqual(controller.settings.limit, 80, "the normal limit is kept for other networks")

    controller.setLimit(85)
    await controller.settle()
    XCTAssertNil(controller.networkLimit)
    XCTAssertEqual(backend.applied.last, 85)
  }
}
