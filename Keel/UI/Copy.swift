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
    "\(number(abs(value), digits: 1)) W"
  }

  // Decimals in the reader's own style: 12,5 in German, French, Spanish and Portuguese.
  // (CSV export keeps a dot on purpose, for spreadsheets.)
  static func number(_ value: Double, digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
  }

  static func percent(_ value: Double) -> String {
    "\(number(value, digits: 1))%"
  }

  static func temperature(_ value: Double) -> String {
    "\(number(value, digits: 1)) °C"
  }
}
