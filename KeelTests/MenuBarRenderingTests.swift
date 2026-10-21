import XCTest
@testable import Keel

final class MenuBarRenderingTests: XCTestCase {
  func testTextFollowsTheOptions() {
    var options = AppOptions()
    options.menuBarPercent = true
    options.menuBarTemperature = true
    var snapshot = makeBattery(percent: 80)
    snapshot.temperature = 31.4
    let rendering = MenuBarRendering(state: .paused, percent: 80, limit: 95, snapshot: snapshot, options: options, recent: [])
    XCTAssertEqual(rendering.text, " 80% 31°")
  }

  func testBatteryStyleShowsThePercentInsideTheIcon() {
    var options = AppOptions()
    options.iconStyle = .battery
    let rendering = MenuBarRendering(state: .paused, percent: 80, limit: 95, snapshot: nil, options: options, recent: [])
    XCTAssertEqual(rendering.text, "")
    XCTAssertNotNil(rendering.image())
  }

  func testLiveStatusSymbols() {
    let options = AppOptions()
    XCTAssertEqual(MenuBarRendering(state: .paused, percent: 80, limit: 95, snapshot: nil, options: options, recent: []).symbolName, "powerplug")
    XCTAssertEqual(MenuBarRendering(state: .charging, percent: 60, limit: 95, snapshot: nil, options: options, recent: []).symbolName,
                   "battery.100percent.bolt")
    XCTAssertEqual(MenuBarRendering(state: .onBattery, percent: 30, limit: 95, snapshot: nil, options: options, recent: []).symbolName,
                   "battery.25percent")
  }

  func testKeelMarkIsTheDefaultAndDrawsATemplate() {
    let options = AppOptions()
    XCTAssertEqual(options.iconStyle, .mark)
    for (percent, limit) in [(0.0, 80), (50.0, 95), (100.0, 100), (97.0, nil)] as [(Double, Int?)] {
      let image = MenuBarRendering(state: .paused, percent: percent, limit: limit, snapshot: nil, options: options, recent: []).image()
      XCTAssertEqual(image?.size, NSSize(width: 16, height: 16))
      XCTAssertEqual(image?.isTemplate, true)
      XCTAssertNotNil(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
  }

  func testMarkLevelStopsUnderTheLineAndFillsWithoutALimit() {
    let held = MarkGeometry(side: 100, level: 1, limit: 90)
    let line = try! XCTUnwrap(held.lineHeight)
    XCTAssertEqual(held.fillHeight, line - held.gap / 2, accuracy: 0.001)
    let low = MarkGeometry(side: 100, level: 0.2, limit: 90)
    XCTAssertEqual(low.fillHeight, 2 * low.inner * 0.2, accuracy: 0.001)
    let open = MarkGeometry(side: 100, level: 1, limit: nil)
    XCTAssertNil(open.lineHeight)
    XCTAssertEqual(open.fillHeight, 2 * open.inner, accuracy: 0.001)
    // The line never reaches the top of the disc, even at a 100% limit.
    let top = try! XCTUnwrap(MarkGeometry(side: 100, level: 1, limit: 100).lineHeight)
    XCTAssertLessThan(top, 2 * open.inner)
  }
}
