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
      Item(symbol: "powerplug", title: String(localized: "Charger insights"),
           detail: String(localized: "See each charger's rating and what it delivers, with a warning when it can't keep up.")),
      Item(symbol: "heart.text.square", title: String(localized: "Health and history"),
           detail: String(localized: "Daily health with a forecast, every charging session, and CSV export.")),
      Item(symbol: "cpu", title: String(localized: "Where the power goes"),
           detail: String(localized: "CPU, GPU and screen power in the dashboard, and a plain summary of what drains the battery.")),
      Item(symbol: "menubar.rectangle", title: String(localized: "Your menu bar, your way"),
           detail: String(localized: "iPhone-style battery or a tiny graph, a right-click menu, and a popover you can rearrange.")),
      Item(symbol: "calendar.badge.clock", title: String(localized: "Smarter automation"),
           detail: String(localized: "Top Up before calendar events, limits per Wi-Fi network, and keyboard shortcuts.")),
    ],
  ]
}
