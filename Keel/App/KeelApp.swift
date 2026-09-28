import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await AppModel.shared.start() }
  }

  // Quitting waits for the final limit write, so macOS is never left on a temporary limit.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await AppModel.shared.prepareForQuit()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@main
struct KeelApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = AppModel.shared

  var body: some Scene {
    MenuBarExtra {
      PopoverView()
        .environment(model)
        .environment(model.controller)
        .environment(model.helper)
    } label: {
      MenuBarLabel(controller: model.controller)
    }
    .menuBarExtraStyle(.window)

    Window("Keel", id: MainWindow.id) {
      MainWindow()
        .environment(model)
        .environment(model.controller)
        .environment(model.helper)
        .environment(model.scheduler)
        .environment(model.history)
    }
    .windowResizability(.contentMinSize)
    .defaultPosition(.center)
  }
}
