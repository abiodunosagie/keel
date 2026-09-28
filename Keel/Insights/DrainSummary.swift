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
      lines.append(String(localized: "The Mac uses \(Format.watts(load)) right now, from the charger."))
    } else {
      let now = Format.watts(load)
      if let averageWatts, averageWatts > 0.5 {
        // Whole sentences, so each language can order them its own way.
        let average = Format.watts(averageWatts)
        if load > averageWatts * 1.3 {
          lines.append(String(localized: "The Mac uses \(now) right now, more than its recent average of \(average)."))
        } else if load < averageWatts * 0.7 {
          lines.append(String(localized: "The Mac uses \(now) right now, less than its recent average of \(average)."))
        } else {
          lines.append(String(localized: "The Mac uses \(now) right now, about its recent average of \(average)."))
        }
      } else {
        lines.append(String(localized: "The Mac uses \(now) right now."))
      }
    }
    if let chip, chip.total > 0.05 {
      let share = load > 0 ? Int((chip.total / load * 100).rounded()) : 0
      let watts = Format.watts(chip.total)
      let percent = min(share, 100)
      lines.append(chip.gpu > chip.cpu
        ? String(localized: "The chip takes \(watts) (\(percent)%), mostly the graphics.")
        : String(localized: "The chip takes \(watts) (\(percent)%), mostly the processor."))
    }
    if let display = snapshot.displayWatts, display > 0.05, load > 0 {
      let share = Int((display / load * 100).rounded())
      lines.append(String(localized: "The screen backlight takes \(Format.watts(display)) (\(min(share, 100))%). Lower brightness saves the most."))
    }
    let heavy = apps.filter { $0.impact >= 5 }.prefix(3)
    if !heavy.isEmpty {
      let names = heavy.map(\.name).formatted(.list(type: .and))
      lines.append(String(localized: "Busiest apps: \(names)."))
    }
    if let temperature = snapshot.temperature, temperature >= 40 {
      lines.append(String(localized: "The battery is warm (\(Format.temperature(temperature))), which drains and ages it faster."))
    }
    return lines
  }
}
