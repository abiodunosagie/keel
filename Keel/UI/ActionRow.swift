import SwiftUI

// Top Up, Discharge and Calibrate, as in the mockup.
struct ActionRow: View {
  @Environment(ChargeController.self) private var controller
  let open: (AppSection) -> Void

  var body: some View {
    HStack(spacing: 8) {
      ActionTile(
        title: controller.isTopUpActive ? String(localized: "Stop Top Up") : String(localized: "Top Up"),
        symbol: "bolt",
        isActive: controller.isTopUpActive,
        isEnabled: controller.isTopUpActive || (controller.snapshot?.isPluggedIn ?? false),
        help: controller.snapshot?.isPluggedIn == true
          ? String(localized: "Charge to 100% until you unplug, then go back to your limit.")
          : String(localized: "Plug in the charger to top up.")
      ) {
        controller.isTopUpActive ? controller.stopTopUp() : controller.startTopUp()
      }
      ActionTile(
        title: controller.mode == .discharge ? String(localized: "Stop") : String(localized: "Discharge"),
        symbol: "arrow.down.to.line",
        isActive: controller.mode == .discharge,
        isEnabled: controller.mode == .discharge || controller.canDischarge,
        help: controller.canDischarge || controller.mode == .discharge
          ? String(localized: "Run on battery down to your limit, then go back to the charger.")
          : String(localized: "Discharge works on the charger when the battery is above the limit.")
      ) {
        controller.mode == .discharge ? controller.stopDischarge() : controller.startDischarge()
      }
      ActionTile(
        title: controller.calibrationStep == nil ? String(localized: "Calibrate") : String(localized: "Calibrating"),
        symbol: "arrow.clockwise",
        isActive: controller.calibrationStep != nil,
        isEnabled: true,
        help: controller.calibrationBlocker
          ?? String(localized: "Charge to 100%, down to \(Calibration.floor)%, back to 100%, hold an hour, then your limit.")
      ) {
        if controller.calibrationStep == nil, controller.calibrationBlocker == nil {
          controller.startCalibration()
        } else {
          open(.calibration)
        }
      }
    }
  }
}

private struct ActionTile: View {
  let title: String
  let symbol: String
  let isActive: Bool
  let isEnabled: Bool
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .regular))
          .foregroundStyle(isActive ? Theme.moving : Theme.accent)
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Theme.ink)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .panel(radius: 10)
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isActive ? Theme.moving : .clear))
    .opacity(isEnabled ? 1 : 0.45)
    .disabled(!isEnabled)
    .help(help)
  }
}
