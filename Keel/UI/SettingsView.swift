import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Environment(ChargeController.self) private var controller
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    @Bindable var controller = controller
    Form {
      Section("Charging") {
        Stepper(value: $controller.settings.limit, in: controller.backend.limitRange) {
          LabeledContent("Charge limit", value: "\(controller.settings.limit)%")
        }
        Toggle(isOn: $controller.settings.automaticDischarge) {
          Text("Automatic Discharge")
          Text("When the battery is above the limit on the charger, run on battery until it gets there. Off: stay at the current level.")
        }
        Toggle(isOn: $controller.settings.useHardwarePercent) {
          Text("Hardware battery percentage")
          Text("Use the battery controller's own reading, usually a few points below what macOS shows.")
        }
      }
      Section("Heat Protection") {
        Toggle(isOn: $controller.settings.heatProtection) {
          Text("Pause charging when the battery is hot")
          Text("Checked again every 5 minutes. macOS can only pause charging above 80%.")
        }
        Stepper(value: $controller.settings.maxTemperature, in: 25...45, step: 1) {
          LabeledContent("Max temperature", value: String(format: "%.0f °C", controller.settings.maxTemperature))
        }
        .disabled(!controller.settings.heatProtection)
      }
      Section("General") {
        Toggle("Open Keel at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        if let loginError {
          Text(loginError).font(.caption).foregroundStyle(Theme.heat)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginError = nil
    } catch {
      loginError = "Couldn't change the login item: \(error.localizedDescription)"
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
