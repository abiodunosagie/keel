import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let toggleTopUp = Self("toggleTopUp")
  static let raiseLimit = Self("raiseLimit")
  static let lowerLimit = Self("lowerLimit")
  static let pauseHere = Self("pauseHere")
  static let togglePopover = Self("togglePopover")
  static let openDashboard = Self("openDashboard")
}

// Global keyboard shortcuts. None are set until the owner records them in Automation.
@MainActor
enum Hotkeys {
  static let limitStep = 5

  static func install(model: AppModel) {
    let controller = model.controller
    KeyboardShortcuts.onKeyUp(for: .toggleTopUp) {
      controller.isTopUpActive ? controller.stopTopUp() : controller.startTopUp()
    }
    KeyboardShortcuts.onKeyUp(for: .raiseLimit) {
      controller.setLimit(controller.effectiveSettings.limit + limitStep)
    }
    KeyboardShortcuts.onKeyUp(for: .lowerLimit) {
      controller.setLimit(controller.effectiveSettings.limit - limitStep)
    }
    KeyboardShortcuts.onKeyUp(for: .pauseHere) {
      if controller.canPauseHere { controller.pauseCharging() }
    }
    KeyboardShortcuts.onKeyUp(for: .togglePopover) { model.togglePopover() }
    KeyboardShortcuts.onKeyUp(for: .openDashboard) { model.open(.dashboard) }
  }
}
