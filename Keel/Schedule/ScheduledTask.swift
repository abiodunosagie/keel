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
    case powerMode(PowerMode)

    var title: String {
      switch self {
      case .setLimit(let percent): return String(localized: "Set charge limit to \(percent)%")
      case .topUp: return String(localized: "Top Up")
      case .pauseCharging: return String(localized: "Pause charging")
      case .dischargeTo(let percent): return String(localized: "Discharge to \(percent)%")
      case .startCalibration: return String(localized: "Start calibration")
      case .powerMode(let mode): return String(localized: "Switch to \(mode.title) mode")
      }
    }
  }

  enum Repeat: String, Codable, CaseIterable, Sendable {
    case never, daily, weekdays, weekly, biweekly, monthly, yearly

    var title: String {
      switch self {
      case .never: return String(localized: "Never")
      case .daily: return String(localized: "Daily")
      case .weekdays: return String(localized: "Weekdays")
      case .weekly: return String(localized: "Weekly")
      case .biweekly: return String(localized: "Every two weeks")
      case .monthly: return String(localized: "Monthly")
      case .yearly: return String(localized: "Yearly")
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
  var title: String
  var dueAt: Date
  var ranAt: Date
  var outcome: Outcome
}
