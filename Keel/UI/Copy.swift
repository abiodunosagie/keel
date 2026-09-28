import Foundation

// Text shown for model values, kept out of the model files.
extension ChargeState {
  var title: String {
    switch self {
    case .charging: return "Charging"
    case .paused: return "Held at limit"
    case .discharging: return "Discharging"
    case .topUp: return "Top Up to 100%"
    case .heatProtect: return "Paused, too warm"
    case .calibration: return "Calibrating"
    case .onBattery: return "On battery"
    case .macOSOverride: return "macOS is charging"
    case .unavailable: return "Not available"
    }
  }
}

extension PowerMode {
  var title: String {
    switch self {
    case .automatic: return "Automatic"
    case .low: return "Low Power"
    case .high: return "High Power"
    }
  }
}

enum Format {
  static func duration(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
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
