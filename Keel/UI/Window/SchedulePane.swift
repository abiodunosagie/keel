import SwiftUI

struct SchedulePane: View {
  @Environment(Scheduler.self) private var scheduler
  @State private var editing: ScheduledTask?

  var body: some View {
    HStack(alignment: .top) {
      PaneHeader(title: "Schedule", lede: "Run actions at set times. A task missed while the Mac sleeps can run when it wakes.")
      Spacer()
      Menu("Add Task") {
        Button("New Task…") { editing = ScheduledTask(action: .topUp, repeats: .weekdays, start: Self.nextMorning) }
        Divider()
        Button("Calibrate every two weeks") {
          editing = ScheduledTask(action: .startCalibration, repeats: .biweekly, start: Self.nextMorning,
                                  runAtNextOpportunity: true)
        }
        Button("Top Up on weekday mornings") {
          editing = ScheduledTask(action: .topUp, repeats: .weekdays, start: Self.nextMorning,
                                  runAtNextOpportunity: true)
        }
        Button("Limit to 80% every night") {
          editing = ScheduledTask(action: .setLimit(80), repeats: .daily, start: Self.tonight)
        }
      }
      .fixedSize()
    }
    if scheduler.tasks.isEmpty {
      Text("No tasks yet. Add one, or start from a template in Add Task.")
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink3)
    } else {
      RowGroup {
        ForEach(scheduler.tasks) { task in
          SettingRow(title: task.action.title, detail: detail(task)) {
            HStack(spacing: 10) {
              Button("Edit") { editing = task }
              Toggle(task.action.title, isOn: Binding(
                get: { task.isActive },
                set: { active in
                  var changed = task
                  changed.isActive = active
                  scheduler.save(changed)
                }
              ))
              .labelsHidden()
              .toggleStyle(.switch)
            }
          }
        }
      }
    }
    HStack {
      Text("Task history").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      Spacer()
      if !scheduler.history.isEmpty {
        Button("Clear History") { scheduler.clearHistory() }
      }
    }
    .padding(.top, 6)
    if scheduler.history.isEmpty {
      Text("Tasks that ran, ran late after a wake, or were missed appear here.")
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink3)
    } else {
      RowGroup {
        ForEach(scheduler.history.prefix(20)) { run in
          HStack {
            Text(run.title).foregroundStyle(Theme.ink)
            outcomeTag(run.outcome)
            Spacer()
            Text(run.ranAt.formatted(date: .abbreviated, time: .shortened))
              .font(Theme.mono(12))
              .foregroundStyle(Theme.ink2)
          }
          .font(.system(size: 12))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
        }
      }
    }
    Text("Keel checks the schedule once a minute. A sleeping Mac only runs tasks when it wakes, so for night tasks turn on \"Run when the Mac wakes\".")
      .font(.system(size: 11.5))
      .foregroundStyle(Theme.ink3)
      .fixedSize(horizontal: false, vertical: true)
      .sheet(item: $editing) { task in
        TaskEditor(task: task, isNew: !scheduler.tasks.contains { $0.id == task.id })
      }
  }

  private func detail(_ task: ScheduledTask) -> String {
    let when = task.start.formatted(date: task.repeats == .never ? .abbreviated : .omitted, time: .shortened)
    var text = "\(task.repeats.title), \(when)"
    if let next = scheduler.nextRun(of: task) {
      text += ". Next: \(next.formatted(date: .abbreviated, time: .shortened))"
    }
    if task.runAtNextOpportunity { text += ". Runs when the Mac wakes if missed" }
    return text + "."
  }

  private func outcomeTag(_ outcome: TaskRun.Outcome) -> some View {
    let (text, color): (String, Color) = switch outcome {
    case .onTime: ("done", Theme.held)
    case .late: ("ran at wake", Theme.moving)
    case .skipped: ("missed", Theme.ink3)
    }
    return Text(text.uppercased())
      .font(.system(size: 9.5, weight: .semibold))
      .kerning(0.5)
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
  }

  private static var nextMorning: Date {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
    return calendar.date(bySettingHour: 6, minute: 30, second: 0, of: tomorrow) ?? tomorrow
  }

  private static var tonight: Date {
    Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: .now) ?? .now
  }
}
