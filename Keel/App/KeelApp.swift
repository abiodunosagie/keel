import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await AppModel.shared.start() }
  }

  func applicationWillTerminate(_ notification: Notification) {
    AppModel.shared.prepareForQuit()
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
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }
}
