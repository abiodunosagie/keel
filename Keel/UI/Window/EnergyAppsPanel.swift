import SwiftUI

// "Apps using significant energy", from the energy impact column of `top`. The dashboard
// samples it only while it is on screen.
struct EnergyAppsPanel: View {
  let apps: [EnergyApp]?

  var body: some View {
    RowGroup {
      SettingRow(title: "Apps using significant energy", detail: summary) {
        EmptyView()
      }
    }
  }

  private var summary: String {
    guard let apps else { return "Measuring…" }
    guard !apps.isEmpty else { return "No app is using much energy right now." }
    return apps.map { "\($0.name) \(String(format: "%.1f", $0.impact))" }.joined(separator: ", ")
      + ". Energy impact, as in Activity Monitor."
  }
}

struct EnergyApp: Equatable, Sendable {
  var name: String
  var impact: Double

  // The first `top` sample has no rate yet, so two are taken and the second is used.
  nonisolated static func sample(limit: Int = 5) -> [EnergyApp] {
    let arguments = ["-l", "2", "-o", "power", "-n", "\(limit)", "-stats", "power,command"]
    guard let result = Shell.run("/usr/bin/top", arguments) else { return [] }
    return parse(result.output, limit: limit)
  }

  static func parse(_ output: String, limit: Int) -> [EnergyApp] {
    let blocks = output.components(separatedBy: "POWER")
    guard let last = blocks.last else { return [] }
    return last.split(separator: "\n").dropFirst().compactMap { line -> EnergyApp? in
      let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
      guard fields.count == 2, let impact = Double(fields[0]), impact > 0 else { return nil }
      let name = fields[1].trimmingCharacters(in: .whitespaces)
      // `top` measuring itself is noise.
      return name == "top" ? nil : EnergyApp(name: name, impact: impact)
    }
    .prefix(limit)
    .map { $0 }
  }
}
