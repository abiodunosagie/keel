import AppKit
import Observation

// Sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
  case dashboard, history, charge, schedule, calibration, appearance, general

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dashboard: return "Dashboard"
    case .history: return "History"
    case .charge: return "Charge"
    case .schedule: return "Schedule"
    case .calibration: return "Calibration"
    case .appearance: return "Appearance"
    case .general: return "General"
    }
  }

  var symbol: String {
    switch self {
    case .dashboard: return "chart.bar.xaxis"
    case .history: return "heart.text.square"
    case .charge: return "battery.75percent"
    case .schedule: return "calendar"
    case .calibration: return "arrow.triangle.2.circlepath"
    case .appearance: return "circle.lefthalf.filled"
    case .general: return "gearshape"
    }
  }
}

// Everything the app runs, created once. Shortcuts reach the same objects through `shared`.
@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  let controller = ChargeController()
  let helper = HelperClient()
  let history = BatteryHistory()
  let scheduler: Scheduler
  let notifier = Notifier()
  let insights = PowerInsights()
  var section: AppSection = .dashboard

  private init() {
    scheduler = Scheduler(controller: controller, helper: helper)
    controller.charger = helper
    controller.onEvent = { [notifier, controller] event in
      guard controller.options.notifications else { return }
      notifier.post(event)
    }
    controller.onRefresh = { [insights] snapshot, drainExpected in
      insights.update(snapshot, drainExpected: drainExpected, now: .now)
    }
    insights.onProblem = { [controller] problem in
      controller.onEvent?(.chargerProblem(problem.message))
    }
  }

  // Tests host the app binary; they must never drive powerd, the helper or the schedule.
  static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  func start() async {
    guard !Self.isRunningTests else { return }
    helper.refreshStatus()
    await helper.replaceIfOutdated()
    await controller.start()
    history.start(reading: { [controller] in controller.snapshot })
    await history.importPowerLog()
    scheduler.start()
  }

  func prepareForQuit() async {
    guard !Self.isRunningTests else { return }
    await controller.prepareForQuit()
    history.flush()
  }
}
