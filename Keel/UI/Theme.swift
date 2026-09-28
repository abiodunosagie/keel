import SwiftUI

// Colours follow the MagSafe light: green when the battery is held at its limit, amber while
// it is charging or discharging toward it.
enum Theme {
  static let held = Color(nsColor: .systemGreen)
  static let moving = Color(nsColor: .systemOrange)
  static let heat = Color(nsColor: .systemRed)
  static let accent = Color(nsColor: .controlAccentColor)

  static func color(for state: ChargeState) -> Color {
    switch state {
    case .paused: return held
    case .charging, .discharging, .topUp, .macOSOverride: return moving
    case .heatProtect: return heat
    case .onBattery, .unavailable: return .secondary
    }
  }
}

extension ChargeState {
  var title: String {
    switch self {
    case .charging: return "Charging"
    case .paused: return "Held at limit"
    case .discharging: return "Running on battery"
    case .topUp: return "Top Up to 100%"
    case .heatProtect: return "Paused, too warm"
    case .onBattery: return "On battery"
    case .macOSOverride: return "macOS is charging"
    case .unavailable: return "Not available"
    }
  }
}
