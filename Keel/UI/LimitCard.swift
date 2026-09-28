import SwiftUI

// The charge limit slider. Dragging previews the value; macOS only gets the new limit when
// the drag ends, so powerd isn't flooded with writes.
struct LimitCard: View {
  @Environment(ChargeController.self) private var controller
  @State private var dragValue: Int?

  var body: some View {
    let range = controller.limitRange
    let limit = dragValue ?? controller.effectiveSettings.limit
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Charge limit")
          .font(.system(size: 14))
        Spacer()
        Text(verbatim: "\(limit)%")
          .font(.system(size: 18, weight: .semibold))
          .monospacedDigit()
      }
      .foregroundStyle(Theme.ink)
      LimitSlider(
        range: range,
        value: limit,
        current: controller.displayPercent,
        onDrag: { dragValue = $0 },
        onCommit: { value in
          dragValue = nil
          controller.setLimit(value)
        }
      )
      HStack {
        ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 5)), id: \.self) { tick in
          Text(verbatim: "\(tick)")
          if tick != range.upperBound { Spacer() }
        }
      }
      .font(Theme.mono(11))
      .foregroundStyle(Theme.ink3)
      Text(footnote)
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.ink3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .panel()
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
    if let applied = controller.appliedLimit {
      let scale = controller.settings.useHardwarePercent && applied != controller.settings.limit
        ? String(localized: " (\(applied)% as macOS counts it)") : ""
      return String(localized: "Held by macOS\(scale), keeps working while asleep and when Keel is closed.")
    }
    return String(localized: "No limit. The battery charges to 100%.")
  }
}

private struct LimitSlider: View {
  let range: ClosedRange<Int>
  let value: Int
  let current: Double?
  let onDrag: (Int) -> Void
  let onCommit: (Int) -> Void

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track).frame(height: 5)
        Capsule().fill(Theme.held).frame(width: position(Double(value), width), height: 5)
        if let current, current >= Double(range.lowerBound) {
          RoundedRectangle(cornerRadius: 1)
            .fill(Theme.ink3)
            .frame(width: 2, height: 18)
            .offset(x: position(current, width) - 1)
            .help(String(localized: "Battery now: \(Int(current.rounded()))%"))
        }
        Circle()
          .fill(.white)
          .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
          .frame(width: 22, height: 22)
          .offset(x: position(Double(value), width) - 11)
      }
      .frame(height: 26)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { onDrag(percent(at: $0.location.x, width: width)) }
          .onEnded { onCommit(percent(at: $0.location.x, width: width)) }
      )
    }
    .frame(height: 26)
    .focusable()
    .onKeyPress(.leftArrow) {
      onCommit(max(value - 1, range.lowerBound))
      return .handled
    }
    .onKeyPress(.rightArrow) {
      onCommit(min(value + 1, range.upperBound))
      return .handled
    }
    .accessibilityElement()
    .accessibilityLabel("Charge limit")
    .accessibilityValue(current.map { String(localized: "\(value) percent, battery now \(Int($0.rounded())) percent") }
                        ?? String(localized: "\(value) percent"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: onCommit(min(value + 1, range.upperBound))
      case .decrement: onCommit(max(value - 1, range.lowerBound))
      @unknown default: break
      }
    }
  }

  private func position(_ percent: Double, _ width: CGFloat) -> CGFloat {
    let span = Double(range.upperBound - range.lowerBound)
    let clamped = min(max(percent, Double(range.lowerBound)), Double(range.upperBound))
    return CGFloat((clamped - Double(range.lowerBound)) / span) * width
  }

  private func percent(at x: CGFloat, width: CGFloat) -> Int {
    guard width > 0 else { return value }
    let fraction = min(max(x / width, 0), 1)
    return range.lowerBound + Int((Double(fraction) * Double(range.upperBound - range.lowerBound)).rounded())
  }
}
