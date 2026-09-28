import Foundation

// Works out when scheduled tasks fall due. Pure: the caller passes the clock.
struct ScheduleEngine {
  // A task counts as on time when Keel notices it within this window. Longer gaps mean the
  // Mac was asleep or off.
  static let onTimeWindow: TimeInterval = 10 * 60

  // Follows time zone and daylight saving changes while Keel keeps running.
  var calendar: Calendar = .autoupdatingCurrent

  struct Due: Equatable {
    var task: ScheduledTask
    var dueAt: Date
    var outcome: TaskRun.Outcome
  }

  // The first run strictly after `date`, or nil when there is none.
  func nextOccurrence(of task: ScheduledTask, after date: Date) -> Date? {
    // One second before the start, so the start itself counts as a run.
    let from = max(date, task.start.addingTimeInterval(-1))
    let time = calendar.dateComponents([.hour, .minute], from: task.start)
    switch task.repeats {
    case .never:
      return task.start > date ? task.start : nil
    case .daily:
      return next(matching: time, after: from)
    case .weekdays:
      var cursor = from
      // At most two weekend days sit between two weekdays; a few spare steps cost nothing.
      for _ in 0..<4 {
        guard let candidate = next(matching: time, after: cursor) else { return nil }
        if !calendar.isDateInWeekend(candidate) { return candidate }
        cursor = candidate
      }
      return nil
    case .weekly, .biweekly:
      var components = time
      components.weekday = calendar.component(.weekday, from: task.start)
      guard var candidate = next(matching: components, after: from) else { return nil }
      if task.repeats == .biweekly, weeksBetween(task.start, candidate) % 2 != 0 {
        candidate = calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
      }
      return candidate
    case .monthly:
      var components = time
      components.day = calendar.component(.day, from: task.start)
      return next(matching: components, after: from)
    case .yearly:
      var components = time
      components.month = calendar.component(.month, from: task.start)
      components.day = calendar.component(.day, from: task.start)
      return next(matching: components, after: from)
    }
  }

  // Tasks that came due in (lastCheck, now]. A task missed several times runs once. Callers run
  // .onTime and .late results and only record .skipped ones in the history.
  func due(_ tasks: [ScheduledTask], lastCheck: Date, now: Date) -> [Due] {
    tasks.compactMap { task in
      guard task.isActive, let first = nextOccurrence(of: task, after: lastCheck), first <= now else { return nil }
      var latest = first
      while let next = nextOccurrence(of: task, after: latest), next <= now {
        latest = next
      }
      let outcome: TaskRun.Outcome
      if now.timeIntervalSince(latest) <= Self.onTimeWindow {
        outcome = .onTime
      } else {
        outcome = task.runAtNextOpportunity ? .late : .skipped
      }
      return Due(task: task, dueAt: latest, outcome: outcome)
    }
  }

  // Strict matching skips dates that don't exist, so a task on the 31st runs only in
  // months that have one, as AlDente does.
  private func next(matching components: DateComponents, after date: Date) -> Date? {
    calendar.nextDate(after: date, matching: components, matchingPolicy: .strict)
  }

  private func weeksBetween(_ start: Date, _ date: Date) -> Int {
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)
    ).day ?? 0
    return days / 7
  }
}
