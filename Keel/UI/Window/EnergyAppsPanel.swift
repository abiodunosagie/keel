import SwiftUI

// "Apps using significant energy", from the energy impact column of `top`. Sampled only while
// the dashboard is on screen.
struct EnergyAppsPanel: View {
  @State private var apps: [EnergyApp] = []

  var body: some View {
    RowGroup {
      SettingRow(title: "Apps using significant energy", detail: summary) {
        EmptyView()
      }
    }
    .task {
      while !Task.isCancelled {
        apps = await Task.detached(priority: .utility) { EnergyApp.sample() }.value
        try? await Task.sleep(for: .seconds(15))
      }
    }
  }

  private var summary: String {
    guard !apps.isEmpty else { return "Measuring…" }
    return apps.map { "\($0.name) \(String(format: "%.1f", $0.impact))" }.joined(separator: ", ")
      + ". Energy impact, as in Activity Monitor."
  }
}

struct EnergyApp: Equatable, Sendable {
  var name: String
  var impact: Double

  // The first `top` sample has no rate yet, so two are taken and the second is used.
  nonisolated static func sample(limit: Int = 5) -> [EnergyApp] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
    process.arguments = ["-l", "2", "-o", "power", "-n", "\(limit)", "-stats", "power,command"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return parse(String(decoding: data, as: UTF8.self), limit: limit)
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
