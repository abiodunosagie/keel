import SwiftUI

// The charge limit: a system slider from 80 to 100. Dragging previews the value; macOS only gets
// the new limit when the drag ends, so powerd isn't flooded with writes. Arrow keys commit each step.
struct LimitSection: View {
  @Environment(ChargeController.self) private var controller
  @State private var draft: Int?
  @State private var isDragging = false

  var body: some View {
    let range = controller.limitRange
    let limit = draft ?? controller.effectiveSettings.limit
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("Charge limit")
          .font(.callout.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
        Text(verbatim: "\(limit)%")
          .font(.title3.weight(.semibold))
          .monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { Double(limit) },
          set: { value in
            let step = Int(value.rounded())
            draft = step
            // Keyboard and accessibility changes arrive without a drag; send those at once.
            if !isDragging { commit(step) }
          }
        ),
        in: Double(range.lowerBound)...Double(range.upperBound),
        step: 1
      ) {
        Text("Charge limit")
      } minimumValueLabel: {
        Text(verbatim: "\(range.lowerBound)").monospacedDigit()
      } maximumValueLabel: {
        Text(verbatim: "\(range.upperBound)").monospacedDigit()
      } onEditingChanged: { editing in
        isDragging = editing
        if !editing, let draft { commit(draft) }
      }
      .labelsHidden()
      .controlSize(.small)
      .tint(Theme.held)
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityValue(controller.displayPercent.map { String(localized: "\(limit) percent, battery now \(Int($0.rounded())) percent") }
                          ?? String(localized: "\(limit) percent"))
      Text(footnote)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 10)
    // Closing the popover mid-drag can skip the end of the drag; send what was chosen anyway.
    .onDisappear {
      isDragging = false
      if let draft { commit(draft) }
    }
  }

  private func commit(_ value: Int) {
    draft = nil
    guard value != controller.effectiveSettings.limit else { return }
    controller.setLimit(value)
  }

  private var footnote: String {
    switch controller.mode {
    case .topUp: return String(localized: "Top Up is on: charging to 100% until you unplug.")
    case .discharge: return String(localized: "Running on battery down to your limit.")
    case .calibration(let step): return String(localized: "Calibrating: \(step.title).")
    case .normal: break
    }
    if let network = controller.networkLimit {
      return String(localized: "\(network.limit)% on \(network.network). Changing it here applies until you switch networks.")
    }
    let limit = controller.effectiveSettings.limit
    let hardware = controller.settings.useHardwarePercent
    if let applied = controller.appliedLimit {
      return hardware && applied != limit
        ? String(localized: "Charging stops here (\(applied)% in macOS), even while asleep or with Keel closed.")
        : String(localized: "Charging stops here, even while asleep or with Keel closed.")
    }
    // On the chip's scale a high limit can land on 100% for macOS, which means no limit at all.
    if hardware, limit < controller.limitRange.upperBound {
      return String(localized: "\(limit)% on the chip is 100% in macOS right now, so nothing stops charging. Lower the limit.")
    }
    return String(localized: "No limit. The battery charges to 100%.")
  }
}
