import AppKit
import SwiftUI

extension View {
  // Everything Keel's views read from the environment.
  @MainActor
  func keelEnvironment(_ model: AppModel) -> some View {
    environment(model)
      .environment(model.controller)
      .environment(model.helper)
      .environment(model.scheduler)
      .environment(model.history)
      .environment(model.insights)
  }
}

// Opens Keel's windows. AppKit-managed, so the menu bar item, Shortcuts and the Dock icon can all
// open them the same way.
@MainActor
final class WindowManager {
  private var windows: [String: NSWindow] = [:]
  private weak var model: AppModel?

  init(model: AppModel) {
    self.model = model
  }

  func showMain(section: AppSection? = nil) {
    guard let model else { return }
    if let section { model.section = section }
    show("main", title: "Keel", size: NSSize(width: 800, height: 620), resizable: true) {
      MainWindow().keelEnvironment(model)
    }
  }

  func showOnboarding() {
    guard let model else { return }
    show("onboarding", title: "Welcome to Keel", size: NSSize(width: 560, height: 520), resizable: false) {
      OnboardingView { [weak self] in self?.close("onboarding") }.keelEnvironment(model)
    }
  }

  func showWhatsNew() {
    guard let model else { return }
    show("whatsNew", title: "What's New in Keel", size: NSSize(width: 480, height: 460), resizable: false) {
      WhatsNewView { [weak self] in self?.close("whatsNew") }.keelEnvironment(model)
    }
  }

  func close(_ id: String) {
    windows[id]?.close()
  }

  private func show<Content: View>(
    _ id: String, title: String, size: NSSize, resizable: Bool, content: () -> Content
  ) {
    if let window = windows[id] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    if resizable { style.insert(.resizable) }
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                          backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(rootView: content())
    window.setContentSize(size)
    window.center()
    window.makeKeyAndOrderFront(nil)
    windows[id] = window
    NSApp.activate()
  }
}
