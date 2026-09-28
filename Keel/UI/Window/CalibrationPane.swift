import SwiftUI

struct CalibrationPane: View {
  @Environment(ChargeController.self) private var controller

  private static let steps: [CalibrationStep] = [
    .chargeFull, .dischargeLow, .rechargeFull, .hold(until: .distantFuture), .returnToLimit,
  ]

  var body: some View {
    PaneHeader(title: String(localized: "Calibration"), lede: lede)
    RowGroup {
      HStack(spacing: 6) {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
          stepChip(index == 4 ? String(localized: "Back to \(controller.settings.limit)%") : step.title, index: index)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      SettingRow(title: statusTitle, detail: statusDetail) {
        if controller.calibrationStep != nil {
          Button("Stop") { controller.stopCalibration() }
        } else {
          Button("Start Calibration") { controller.startCalibration() }
            .disabled(controller.calibrationBlocker != nil)
        }
      }
    }
    Text("Calibration keeps the Mac awake and pauses Heat Protection until it ends. Run it every 3 weeks if the Mac is always plugged in, every 4 to 6 weeks otherwise. Schedule it under Schedule.")
      .font(.system(size: 11.5))
      .foregroundStyle(Theme.ink3)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var lede: String {
    guard let last = controller.lastCalibration else {
      return String(localized: "A full cycle keeps the battery's percentage reading accurate. Not run yet.")
    }
    let days = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
    return days == 0
      ? String(localized: "A full cycle keeps the battery's percentage reading accurate. Last run today.")
      : String(localized: "A full cycle keeps the battery's percentage reading accurate. Last run \(days) days ago.")
  }

  private var statusTitle: String {
    guard let step = controller.calibrationStep else { return String(localized: "Ready") }
    let percent = controller.snapshot.map { " \($0.macOSPercent)%" } ?? ""
    return "\(step.title),\(percent)"
  }

  private var statusDetail: String {
    if let step = controller.calibrationStep {
      if case .hold(let until) = step {
        return String(localized: "Holding at 100% until \(until.formatted(date: .omitted, time: .shortened)). The Mac stays awake until the cycle ends.")
      }
      return String(localized: "The Mac stays awake until the cycle ends. Unplugging during a charging step stops it.")
    }
    return controller.calibrationBlocker ?? String(localized: "Takes a few hours depending on how busy the Mac is.")
  }

  private func stepChip(_ title: String, index: Int) -> some View {
    let current = controller.calibrationStep?.index
    let done = current.map { index < $0 } ?? false
    let active = current == index
    return Text(title)
      .font(.system(size: 11.5, weight: active ? .semibold : .regular))
      .foregroundStyle(active ? Theme.moving : done ? Theme.held : Theme.ink2)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        active ? Theme.moving.opacity(0.15) : done ? Theme.held.opacity(0.15) : Theme.chip,
        in: RoundedRectangle(cornerRadius: 6)
      )
  }
}
