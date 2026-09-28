import SwiftUI

// The menu bar popover, laid out as in the approved mockup.
struct PopoverView: View {
  @Environment(AppModel.self) private var model
  @Environment(ChargeController.self) private var controller
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if let snapshot = controller.snapshot {
        summary(snapshot)
        if controller.isAvailable {
          LimitCard()
          ActionRow(open: open)
        } else {
          Text(ChargeBackendError.unavailable.errorDescription ?? "")
            .font(.callout)
            .foregroundStyle(Theme.ink2)
        }
        PowerFlowRow(snapshot: snapshot)
        StatsRow(snapshot: snapshot)
      } else {
        Text("No battery found.").foregroundStyle(Theme.ink2)
      }
      if let error = controller.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(Theme.heat)
      }
    }
    .padding(14)
    .frame(width: 340)
    .background(Theme.surface)
  }

  private var header: some View {
    HStack {
      StatePill(state: controller.state)
      Spacer()
      Button { open(.dashboard) } label: {
        Label("Open Dashboard", systemImage: "square.grid.2x2").labelStyle(.iconOnly)
      }
      .help("Open Dashboard")
      Button { open(.charge) } label: {
        Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
      }
      .help("Settings")
    }
    .buttonStyle(IconButtonStyle())
  }

  private func summary(_ snapshot: BatterySnapshot) -> some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(alignment: .lastTextBaseline, spacing: 1) {
        Text(verbatim: "\(Int((controller.displayPercent ?? 0).rounded()))")
          .font(.system(size: 46, weight: .semibold))
          .monospacedDigit()
        Text(verbatim: "%")
          .font(Theme.mono(20, weight: .medium))
          .foregroundStyle(Theme.ink3)
      }
      .foregroundStyle(Theme.ink)
      Text(detail(snapshot))
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func detail(_ snapshot: BatterySnapshot) -> String {
    let other = controller.settings.useHardwarePercent
      ? "macOS shows \(snapshot.macOSPercent)%."
      : String(format: "Hardware reads %.1f%%.", snapshot.hardwarePercent)
    switch controller.state {
    case .onBattery:
      if let minutes = snapshot.minutesToEmpty { return "On battery, \(Format.duration(minutes)) left. \(other)" }
      return "On battery. \(other)"
    case .charging, .topUp, .macOSOverride:
      if let minutes = snapshot.minutesToFull { return "Charging, full in \(Format.duration(minutes)). \(other)" }
      return "Plugged in and charging. \(other)"
    case .discharging:
      return "Plugged in, running on battery down to the limit. \(other)"
    case .heatProtect:
      return "Charging paused until the battery cools. \(other)"
    case .calibration:
      return "\(controller.calibrationStep?.title ?? "Calibrating"). \(other)"
    case .paused:
      return "Plugged in, running on the charger. \(other) Battery idle."
    case .unavailable:
      return other
    }
  }

  private func open(_ section: AppSection) {
    model.section = section
    openWindow(id: MainWindow.id)
    NSApp.activate()
  }
}

private struct StatePill: View {
  let state: ChargeState

  var body: some View {
    let color = Theme.color(for: state)
    HStack(spacing: 7) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 3))
      Text(state.title)
    }
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(color)
    .padding(.vertical, 4)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .background(color.opacity(0.15), in: Capsule())
    .help(state == .macOSOverride
          ? "macOS sometimes charges to 100% to recalibrate its battery gauge. It goes back to the limit afterwards."
          : "")
  }
}

struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14))
      .foregroundStyle(Theme.ink2)
      .frame(width: 26, height: 26)
      .background(configuration.isPressed ? Theme.line : .clear, in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
  }
}
