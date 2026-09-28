import SwiftUI

struct PopoverView: View {
  @Environment(ChargeController.self) private var controller

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if let snapshot = controller.snapshot {
        summary(snapshot)
        if controller.isAvailable {
          LimitCard()
          actions
        } else {
          Text(ChargeBackendError.unavailable.errorDescription ?? "")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        PowerFlowRow(snapshot: snapshot)
        StatsRow(snapshot: snapshot)
      } else {
        Text("No battery found.")
          .foregroundStyle(.secondary)
      }
      if let error = controller.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(Theme.heat)
      }
    }
    .padding(14)
    .frame(width: 320)
  }

  private var header: some View {
    HStack {
      StatePill(state: controller.state)
      Spacer()
      SettingsLink {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Settings")
      Button {
        NSApp.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .buttonStyle(.borderless)
      .help("Quit Keel. The charge limit stays on.")
    }
  }

  private func summary(_ snapshot: BatterySnapshot) -> some View {
    HStack(alignment: .lastTextBaseline, spacing: 12) {
      Text(verbatim: "\(Int((controller.displayPercent ?? 0).rounded()))")
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .monospacedDigit()
      + Text(verbatim: "%")
        .font(.system(size: 20, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
      Text(detail(snapshot))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func detail(_ snapshot: BatterySnapshot) -> String {
    let other = controller.settings.useHardwarePercent
      ? "macOS shows \(snapshot.macOSPercent)%."
      : String(format: "Hardware reads %.1f%%.", snapshot.hardwarePercent)
    switch controller.state {
    case .onBattery:
      if let minutes = snapshot.minutesToEmpty { return "\(Format.duration(minutes)) left. \(other)" }
      return other
    case .charging, .topUp, .macOSOverride:
      if let minutes = snapshot.minutesToFull { return "Full in \(Format.duration(minutes)). \(other)" }
      return "Plugged in and charging. \(other)"
    case .discharging:
      return "Running on battery down to the limit. \(other)"
    case .heatProtect:
      return "Charging resumes when the battery cools. \(other)"
    case .paused:
      return "Running on the charger. \(other)"
    case .unavailable:
      return other
    }
  }

  private var actions: some View {
    HStack(spacing: 8) {
      ActionButton(
        title: controller.isTopUpActive ? "Stop Top Up" : "Top Up",
        symbol: "bolt.fill",
        help: "Charge to 100% until you unplug, then go back to your limit."
      ) {
        controller.isTopUpActive ? controller.stopTopUp() : controller.startTopUp()
      }
      ActionButton(title: "Pause Here", symbol: "pause.fill",
                   help: "Set the limit to the current level so the battery stays where it is.") {
        controller.pauseCharging()
      }
    }
  }
}

private struct StatePill: View {
  let state: ChargeState

  var body: some View {
    let color = Theme.color(for: state)
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(state.title)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(color)
    .padding(.vertical, 4)
    .padding(.horizontal, 9)
    .background(color.opacity(0.14), in: Capsule())
    .help(state == .macOSOverride
          ? "macOS sometimes charges to 100% to recalibrate its battery gauge. It goes back to the limit afterwards."
          : "")
  }
}

private struct ActionButton: View {
  let title: String
  let symbol: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol).foregroundStyle(Theme.accent)
        Text(title).font(.caption)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
    .help(help)
  }
}
