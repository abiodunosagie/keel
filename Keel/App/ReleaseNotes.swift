import Foundation

// What's New, per version. Only versions listed here show the window after an update.
enum ReleaseNotes {
  struct Item: Identifiable {
    var symbol: String
    var title: String
    var detail: String
    var id: String { title }
  }

  static func notes(for version: String) -> [Item]? {
    all[version]
  }

  private static let all: [String: [Item]] = [
    "0.2.0": [
      Item(symbol: "powerplug", title: "Charger insights",
           detail: "See each charger's rating and what it delivers, with a warning when it can't keep up."),
      Item(symbol: "heart.text.square", title: "Health and history",
           detail: "Daily health with a forecast, every charging session, and CSV export."),
      Item(symbol: "cpu", title: "Where the power goes",
           detail: "CPU, GPU and screen power in the dashboard, and a plain summary of what drains the battery."),
      Item(symbol: "menubar.rectangle", title: "Your menu bar, your way",
           detail: "iPhone-style battery or a tiny graph, a right-click menu, and a popover you can rearrange."),
      Item(symbol: "calendar.badge.clock", title: "Smarter automation",
           detail: "Top Up before calendar events, limits per Wi-Fi network, and keyboard shortcuts."),
    ],
  ]
}
