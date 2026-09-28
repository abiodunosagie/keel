import SwiftUI

// Installs the helper that Calibration, the MagSafe light and power modes need.
struct HelperSection: View {
  @Environment(HelperClient.self) private var helper
  @State private var running: Bool?

  var body: some View {
    SettingRow(title: "Keel Helper", detail: detail) {
      switch helper.status {
      case .ready:
        if running == false {
          Label("Not responding", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.heat)
        } else {
          Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.held)
        }
      case .needsApproval:
        Button("Open Login Items") { helper.install() }
      case .notInstalled, .failed:
        Button("Install Helper") { helper.install() }
      }
    }
    .task(id: helper.status) {
      helper.refreshStatus()
      running = helper.isReady ? await helper.version() != nil : nil
    }
  }

  private var detail: String {
    switch helper.status {
    case .ready:
      return "Calibration, the MagSafe light and power modes are available."
    case .needsApproval:
      return "In System Settings > General > Login Items, switch on Keel under \"Allow in the Background\"."
    case .notInstalled:
      return "Needed for Calibration, the MagSafe light and power modes. It only switches the charger, the light, sleep and the power mode, and undoes the first three when Keel quits."
    case .failed:
      return "macOS didn't install the helper. Try again, or check System Settings > General > Login Items."
    }
  }
}
