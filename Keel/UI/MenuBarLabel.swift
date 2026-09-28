import SwiftUI

struct MenuBarLabel: View {
  let controller: ChargeController

  var body: some View {
    let percent = controller.displayPercent.map { Int($0.rounded()) }
    HStack(spacing: 3) {
      Image(systemName: symbol)
      if let percent {
        Text(verbatim: "\(percent)%")
      }
    }
  }

  private var symbol: String {
    switch controller.state {
    case .charging, .topUp, .macOSOverride: return "battery.100percent.bolt"
    case .paused: return "powerplug"
    case .heatProtect: return "thermometer.high"
    case .discharging, .onBattery: return batteryLevelSymbol
    case .unavailable: return "battery.0percent"
    }
  }

  private var batteryLevelSymbol: String {
    let percent = controller.displayPercent ?? 0
    switch percent {
    case 88...: return "battery.100percent"
    case 63..<88: return "battery.75percent"
    case 38..<63: return "battery.50percent"
    case 13..<38: return "battery.25percent"
    default: return "battery.0percent"
    }
  }
}
