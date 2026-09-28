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

final class PopoverLayoutTests: XCTestCase {
  func testMoveAndHide() {
    var layout = PopoverLayout()
    layout.move(.stats, by: -1)
    XCTAssertEqual(Array(layout.order.prefix(5)), [.summary, .limit, .actions, .stats, .powerFlow])
    layout.toggle(.limit)
    XCTAssertFalse(layout.visible.contains(.limit))
    layout.move(.summary, by: -1)
    XCTAssertEqual(layout.order.first, .summary, "moving past the top does nothing")
  }

  func testNewCardsAppearHiddenInOldLayouts() {
    let old = PopoverLayout(order: [.limit, .summary], hidden: [])
    let normalized = old.normalized()
    XCTAssertEqual(normalized.order.prefix(2), [.limit, .summary])
    XCTAssertEqual(Set(normalized.order), Set(PopoverLayout.Card.allCases))
    XCTAssertTrue(normalized.hidden.contains(.chart))
  }
}

final class MenuBarRenderingTests: XCTestCase {
  func testTextFollowsTheOptions() {
    var options = AppOptions()
    options.menuBarPercent = true
    options.menuBarTemperature = true
    var snapshot = makeBattery(percent: 80)
    snapshot.temperature = 31.4
    let rendering = MenuBarRendering(state: .paused, percent: 80, snapshot: snapshot, options: options, recent: [])
    XCTAssertEqual(rendering.text, " 80% 31°")
  }

  func testBatteryStyleShowsThePercentInsideTheIcon() {
    var options = AppOptions()
    options.iconStyle = .battery
    let rendering = MenuBarRendering(state: .paused, percent: 80, snapshot: nil, options: options, recent: [])
    XCTAssertEqual(rendering.text, "")
    XCTAssertNotNil(rendering.image())
  }

  func testLiveStatusSymbols() {
    let options = AppOptions()
    XCTAssertEqual(MenuBarRendering(state: .paused, percent: 80, snapshot: nil, options: options, recent: []).symbolName, "powerplug")
    XCTAssertEqual(MenuBarRendering(state: .charging, percent: 60, snapshot: nil, options: options, recent: []).symbolName,
                   "battery.100percent.bolt")
    XCTAssertEqual(MenuBarRendering(state: .onBattery, percent: 30, snapshot: nil, options: options, recent: []).symbolName,
                   "battery.25percent")
  }
}
