import XCTest
@testable import Keel

final class SetupRecommendationTests: XCTestCase {
  func testDeskUseGetsALowLimitAndRegularCalibration() {
    XCTAssertEqual(SetupRecommendation.make(usage: .desk, longDays: .rarely, heat: .often),
                   SetupRecommendation(limit: 80, heatProtection: true, calibration: .biweekly, weekdayTopUp: false))
  }

  func testMostlyOnBatteryNeedsNoCalibrationOrTopUp() {
    XCTAssertEqual(SetupRecommendation.make(usage: .mobile, longDays: .daily, heat: .rarely),
                   SetupRecommendation(limit: 95, heatProtection: false, calibration: nil, weekdayTopUp: false))
  }

  func testLongDaysAtADeskGetAWeekdayTopUp() {
    XCTAssertTrue(SetupRecommendation.make(usage: .mixed, longDays: .daily, heat: .sometimes).weekdayTopUp)
  }
}
