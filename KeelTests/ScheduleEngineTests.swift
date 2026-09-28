import XCTest
@testable import Keel

final class ScheduleEngineTests: XCTestCase {
  private var engine: ScheduleEngine!
  private var calendar: Calendar!

  override func setUp() {
    super.setUp()
    calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    engine = ScheduleEngine(calendar: calendar)
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private func task(_ repeats: ScheduledTask.Repeat, start: Date, catchUp: Bool = false) -> ScheduledTask {
    ScheduledTask(action: .topUp, repeats: repeats, start: start, runAtNextOpportunity: catchUp)
  }

  func testNeverRunsOnce() {
    let once = task(.never, start: date(2026, 9, 28))
    XCTAssertEqual(engine.nextOccurrence(of: once, after: date(2026, 9, 27)), date(2026, 9, 28))
    XCTAssertNil(engine.nextOccurrence(of: once, after: date(2026, 9, 28)))
  }

  func testDailyKeepsTheTimeOfDay() {
    let daily = task(.daily, start: date(2026, 9, 28, 6, 30))
    XCTAssertEqual(engine.nextOccurrence(of: daily, after: date(2026, 9, 28, 7, 0)), date(2026, 9, 29, 6, 30))
  }

  func testDailyDoesNotRunBeforeItsStart() {
    let daily = task(.daily, start: date(2026, 10, 5, 6, 30))
    XCTAssertEqual(engine.nextOccurrence(of: daily, after: date(2026, 9, 28)), date(2026, 10, 5, 6, 30))
  }

  func testWeekdaysSkipTheWeekend() {
    // 2 October 2026 is a Friday.
    let weekdays = task(.weekdays, start: date(2026, 9, 28, 6, 30))
    XCTAssertEqual(engine.nextOccurrence(of: weekdays, after: date(2026, 10, 2, 7, 0)), date(2026, 10, 5, 6, 30))
  }

  func testWeeklyKeepsTheWeekday() {
    let weekly = task(.weekly, start: date(2026, 9, 28))
    XCTAssertEqual(engine.nextOccurrence(of: weekly, after: date(2026, 9, 28, 10)), date(2026, 10, 5))
  }

  func testBiweeklySkipsEveryOtherWeek() {
    let biweekly = task(.biweekly, start: date(2026, 9, 28))
    XCTAssertEqual(engine.nextOccurrence(of: biweekly, after: date(2026, 9, 28, 10)), date(2026, 10, 12))
    XCTAssertEqual(engine.nextOccurrence(of: biweekly, after: date(2026, 10, 12, 10)), date(2026, 10, 26))
  }

  func testMonthlyOnThe31stSkipsShortMonths() {
    let monthly = task(.monthly, start: date(2026, 8, 31))
    XCTAssertEqual(engine.nextOccurrence(of: monthly, after: date(2026, 8, 31, 10)), date(2026, 10, 31))
  }

  func testYearly() {
    let yearly = task(.yearly, start: date(2026, 9, 28))
    XCTAssertEqual(engine.nextOccurrence(of: yearly, after: date(2026, 9, 28, 10)), date(2027, 9, 28))
  }

  func testDueOnTime() {
    let daily = task(.daily, start: date(2026, 9, 28, 6, 30))
    let due = engine.due([daily], lastCheck: date(2026, 9, 29, 6, 29), now: date(2026, 9, 29, 6, 31))
    XCTAssertEqual(due.map(\.outcome), [.onTime])
    XCTAssertEqual(due.first?.dueAt, date(2026, 9, 29, 6, 30))
  }

  func testMissedWhileAsleepRunsOnceWhenCatchingUp() {
    let daily = task(.daily, start: date(2026, 9, 28, 6, 30), catchUp: true)
    let due = engine.due([daily], lastCheck: date(2026, 9, 28, 23, 0), now: date(2026, 10, 1, 8, 0))
    XCTAssertEqual(due.count, 1)
    XCTAssertEqual(due.first?.dueAt, date(2026, 10, 1, 6, 30))
    XCTAssertEqual(due.first?.outcome, .late)
  }

  func testMissedWhileAsleepIsSkippedWithoutCatchingUp() {
    let daily = task(.daily, start: date(2026, 9, 28, 6, 30))
    let due = engine.due([daily], lastCheck: date(2026, 9, 28, 23, 0), now: date(2026, 9, 29, 8, 0))
    XCTAssertEqual(due.first?.outcome, .skipped)
  }

  func testInactiveTasksNeverFall() {
    var daily = task(.daily, start: date(2026, 9, 28, 6, 30))
    daily.isActive = false
    XCTAssertTrue(engine.due([daily], lastCheck: date(2026, 9, 29, 6), now: date(2026, 9, 29, 7)).isEmpty)
  }
}
