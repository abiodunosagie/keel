import SwiftUI

struct ChargePane: View {
  @Environment(ChargeController.self) private var controller

  var body: some View {
    @Bindable var controller = controller
    PaneHeader(
      title: "Charging",
      lede: "The limit is held by macOS itself, so it keeps working while the Mac sleeps, after a restart and when Keel is closed."
    )
    RowGroup {
      SettingRow(title: "Charge limit", detail: "\(controller.limitRange.lowerBound) to \(controller.limitRange.upperBound)%. Drag in the popover or step here.") {
        Stepper(value: $controller.settings.limit, in: controller.limitRange) {
          ValueChip(text: "\(controller.settings.limit)%")
        }
      }
      SettingRow(title: "Automatic Discharge", detail: "When the battery is above the limit on the charger, run on battery until it gets there. Off: stay at the current level.") {
        Toggle("Automatic Discharge", isOn: $controller.settings.automaticDischarge).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Hardware battery percentage", detail: "Use the battery controller's own reading, usually a few points below what macOS shows.") {
        Toggle("Hardware battery percentage", isOn: $controller.settings.useHardwarePercent).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Keep awake until the limit", detail: "Stay awake with the lid closed until charging or discharging reaches the limit.") {
        Toggle("Keep awake until the limit", isOn: $controller.options.keepAwakeUntilLimit).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Keep the limit when Keel is closed", detail: "Off: quitting Keel removes the limit and the battery charges to 100%.") {
        Toggle("Keep the limit when Keel is closed", isOn: $controller.options.keepLimitWhenClosed).labelsHidden().toggleStyle(.switch)
      }
    }
    RowGroup {
      SettingRow(title: "Heat Protection", detail: "Pause charging when the battery is hotter than the limit. Checked again every \(Int(HeatGuard.window / 60)) minutes. macOS can only pause charging above \(controller.limitRange.lowerBound)%.") {
        Toggle("Heat Protection", isOn: $controller.settings.heatProtection).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Max temperature", detail: "Apple advises keeping the Mac below 35 °C.") {
        Stepper(value: $controller.settings.maxTemperature, in: 25...45, step: 1) {
          ValueChip(text: String(format: "%.0f °C", controller.settings.maxTemperature))
        }
        .disabled(!controller.settings.heatProtection)
      }
    }
    Text("Also built in: charging stays paused while the Mac sleeps, and each user account on this Mac gets the same limit, because macOS holds it for the whole Mac. macOS sometimes charges to 100% on its own to recalibrate its battery gauge, then returns to the limit.")
      .font(.system(size: 11.5))
      .foregroundStyle(Theme.ink3)
      .fixedSize(horizontal: false, vertical: true)
  }
}
