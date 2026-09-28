import XCTest
@testable import Keel

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
