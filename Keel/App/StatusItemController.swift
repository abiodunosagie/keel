import AppKit
import Observation
import SwiftUI

// Keel's menu bar item: a live icon (state symbol, iPhone-style battery or mini graph), a
// popover on left click and the chosen action on right click.
@MainActor
final class StatusItemController: NSObject {
  private let model: AppModel
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()

  init(model: AppModel) {
    self.model = model
    super.init()
    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = NSHostingController(rootView: PopoverView().keelEnvironment(model))
    if let button = item.button {
      button.target = self
      button.action = #selector(clicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.setAccessibilityLabel("Keel")
    }
    observe()
  }

  func showPopover() {
    guard let button = item.button, !popover.isShown else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  func closePopover() {
    popover.performClose(nil)
  }

  // Redraws whenever anything the item shows changes.
  private func observe() {
    withObservationTracking {
      render()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
  }

  private func render() {
    let controller = model.controller
    let options = controller.options
    item.isVisible = !options.hideMenuBarIcon
    guard let button = item.button else { return }
    let rendering = MenuBarRendering(
      state: controller.state,
      percent: controller.displayPercent,
      snapshot: controller.snapshot,
      options: options,
      recent: options.iconStyle == .graph ? model.history.samples(since: .now.addingTimeInterval(-30 * 60)) : []
    )
    button.image = rendering.image()
    button.imagePosition = .imageLeading
    button.title = rendering.text
    button.toolTip = "Keel: \(controller.state.title)"
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    let isRight = NSApp.currentEvent?.type == .rightMouseUp
      || NSApp.currentEvent?.modifierFlags.contains(.control) == true
    guard isRight else {
      popover.isShown ? closePopover() : showPopover()
      return
    }
    switch model.controller.options.rightClick {
    case .popover: popover.isShown ? closePopover() : showPopover()
    case .dashboard: model.windows.showMain(section: .dashboard)
    case .topUp: model.controller.isTopUpActive ? model.controller.stopTopUp() : model.controller.startTopUp()
    case .menu: showMenu()
    }
  }

  private func showMenu() {
    let controller = model.controller
    let menu = NSMenu()
    menu.addItem(menuItem(controller.isTopUpActive ? "Stop Top Up" : "Top Up", enabled: controller.isTopUpActive
      || controller.snapshot?.isPluggedIn == true) {
      controller.isTopUpActive ? controller.stopTopUp() : controller.startTopUp()
    })
    menu.addItem(menuItem(controller.mode == .discharge ? "Stop Discharge" : "Discharge",
                          enabled: controller.canDischarge || controller.mode == .discharge) {
      controller.mode == .discharge ? controller.stopDischarge() : controller.startDischarge()
    })
    menu.addItem(menuItem("Pause Here", enabled: controller.canPauseHere) { controller.pauseCharging() })
    menu.addItem(.separator())
    for limit in [80, 85, 90, 95, 100] {
      let item = menuItem("Limit \(limit)%", enabled: true) { controller.setLimit(limit) }
      item.state = controller.settings.limit == limit ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(menuItem("Open Dashboard", enabled: true) { [model] in model.windows.showMain(section: .dashboard) })
    menu.addItem(menuItem("Settings…", enabled: true) { [model] in model.windows.showMain(section: .charge) })
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Keel", enabled: true) { NSApp.terminate(nil) })
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  private func menuItem(_ title: String, enabled: Bool, action: @escaping () -> Void) -> NSMenuItem {
    let item = ClosureMenuItem(title: title, action: action)
    item.isEnabled = enabled
    return item
  }
}

private final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: #selector(run), keyEquivalent: "")
    target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  @objc private func run() {
    handler()
  }
}
