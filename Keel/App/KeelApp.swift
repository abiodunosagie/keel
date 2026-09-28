import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await AppModel.shared.start() }
  }

  // Opening Keel again (Finder, Spotlight, the Dock) shows the window, the only way in when the
  // menu bar icon is hidden.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    AppModel.shared.windows.showMain()
    return false
  }

  private var hasReplied = false

  // Quitting waits for the final limit write, so macOS is never left on a temporary limit, but
  // never more than a few seconds: a stuck helper call must not block Quit.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await AppModel.shared.prepareForQuit()
      reply(sender)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      MainActor.assumeIsolated { self?.reply(sender) }
    }
    return .terminateLater
  }

  private func reply(_ sender: NSApplication) {
    guard !hasReplied else { return }
    hasReplied = true
    sender.reply(toApplicationShouldTerminate: true)
  }
}

@main
struct KeelApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  // The menu bar item and windows are AppKit-managed (StatusItemController, WindowManager);
  // SwiftUI only needs a scene to exist.
  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
