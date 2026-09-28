import Foundation

// Text shown for model values, kept out of the model files.
extension ChargeState {
  var title: String {
    switch self {
    case .charging: return String(localized: "Charging")
    case .paused: return String(localized: "Held at limit")
    case .discharging: return String(localized: "Discharging")
    case .topUp: return String(localized: "Top Up to 100%")
    case .heatProtect: return String(localized: "Paused, too warm")
    case .calibration: return String(localized: "Calibrating")
    case .onBattery: return String(localized: "On battery")
    case .macOSOverride: return String(localized: "macOS is charging")
    case .unavailable: return String(localized: "Not available")
    }
  }
}

extension PowerMode {
  var title: String {
    switch self {
    case .automatic: return String(localized: "Automatic")
    case .low: return String(localized: "Low Power")
    case .high: return String(localized: "High Power")
    }
  }
}

enum Format {
  static func duration(_ minutes: Int) -> String {
    minutes >= 60 ? String(localized: "\(minutes / 60) h \(minutes % 60) min") : String(localized: "\(minutes) min")
  }

  static func watts(_ value: Double) -> String {
    String(format: "%.1f W", abs(value))
  }

  static func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
  }

  static func temperature(_ value: Double) -> String {
    String(format: "%.1f°C", value)
  }
}
