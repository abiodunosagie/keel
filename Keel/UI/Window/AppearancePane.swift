import SwiftUI

struct AppearancePane: View {
  @Environment(ChargeController.self) private var controller
  @Environment(HelperClient.self) private var helper

  var body: some View {
    @Bindable var controller = controller
    PaneHeader(title: "Appearance", lede: "What the menu bar shows and how the MagSafe light behaves.")
    RowGroup {
      SettingRow(title: "Percentage", detail: "The battery level next to the icon.") {
        Toggle("Percentage", isOn: $controller.options.menuBarPercent).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Power draw", detail: "Watts the whole Mac is using.") {
        Toggle("Power draw", isOn: $controller.options.menuBarWatts).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Temperature", detail: "The battery temperature.") {
        Toggle("Temperature", isOn: $controller.options.menuBarTemperature).labelsHidden().toggleStyle(.switch)
      }
    }
    RowGroup {
      SettingRow(title: "MagSafe light", detail: lightDetail) {
        Picker("MagSafe light", selection: $controller.options.magSafeLight) {
          Text("Keel").tag(AppOptions.Light.auto)
          Text("macOS").tag(AppOptions.Light.system)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .disabled(!helper.isReady)
      }
      SettingRow(title: "Notifications", detail: "Limit reached, charging paused for heat, calibration finished or stopped, charger problems.") {
        Toggle("Notifications", isOn: $controller.options.notifications).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: "Hot battery alert", detail: "Warn once each time the battery gets this hot.") {
        HStack(spacing: 10) {
          Stepper(value: $controller.options.temperatureAlertLimit, in: HeatGuard.temperatureRange, step: 1) {
            ValueChip(text: String(format: "%.0f °C", controller.options.temperatureAlertLimit))
          }
          .disabled(!controller.options.temperatureAlert)
          Toggle("Hot battery alert", isOn: $controller.options.temperatureAlert).labelsHidden().toggleStyle(.switch)
        }
      }
      SettingRow(title: "Above-limit alert", detail: "When Keel starts and the battery is well above your limit, for example after charging while switched off.") {
        Toggle("Above-limit alert", isOn: $controller.options.overLimitAlert).labelsHidden().toggleStyle(.switch)
      }
    }
  }

  private var lightDetail: String {
    guard helper.isReady else { return "Needs Keel Helper (General)." }
    return "Keel: green at the limit, amber while charging or discharging. Only on Macs with a MagSafe port."
  }
}
