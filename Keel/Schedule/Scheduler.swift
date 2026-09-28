import AppKit
import Foundation
import Observation

// Keeps the scheduled tasks and their history, and runs whatever falls due. Checks once a
// minute and right after the Mac wakes.
@MainActor
@Observable
final class Scheduler {
  static let historyLimit = 100
  static let checkInterval: TimeInterval = 60

  private(set) var tasks: [ScheduledTask] = []
  private(set) var history: [TaskRun] = []

  private let controller: ChargeController
  private weak var helper: HelperClient?
  private let defaults: UserDefaults
  private let clock: @MainActor () -> Date
  private var engine = ScheduleEngine()
  private var timer: Timer?
  private var wakeObserver: NSObjectProtocol?

  private enum Key {
    static let tasks = "scheduledTasks"
    static let history = "taskHistory"
    static let lastCheck = "scheduleLastCheck"
  }

  init(
    controller: ChargeController,
    helper: HelperClient?,
    defaults: UserDefaults = .standard,
    clock: @escaping @MainActor () -> Date = { .now }
  ) {
    self.controller = controller
    self.helper = helper
    self.defaults = defaults
    self.clock = clock
    tasks = decode([ScheduledTask].self, Key.tasks) ?? []
    history = decode([TaskRun].self, Key.history) ?? []
  }

  func start() {
    if defaults.object(forKey: Key.lastCheck) == nil { lastCheck = clock() }
    check()
    timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
  }

  func save(_ task: ScheduledTask) {
    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
      tasks[index] = task
    } else {
      tasks.append(task)
    }
    persist()
  }

  func delete(_ task: ScheduledTask) {
    tasks.removeAll { $0.id == task.id }
    persist()
  }

  func clearHistory() {
    history.removeAll()
    persist()
  }

  func nextRun(of task: ScheduledTask) -> Date? {
    guard task.isActive else { return nil }
    return engine.nextOccurrence(of: task, after: clock())
  }

  func check() {
    let now = clock()
    let due = engine.due(tasks, lastCheck: lastCheck, now: now)
    lastCheck = now
    for item in due {
      if item.outcome != .skipped { perform(item.task.action) }
      history.insert(TaskRun(taskID: item.task.id, title: item.task.action.title, dueAt: item.dueAt,
                             ranAt: now, outcome: item.outcome), at: 0)
      if item.task.repeats == .never, var finished = tasks.first(where: { $0.id == item.task.id }) {
        finished.isActive = false
        save(finished)
      }
    }
    if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    if !due.isEmpty { persist() }
  }

  func perform(_ action: ScheduledTask.Action) {
    switch action {
    case .setLimit(let percent):
      controller.setLimit(percent)
    case .topUp:
      controller.startTopUp()
    case .pauseCharging:
      controller.pauseCharging()
    case .dischargeTo(let percent):
      controller.setLimit(percent)
      controller.startDischarge()
    case .startCalibration:
      controller.startCalibration()
    case .powerMode(let raw):
      guard let mode = PowerMode(rawValue: raw), let helper else { return }
      Task { await helper.setPowerMode(mode) }
    }
  }

  private var lastCheck: Date {
    get { defaults.object(forKey: Key.lastCheck) as? Date ?? clock() }
    set { defaults.set(newValue, forKey: Key.lastCheck) }
  }

  private func persist() {
    defaults.set(try? JSONEncoder().encode(tasks), forKey: Key.tasks)
    defaults.set(try? JSONEncoder().encode(history), forKey: Key.history)
  }

  private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}
