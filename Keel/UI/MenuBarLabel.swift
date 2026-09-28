import SwiftUI

// The menu bar item: a live status icon plus whichever readings the owner picked.
struct MenuBarLabel: View {
  let controller: ChargeController

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: symbol)
      if !parts.isEmpty {
        Text(verbatim: parts.joined(separator: " "))
      }
    }
  }

  private var parts: [String] {
    var parts: [String] = []
    let options = controller.options
    if options.menuBarPercent, let percent = controller.displayPercent {
      parts.append("\(Int(percent.rounded()))%")
    }
    if options.menuBarWatts, let snapshot = controller.snapshot, let watts = PowerFlow(snapshot: snapshot).sourceWatts {
      parts.append(String(format: "%.0fW", watts))
    }
    if options.menuBarTemperature, let temperature = controller.snapshot?.temperature {
      parts.append(String(format: "%.0f°", temperature))
    }
    return parts
  }

  // AlDente's live status icons: plugged in and charging, plugged in and paused, plugged in and
  // discharging, unplugged.
  private var symbol: String {
    switch controller.state {
    case .charging, .topUp, .macOSOverride, .calibration: return "battery.100percent.bolt"
    case .paused: return "powerplug"
    case .heatProtect: return "thermometer.high"
    case .discharging: return "arrow.down.to.line.compact"
    case .onBattery: return batteryLevelSymbol
    case .unavailable: return "exclamationmark.triangle"
    }
  }

  private var batteryLevelSymbol: String {
    switch controller.displayPercent ?? 0 {
    case 88...: return "battery.100percent"
    case 63..<88: return "battery.75percent"
    case 38..<63: return "battery.50percent"
    case 13..<38: return "battery.25percent"
    default: return "battery.0percent"
    }
  }
}
