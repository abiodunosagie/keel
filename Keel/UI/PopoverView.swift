import SwiftUI

// The menu bar popover. Plain sections split by dividers, in the style of the system's own
// menu bar modules: the level, the limit, the actions, the details, then the app's commands.
// Hold a section (or right-click it) to rearrange or hide sections; the layout is saved.
struct PopoverView: View {
  @Environment(AppModel.self) private var model
  @Environment(ChargeController.self) private var controller

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.isEditingPopover {
        PopoverEditor()
      } else if let snapshot = controller.snapshot {
        ForEach(Array(model.popoverLayout.visible.enumerated()), id: \.element) { index, card in
          if index > 0 { SectionDivider() }
          section(for: card, snapshot: snapshot)
        }
      } else {
        Text("No battery found.")
          .foregroundStyle(.secondary)
          .padding(.vertical, 10)
      }
      if let error = controller.lastError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(Theme.heat)
          .padding(.vertical, 8)
      }
      SectionDivider()
      PopoverCommands(open: model.open)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(width: 300)
    .background(controller.options.reduceTransparency ? Theme.surface : .clear)
  }

  @ViewBuilder
  private func section(for card: PopoverLayout.Card, snapshot: BatterySnapshot) -> some View {
    let content = cardView(card, snapshot: snapshot)
    if card.isInteractive {
      // The slider and rows keep their own gestures; right-click still offers the editor.
      content.contextMenu { customizeButton }
    } else {
      content
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) { model.isEditingPopover = true }
        .contextMenu { customizeButton }
    }
  }

  private var customizeButton: some View {
    Button("Customize Sections…") { model.isEditingPopover = true }
  }

  @ViewBuilder
  private func cardView(_ card: PopoverLayout.Card, snapshot: BatterySnapshot) -> some View {
    switch card {
    case .summary:
      LevelSection(snapshot: snapshot)
    case .limit:
      if controller.isAvailable {
        LimitSection()
      } else {
        Text(controller.unavailableReason)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.vertical, 10)
      }
    case .actions:
      if controller.isAvailable { ActionList(open: model.open) }
    case .powerFlow:
      PowerSection(snapshot: snapshot)
    case .stats:
      BatteryDetailsSection(snapshot: snapshot)
    case .charger:
      ChargerSection(snapshot: snapshot)
    case .chart:
      MiniChart()
    }
  }
}

// The battery level as one number, with what is happening right now under it.
private struct LevelSection: View {
  @Environment(ChargeController.self) private var controller
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let snapshot: BatterySnapshot

  var body: some View {
    let percent = Int((controller.displayPercent ?? 0).rounded())
    let color = Theme.color(for: controller.state)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: "\(percent)%")
          .font(.system(size: 30, weight: .semibold))
          .monospacedDigit()
          .contentTransition(.numericText(value: Double(percent)))
          .animation(reduceMotion ? nil : .snappy, value: percent)
        Label(controller.state.title, systemImage: controller.state.symbol)
          .font(.callout.weight(.medium))
          .foregroundStyle(color)
          .help(controller.state == .macOSOverride
                ? Text("macOS sometimes charges to 100% to recalibrate its battery gauge. It goes back to the limit afterwards.")
                : Text(verbatim: ""))
        if let detail {
          Text(detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      // On battery the state colour is a neutral grey; the mark keeps the brand green for the level.
      LiveMark(level: Double(percent) / 100, limit: controller.displayLimit,
               color: controller.state == .onBattery ? Theme.held : color)
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private var detail: String? {
    let limit = controller.effectiveSettings.limit
    switch controller.state {
    case .onBattery:
      return snapshot.minutesToEmpty.map { String(localized: "\(Format.duration($0)) left") }
    case .charging:
      if let minutes = snapshot.minutesToFull { return String(localized: "Full in \(Format.duration(minutes))") }
      return String(localized: "Charging to \(limit)%")
    case .topUp:
      return String(localized: "Charging to 100% until you unplug")
    case .macOSOverride:
      return String(localized: "Back to your limit afterwards")
    case .discharging:
      return String(localized: "Using the battery down to \(limit)%")
    case .heatProtect:
      return String(localized: "Charging resumes when the battery cools")
    case .calibration:
      return controller.calibrationStep?.title
    case .paused:
      return String(localized: "Running on the charger, battery resting")
    case .unavailable:
      return nil
    }
  }
}

extension ChargeState {
  var symbol: String {
    switch self {
    case .charging, .macOSOverride: return "bolt.fill"
    case .topUp: return "bolt.badge.clock.fill"
    case .paused: return "checkmark.circle.fill"
    case .discharging: return "arrow.down.circle.fill"
    case .heatProtect: return "thermometer.high"
    case .calibration: return "arrow.triangle.2.circlepath"
    case .onBattery: return "battery.75percent"
    case .unavailable: return "exclamationmark.circle"
    }
  }
}
