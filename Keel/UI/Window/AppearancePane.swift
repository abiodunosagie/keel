import SwiftUI

struct AppearancePane: View {
  @Environment(AppModel.self) private var model
  @Environment(ChargeController.self) private var controller
  @Environment(HelperClient.self) private var helper

  var body: some View {
    @Bindable var controller = controller
    PaneHeader(title: String(localized: "Appearance"), lede: String(localized: "What the menu bar shows and how the MagSafe light behaves."))
    RowGroup {
      SettingRow(title: String(localized: "Menu bar icon"), detail: String(localized: "State symbols, an iPhone-style battery with the level inside, or a tiny graph of the last half hour.")) {
        Picker("Menu bar icon", selection: $controller.options.iconStyle) {
          Text("Symbols").tag(AppOptions.IconStyle.symbol)
          Text("Battery").tag(AppOptions.IconStyle.battery)
          Text("Graph").tag(AppOptions.IconStyle.graph)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingRow(title: String(localized: "Right-click"), detail: String(localized: "What happens when you right-click Keel in the menu bar.")) {
        Picker("Right-click", selection: $controller.options.rightClick) {
          Text("Quick menu").tag(AppOptions.RightClick.menu)
          Text("Open Dashboard").tag(AppOptions.RightClick.dashboard)
          Text("Top Up").tag(AppOptions.RightClick.topUp)
          Text("Same as click").tag(AppOptions.RightClick.popover)
        }
        .labelsHidden()
        .fixedSize()
      }
      SettingRow(title: String(localized: "Hide the menu bar icon"), detail: String(localized: "Keel keeps running. Open it again from Applications or the Dock.")) {
        Toggle("Hide the menu bar icon", isOn: $controller.options.hideMenuBarIcon).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: String(localized: "Show in the Dock"), detail: String(localized: "Always on while the menu bar icon is hidden.")) {
        Toggle("Show in the Dock", isOn: $controller.options.showDockIcon).labelsHidden().toggleStyle(.switch)
          .disabled(controller.options.hideMenuBarIcon)
      }
    }
    RowGroup {
      SettingRow(title: String(localized: "Appearance"), detail: String(localized: "Follow macOS, or always light or dark.")) {
        Picker("Appearance", selection: $controller.options.appearance) {
          Text("System").tag(AppOptions.Appearance.system)
          Text("Light").tag(AppOptions.Appearance.light)
          Text("Dark").tag(AppOptions.Appearance.dark)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingRow(title: String(localized: "Reduce transparency"), detail: String(localized: "A solid popover. Off: the popover shows the glass behind it.")) {
        Toggle("Reduce transparency", isOn: $controller.options.reduceTransparency).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: String(localized: "Popover cards"), detail: String(localized: "Rearrange or hide cards. You can also hold any card in the popover.")) {
        Button("Customize") { model.isEditingPopover = true; model.showPopover() }
      }
    }
    RowGroup {
      SettingRow(title: String(localized: "Percentage"), detail: String(localized: "The battery level next to the icon.")) {
        Toggle("Percentage", isOn: $controller.options.menuBarPercent).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: String(localized: "Power draw"), detail: String(localized: "Watts the whole Mac is using.")) {
        Toggle("Power draw", isOn: $controller.options.menuBarWatts).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: String(localized: "Temperature"), detail: String(localized: "The battery temperature.")) {
        Toggle("Temperature", isOn: $controller.options.menuBarTemperature).labelsHidden().toggleStyle(.switch)
      }
    }
    RowGroup {
      SettingRow(title: String(localized: "MagSafe light"), detail: lightDetail) {
        Picker("MagSafe light", selection: $controller.options.magSafeLight) {
          Text("Keel").tag(AppOptions.Light.auto)
          Text("macOS").tag(AppOptions.Light.system)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .disabled(!helper.isReady)
      }
      SettingRow(title: String(localized: "Notifications"), detail: String(localized: "Limit reached, charging paused for heat, calibration finished or stopped, charger problems.")) {
        Toggle("Notifications", isOn: $controller.options.notifications).labelsHidden().toggleStyle(.switch)
      }
      SettingRow(title: String(localized: "Hot battery alert"), detail: String(localized: "Warn once each time the battery gets this hot.")) {
        HStack(spacing: 10) {
          Stepper(value: $controller.options.temperatureAlertLimit, in: HeatGuard.temperatureRange, step: 1) {
            ValueChip(text: "\(Format.number(controller.options.temperatureAlertLimit, digits: 0)) °C")
          }
          .disabled(!controller.options.temperatureAlert)
          Toggle("Hot battery alert", isOn: $controller.options.temperatureAlert).labelsHidden().toggleStyle(.switch)
        }
      }
      SettingRow(title: String(localized: "Above-limit alert"), detail: String(localized: "When Keel starts and the battery is well above your limit, for example after charging while switched off.")) {
        Toggle("Above-limit alert", isOn: $controller.options.overLimitAlert).labelsHidden().toggleStyle(.switch)
      }
    }
  }

  private var lightDetail: String {
    guard helper.isReady else { return String(localized: "Needs Keel Helper (General).") }
    return String(localized: "Keel: green at the limit, amber while charging or discharging. Only on Macs with a MagSafe port.")
  }
}
