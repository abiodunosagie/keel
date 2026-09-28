import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller = ChargeController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller.start()
  }
}

@main
struct KeelApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      PopoverView()
        .environment(appDelegate.controller)
    } label: {
      MenuBarLabel(controller: appDelegate.controller)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(appDelegate.controller)
    }
  }
}
