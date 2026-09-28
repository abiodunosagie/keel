import Foundation

// Where the Mac's power goes right now, in the helper's own units.
struct ChipPower: Equatable, Sendable {
  var cpu: Double
  var gpu: Double
  var neuralEngine: Double

  var total: Double { cpu + gpu + neuralEngine }
}

// "Why is my battery draining?": a few plain sentences from the live readings.
enum DrainSummary {
  static func sentences(
    snapshot: BatterySnapshot,
    averageWatts: Double?,
    chip: ChipPower?,
    apps: [EnergyApp]
  ) -> [String] {
    var lines: [String] = []
    let load = snapshot.systemLoad ?? abs(min(0, snapshot.batteryWatts))
    if snapshot.isPluggedIn {
      lines.append("The Mac uses \(Format.watts(load)) right now, from the charger.")
    } else {
      var line = "The Mac uses \(Format.watts(load)) right now"
      if let averageWatts, averageWatts > 0.5 {
        let comparison = load > averageWatts * 1.3 ? "more than" : load < averageWatts * 0.7 ? "less than" : "about"
        line += ", \(comparison) its recent average of \(Format.watts(averageWatts))"
      }
      lines.append(line + ".")
    }
    if let chip, chip.total > 0.05 {
      let share = load > 0 ? Int((chip.total / load * 100).rounded()) : 0
      let busiest = chip.gpu > chip.cpu ? "graphics" : "processor"
      lines.append("The chip takes \(Format.watts(chip.total)) (\(min(share, 100))%), mostly the \(busiest).")
    }
    if let display = snapshot.displayWatts, display > 0.05, load > 0 {
      let share = Int((display / load * 100).rounded())
      lines.append("The screen backlight takes \(Format.watts(display)) (\(min(share, 100))%). Lower brightness saves the most.")
    }
    let heavy = apps.filter { $0.impact >= 5 }.prefix(3)
    if !heavy.isEmpty {
      lines.append("Busiest apps: \(heavy.map(\.name).joined(separator: ", ")).")
    }
    if let temperature = snapshot.temperature, temperature >= 40 {
      lines.append("The battery is warm (\(Format.temperature(temperature))), which drains and ages it faster.")
    }
    return lines
  }
}
