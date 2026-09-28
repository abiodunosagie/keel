import SwiftUI

// The charge limit slider. Dragging previews the value; macOS only gets the new limit when
// the drag ends, so powerd isn't flooded with writes.
struct LimitCard: View {
  @Environment(ChargeController.self) private var controller
  @State private var dragValue: Int?

  var body: some View {
    let range = controller.backend.limitRange
    let limit = dragValue ?? controller.settings.limit
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Charge limit")
        Spacer()
        Text(verbatim: "\(limit)%")
          .font(.title3.weight(.semibold))
          .monospacedDigit()
      }
      LimitSlider(range: range, value: limit, current: controller.displayPercent) { value, done in
        dragValue = done ? nil : value
        if done { controller.settings.limit = value }
      }
      HStack {
        ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 5)), id: \.self) { tick in
          Text(verbatim: "\(tick)")
          if tick != range.upperBound { Spacer() }
        }
      }
      .font(.caption2)
      .monospacedDigit()
      .foregroundStyle(.tertiary)
      Text(footnote)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.separator))
  }

  private var footnote: String {
    if controller.isTopUpActive { return "Top Up is on: charging to 100% until you unplug." }
    if let applied = controller.appliedLimit { return "macOS is holding the battery at \(applied)%, even while asleep." }
    return "No limit set. The battery charges to 100%."
  }
}

private struct LimitSlider: View {
  let range: ClosedRange<Int>
  let value: Int
  let current: Double?
  let onChange: (Int, _ done: Bool) -> Void

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let span = Double(range.upperBound - range.lowerBound)
      let position = { (percent: Double) in
        CGFloat((min(max(percent, Double(range.lowerBound)), Double(range.upperBound)) - Double(range.lowerBound)) / span) * width
      }
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary).frame(height: 4)
        Capsule().fill(Theme.held).frame(width: position(Double(value)), height: 4)
        if let current, current >= Double(range.lowerBound) {
          RoundedRectangle(cornerRadius: 1)
            .fill(.secondary)
            .frame(width: 2, height: 16)
            .offset(x: position(current) - 1)
            .help(String(format: "Battery now: %.0f%%", current))
        }
        Circle()
          .fill(.white)
          .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
          .frame(width: 20, height: 20)
          .offset(x: position(Double(value)) - 10)
      }
      .frame(height: 24)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { onChange(percent(at: $0.location.x, width: width), false) }
          .onEnded { onChange(percent(at: $0.location.x, width: width), true) }
      )
    }
    .frame(height: 24)
    .accessibilityElement()
    .accessibilityLabel("Charge limit")
    .accessibilityValue("\(value) percent")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: onChange(min(value + 1, range.upperBound), true)
      case .decrement: onChange(max(value - 1, range.lowerBound), true)
      @unknown default: break
      }
    }
  }

  private func percent(at x: CGFloat, width: CGFloat) -> Int {
    guard width > 0 else { return value }
    let fraction = min(max(x / width, 0), 1)
    return range.lowerBound + Int((Double(fraction) * Double(range.upperBound - range.lowerBound)).rounded())
  }
}
