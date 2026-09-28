import SwiftUI

// Adds or edits one scheduled task.
struct TaskEditor: View {
  @Environment(Scheduler.self) private var scheduler
  @Environment(ChargeController.self) private var controller
  @Environment(\.dismiss) private var dismiss
  @State private var task: ScheduledTask
  @State private var kind: Kind
  @State private var percent: Int
  @State private var powerMode: PowerMode
  let isNew: Bool

  // What a new percent-based action starts at.
  private static let defaultPercent = 80

  enum Kind: String, CaseIterable, Identifiable {
    case setLimit, topUp, pauseCharging, dischargeTo, startCalibration, powerMode

    var id: String { rawValue }

    var title: String {
      switch self {
      case .setLimit: return String(localized: "Set charge limit")
      case .topUp: return String(localized: "Top Up")
      case .pauseCharging: return String(localized: "Pause charging")
      case .dischargeTo: return String(localized: "Discharge to")
      case .startCalibration: return String(localized: "Start calibration")
      case .powerMode: return String(localized: "Switch power mode")
      }
    }
  }

  init(task: ScheduledTask, isNew: Bool) {
    self.isNew = isNew
    _task = State(initialValue: task)
    switch task.action {
    case .setLimit(let value):
      _kind = State(initialValue: .setLimit)
      _percent = State(initialValue: value)
      _powerMode = State(initialValue: .automatic)
    case .dischargeTo(let value):
      _kind = State(initialValue: .dischargeTo)
      _percent = State(initialValue: value)
      _powerMode = State(initialValue: .automatic)
    case .powerMode(let mode):
      _kind = State(initialValue: .powerMode)
      _percent = State(initialValue: Self.defaultPercent)
      _powerMode = State(initialValue: mode)
    case .topUp:
      _kind = State(initialValue: .topUp)
      _percent = State(initialValue: Self.defaultPercent)
      _powerMode = State(initialValue: .automatic)
    case .pauseCharging:
      _kind = State(initialValue: .pauseCharging)
      _percent = State(initialValue: Self.defaultPercent)
      _powerMode = State(initialValue: .automatic)
    case .startCalibration:
      _kind = State(initialValue: .startCalibration)
      _percent = State(initialValue: Self.defaultPercent)
      _powerMode = State(initialValue: .automatic)
    }
  }

  var body: some View {
    Form {
      Picker("Action", selection: $kind) {
        ForEach(Kind.allCases) { Text($0.title).tag($0) }
      }
      if kind == .setLimit || kind == .dischargeTo {
        Stepper(value: $percent, in: controller.limitRange) {
          LabeledContent("Percent", value: "\(percent)%")
        }
      }
      if kind == .powerMode {
        Picker("Mode", selection: $powerMode) {
          ForEach(PowerMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      }
      Picker("Repeat", selection: $task.repeats) {
        ForEach(ScheduledTask.Repeat.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      DatePicker("Starts", selection: $task.start)
      Toggle("Run when the Mac wakes if missed", isOn: $task.runAtNextOpportunity)
      Toggle("Active", isOn: $task.isActive)
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button(isNew ? "Add" : "Save") {
          task.action = action
          scheduler.save(task)
          dismiss()
        }
      }
      if !isNew {
        ToolbarItem(placement: .destructiveAction) {
          Button("Delete", role: .destructive) {
            scheduler.delete(task)
            dismiss()
          }
        }
      }
    }
  }

  private var action: ScheduledTask.Action {
    let percent = controller.limitRange.clamped(percent)
    switch kind {
    case .setLimit: return .setLimit(percent)
    case .topUp: return .topUp
    case .pauseCharging: return .pauseCharging
    case .dischargeTo: return .dischargeTo(percent)
    case .startCalibration: return .startCalibration
    case .powerMode: return .powerMode(powerMode)
    }
  }
}
