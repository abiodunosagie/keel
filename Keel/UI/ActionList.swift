import SwiftUI

// Top Up, Discharge and Calibrate as rows: a round icon, a title and one line saying what the
// action does now, or why it can't run yet.
struct ActionList: View {
  @Environment(ChargeController.self) private var controller
  let open: (AppSection) -> Void

  var body: some View {
    let pluggedIn = controller.snapshot?.isPluggedIn ?? false
    VStack(spacing: 2) {
      ActionItem(
        title: controller.isTopUpActive ? String(localized: "Stop Top Up") : String(localized: "Top Up"),
        detail: controller.isTopUpActive || pluggedIn
          ? String(localized: "Charge to 100% until you unplug, then back to your limit")
          : String(localized: "Plug in the charger to top up"),
        symbol: "bolt.fill",
        isActive: controller.isTopUpActive,
        isEnabled: controller.isTopUpActive || pluggedIn
      ) {
        controller.isTopUpActive ? controller.stopTopUp() : controller.startTopUp()
      }
      ActionItem(
        title: controller.mode == .discharge ? String(localized: "Stop Discharge") : String(localized: "Discharge"),
        detail: controller.canDischarge || controller.mode == .discharge
          ? String(localized: "Use the battery down to your limit, on the charger")
          : String(localized: "Works on the charger when above the limit"),
        symbol: "arrow.down",
        isActive: controller.mode == .discharge,
        isEnabled: controller.mode == .discharge || controller.canDischarge
      ) {
        controller.mode == .discharge ? controller.stopDischarge() : controller.startDischarge()
      }
      ActionItem(
        title: controller.calibrationStep == nil ? String(localized: "Calibrate") : String(localized: "Calibrating"),
        detail: controller.calibrationStep?.title
          ?? controller.calibrationBlocker
          ?? String(localized: "Full cycle so the percentage stays accurate"),
        symbol: "arrow.triangle.2.circlepath",
        isActive: controller.calibrationStep != nil,
        isEnabled: true
      ) {
        if controller.calibrationStep == nil, controller.calibrationBlocker == nil {
          controller.startCalibration()
        } else {
          open(.calibration)
        }
      }
    }
    .padding(.vertical, 6)
  }
}

private struct ActionItem: View {
  let title: String
  let detail: String
  let symbol: String
  let isActive: Bool
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isActive ? Color.white : Color.primary)
          .frame(width: 26, height: 26)
          .background(Circle().fill(isActive ? Theme.moving : Color.primary.opacity(0.09)))
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        Spacer(minLength: 0)
      }
    }
    .buttonStyle(HoverRowStyle(verticalPadding: 4))
    .disabled(!isEnabled)
    .help(detail)
  }
}
