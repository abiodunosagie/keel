import XCTest
@testable import Keel

final class ShellTests: XCTestCase {
  func testReturnsStatusAndOutput() {
    let result = Shell.run("/bin/echo", ["hello"])
    XCTAssertEqual(result?.status, 0)
    XCTAssertEqual(result?.output, "hello\n")
  }

  func testStopsAToolThatRunsTooLong() {
    let started = Date()
    XCTAssertNil(Shell.run("/bin/sleep", ["5"], timeout: 0.5))
    XCTAssertLessThan(Date().timeIntervalSince(started), 4)
  }

  func testMissingToolIsNil() {
    XCTAssertNil(Shell.run("/nonexistent/tool", []))
  }
}
