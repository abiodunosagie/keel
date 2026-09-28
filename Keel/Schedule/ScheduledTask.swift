import Foundation

// A task the owner schedules, like "Top Up on weekdays at 06:30".
struct ScheduledTask: Codable, Equatable, Identifiable, Sendable {
  enum Action: Codable, Equatable, Sendable {
    case setLimit(Int)
    case topUp
    case pauseCharging
    // Sets the limit and runs on battery down to it (macOS holds nothing below 80%).
    case dischargeTo(Int)
    case startCalibration
    case powerMode(Int) // PowerMode raw value

    var title: String {
      switch self {
      case .setLimit(let percent): return "Set charge limit to \(percent)%"
      case .topUp: return "Top Up"
      case .pauseCharging: return "Pause charging"
      case .dischargeTo(let percent): return "Discharge to \(percent)%"
      case .startCalibration: return "Start calibration"
      case .powerMode(let raw): return "Switch to \(PowerMode(rawValue: raw)?.title ?? "Automatic") mode"
      }
    }
  }

  enum Repeat: String, Codable, CaseIterable, Sendable {
    case never, daily, weekdays, weekly, biweekly, monthly, yearly

    var title: String {
      switch self {
      case .never: return "Never"
      case .daily: return "Daily"
      case .weekdays: return "Weekdays"
      case .weekly: return "Weekly"
      case .biweekly: return "Every two weeks"
      case .monthly: return "Monthly"
      case .yearly: return "Yearly"
      }
    }
  }

  var id = UUID()
  var action: Action
  var repeats: Repeat
  // The first run. Later runs keep its time of day (and weekday or day of month).
  var start: Date
  var isActive = true
  // Run a task that came due while the Mac was asleep or off as soon as it wakes.
  var runAtNextOpportunity = false
}

// One line of the task history.
struct TaskRun: Codable, Equatable, Identifiable, Sendable {
  enum Outcome: String, Codable, Sendable {
    case onTime
    case late // ran at the next opportunity
    case skipped // missed while asleep, not set to catch up
  }

  var id = UUID()
  var taskID: UUID
  var title: String
  var dueAt: Date
  var ranAt: Date
  var outcome: Outcome
}
