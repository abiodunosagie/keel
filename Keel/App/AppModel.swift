import AppKit
import Observation

// Sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
  case dashboard, history, charge, schedule, automation, calibration, appearance, general

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dashboard: return "Dashboard"
    case .history: return "History"
    case .charge: return "Charge"
    case .schedule: return "Schedule"
    case .automation: return "Automation"
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
    case .automation: return "wand.and.stars"
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
  let automation: Automation
  var section: AppSection = .dashboard
  @ObservationIgnored private(set) lazy var windows = WindowManager(model: self)
  @ObservationIgnored private var statusItem: StatusItemController?
  var popoverLayout: PopoverLayout {
    didSet { store.popoverLayout = popoverLayout }
  }
  var isEditingPopover = false
  let store = SettingsStore()

  private init() {
    popoverLayout = SettingsStore().popoverLayout
    scheduler = Scheduler(controller: controller, helper: helper)
    automation = Automation(controller: controller)
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
    statusItem = StatusItemController(model: self)
    applyAppearance()
    observeAppearance()
    showFirstRunWindows()
    helper.refreshStatus()
    await helper.replaceIfOutdated()
    await controller.start()
    history.start(reading: { [controller] in controller.snapshot })
    await history.importPowerLog()
    scheduler.start()
    automation.start()
    Hotkeys.install(model: self)
  }

  func showPopover() {
    statusItem?.showPopover()
  }

  func togglePopover() {
    statusItem?.togglePopover()
  }

  func open(_ section: AppSection) {
    statusItem?.closePopover()
    windows.showMain(section: section)
  }

  // Light, dark or following macOS, and a Dock icon when asked for or when the menu bar icon
  // is hidden (otherwise Keel would be unreachable).
  private func applyAppearance() {
    let options = controller.options
    switch options.appearance {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    let wantsDock = options.showDockIcon || options.hideMenuBarIcon
    NSApp.setActivationPolicy(wantsDock ? .regular : .accessory)
  }

  private func observeAppearance() {
    withObservationTracking {
      _ = controller.options
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.applyAppearance()
        self?.observeAppearance()
      }
    }
  }

  // The setup guide on a first install, What's New after an update.
  private func showFirstRunWindows() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    if !store.hasOnboarded {
      windows.showOnboarding()
    } else if store.lastSeenVersion != version, ReleaseNotes.notes(for: version) != nil {
      windows.showWhatsNew()
    }
    store.lastSeenVersion = version
  }

  func prepareForQuit() async {
    guard !Self.isRunningTests else { return }
    await controller.prepareForQuit()
    history.flush()
  }
}
