import ServiceManagement
import SwiftUI

struct GeneralPane: View {
  @Environment(AppModel.self) private var model
  @Environment(HelperClient.self) private var helper
  @State private var loginError: String?
  @State private var powerMode: PowerMode?
  @State private var confirmRemove = false
  @State private var removeError: String?
  @State private var launchAtLogin = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      PaneHeader(title: "General", lede: "Keel Helper, power mode, login and removal.")
      RowGroup {
        HelperSection()
        SettingRow(title: "Power mode", detail: "The macOS energy mode. High Power only exists on some MacBook Pro models.") {
          Picker("Power mode", selection: Binding(get: { powerMode ?? .automatic }, set: setPowerMode)) {
            ForEach(PowerMode.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
          .disabled(!helper.isReady)
        }
      }
      RowGroup {
        SettingRow(title: "Open Keel at login", detail: loginError) {
          Toggle("Open Keel at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        SettingRow(title: "Remove Keel", detail: removeError ?? "Puts back the charge limit macOS had before Keel, removes the helper and the login item, and moves Keel to the Trash.") {
          Button("Remove…", role: .destructive) { confirmRemove = true }
        }
        SettingRow(title: "Quit Keel", detail: "The charge limit stays on unless you turned that off under Charge.") {
          Button("Quit") { NSApp.terminate(nil) }
        }
      }
    }
    .confirmationDialog("Remove Keel from this Mac?", isPresented: $confirmRemove) {
      Button("Remove Keel", role: .destructive) { Task { await remove() } }
    } message: {
      Text("The battery goes back to how macOS charged it before Keel.")
    }
    .task {
      powerMode = await PowerModeReader.current()
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }

  private func setPowerMode(_ mode: PowerMode) {
    powerMode = mode
    Task {
      if !(await helper.setPowerMode(mode)) { powerMode = await PowerModeReader.current() }
    }
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginError = nil
      launchAtLogin = enabled
    } catch {
      loginError = "macOS didn't allow changing the login item. Try again from System Settings > General > Login Items."
    }
  }

  private func remove() async {
    await model.controller.restoreOriginalLimit()
    do {
      try await helper.uninstall()
    } catch {
      removeError = "macOS didn't remove Keel Helper, so Keel stays installed. Try again, or switch it off in System Settings > General > Login Items."
      return
    }
    try? await SMAppService.mainApp.unregister()
    NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}

// Reads the current macOS energy mode (no root needed).
enum PowerModeReader {
  static func current() async -> PowerMode? {
    await Task.detached(priority: .utility) {
      Shell.run("/usr/bin/pmset", ["-g"]).flatMap { parse($0.output) }
    }.value
  }

  // pmset -g prints a line like " powermode            0".
  nonisolated static func parse(_ output: String) -> PowerMode? {
    for line in output.split(separator: "\n") {
      let fields = line.split(whereSeparator: \.isWhitespace)
      if fields.count >= 2, fields[0] == "powermode", let raw = Int(fields[1]) {
        return PowerMode(rawValue: raw)
      }
    }
    return nil
  }
}
