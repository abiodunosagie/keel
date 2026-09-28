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

final class NetworkTrackerTests: XCTestCase {
  func testABriefNilReadingIsNotANetworkChange() {
    var tracker = NetworkTracker()
    XCTAssertEqual(NetworkTracker.settle("Office", state: &tracker)?.changed, true)
    XCTAssertNil(NetworkTracker.settle(nil, state: &tracker), "one nil reading is ignored")
    XCTAssertEqual(NetworkTracker.settle("Office", state: &tracker)?.changed, false)
  }

  func testLeavingWiFiNeedsSeveralNilReadings() {
    var tracker = NetworkTracker()
    _ = NetworkTracker.settle("Office", state: &tracker)
    for _ in 1..<NetworkTracker.nilReadingsToLeave {
      XCTAssertNil(NetworkTracker.settle(nil, state: &tracker))
    }
    let left = NetworkTracker.settle(nil, state: &tracker)
    XCTAssertEqual(left?.changed, true)
    XCTAssertNil(left?.name ?? nil)
  }

  func testSwitchingNetworksIsAChange() {
    var tracker = NetworkTracker()
    _ = NetworkTracker.settle("Office", state: &tracker)
    let home = NetworkTracker.settle("Home", state: &tracker)
    XCTAssertEqual(home?.name, "Home")
    XCTAssertEqual(home?.changed, true)
  }
}

final class CalendarTopUpTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  func testPicksTheFirstUnhandledTripInTheWindow() {
    let trips = [
      Automation.Trip(key: "a|1", start: now.addingTimeInterval(3600)),
      Automation.Trip(key: "b|2", start: now.addingTimeInterval(7200)),
    ]
    XCTAssertEqual(Automation.tripToTopUp(trips, handled: ["a|1"], now: now, lead: 3 * 3600)?.key, "b|2")
  }

  func testIgnoresTripsBeyondTheLeadTime() {
    let trips = [Automation.Trip(key: "a|1", start: now.addingTimeInterval(5 * 3600))]
    XCTAssertNil(Automation.tripToTopUp(trips, handled: [], now: now, lead: 3 * 3600))
  }

  func testEachOccurrenceOfARepeatingTripCounts() {
    // Same identifier, different start: the second week's flight is a new trip.
    let nextWeek = [Automation.Trip(key: "flight|\(Int(now.timeIntervalSince1970) + 3600)", start: now.addingTimeInterval(3600))]
    let handled: Set = ["flight|\(Int(now.timeIntervalSince1970) - 7 * 86_400 + 3600)"]
    XCTAssertNotNil(Automation.tripToTopUp(nextWeek, handled: handled, now: now, lead: 3 * 3600))
  }
}
