import XCTest
@testable import Keel

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
