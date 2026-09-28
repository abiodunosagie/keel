import SwiftUI

enum Format {
  static func duration(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
  }

  static func watts(_ value: Double) -> String {
    String(format: "%.1f W", abs(value))
  }
}

// Where the power is going: charger to Mac and battery, or battery to Mac.
struct PowerFlowRow: View {
  let snapshot: BatterySnapshot

  var body: some View {
    HStack(spacing: 8) {
      Label(source, systemImage: snapshot.isPluggedIn ? "bolt.fill" : "battery.75percent")
      Image(systemName: "arrow.right").foregroundStyle(.tertiary)
      Text(destination)
      Spacer()
    }
    .font(.caption)
    .monospacedDigit()
    .foregroundStyle(.secondary)
  }

  private var batteryWatts: Double { snapshot.batteryWatts }

  private var source: String {
    if snapshot.isPluggedIn, batteryWatts < -0.3 {
      return "Charger + battery \(Format.watts(batteryWatts))"
    }
    if snapshot.isPluggedIn { return "Charger" }
    return "Battery \(Format.watts(batteryWatts))"
  }

  private var destination: String {
    let load = snapshot.systemLoad.map { "Mac \(Format.watts($0))" } ?? "Mac"
    if snapshot.isPluggedIn, batteryWatts > 0.3 {
      return "\(load), battery \(Format.watts(batteryWatts))"
    }
    return load
  }
}

struct StatsRow: View {
  let snapshot: BatterySnapshot

  var body: some View {
    HStack(spacing: 0) {
      stat("Health", String(format: "%.1f%%", snapshot.health))
      Divider()
      stat("Cycles", "\(snapshot.cycleCount)")
      Divider()
      stat("Temp", snapshot.temperature.map { String(format: "%.1f°C", $0) } ?? "n/a")
      Divider()
      stat("Adapter", snapshot.adapterWatts.map { "\($0) W" } ?? "none")
    }
    .frame(height: 34)
    .padding(.top, 8)
    .overlay(alignment: .top) { Divider() }
  }

  private func stat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.weight(.semibold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 6)
  }
}
