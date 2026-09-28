import SwiftUI

// A warning strip for a charger problem.
struct ProblemBanner: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(.system(size: 12.5, weight: .medium))
      .foregroundStyle(Theme.heat)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.heat.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
  }
}

// Where the Mac's power goes: chip (CPU, GPU, Neural Engine) and screen, the rest as "other".
struct PowerBreakdown: View {
  let snapshot: BatterySnapshot
  let chip: ChipPower?
  let helperReady: Bool

  var body: some View {
    let load = snapshot.systemLoad ?? 0
    VStack(alignment: .leading, spacing: 8) {
      if load > 0 {
        GeometryReader { geometry in
          HStack(spacing: 2) {
            ForEach(parts(load: load), id: \.name) { part in
              RoundedRectangle(cornerRadius: 3)
                .fill(part.color)
                .frame(width: max(2, geometry.size.width * part.watts / load))
            }
          }
        }
        .frame(height: 8)
      }
      HStack(spacing: 14) {
        ForEach(parts(load: load), id: \.name) { part in
          HStack(spacing: 5) {
            Circle().fill(part.color).frame(width: 7, height: 7)
            Text(part.name).foregroundStyle(Theme.ink2)
            Text(Format.watts(part.watts)).font(Theme.mono(11.5, weight: .semibold)).foregroundStyle(Theme.ink)
          }
        }
        Spacer()
      }
      .font(.system(size: 11.5))
      if chip == nil {
        Text(helperReady ? "Measuring chip power…" : "Chip power needs Keel Helper (General).")
          .font(.system(size: 11))
          .foregroundStyle(Theme.ink3)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private struct Part {
    var name: String
    var watts: Double
    var color: Color
  }

  private func parts(load: Double) -> [Part] {
    var parts: [Part] = []
    if let chip {
      parts.append(Part(name: "CPU", watts: chip.cpu, color: Theme.accent))
      parts.append(Part(name: "GPU", watts: chip.gpu, color: Theme.moving))
      if chip.neuralEngine > 0.01 {
        parts.append(Part(name: String(localized: "Neural Engine"), watts: chip.neuralEngine, color: Theme.heat))
      }
    }
    if let display = snapshot.displayWatts {
      parts.append(Part(name: String(localized: "Screen"), watts: display, color: Theme.held))
    }
    let known = parts.map(\.watts).reduce(0, +)
    parts.append(Part(name: String(localized: "Other"), watts: max(0, load - known), color: Theme.ink3.opacity(0.5)))
    return parts
  }
}

// The connected charger: rating, negotiated voltage and current, what actually comes in.
struct ChargerPanel: View {
  let snapshot: BatterySnapshot

  var body: some View {
    RowGroup {
      if let charger = snapshot.charger {
        SettingRow(title: charger.name, detail: detail(charger)) {
          ValueChip(text: "\(charger.watts) W")
        }
      } else {
        SettingRow(title: String(localized: "No charger"), detail: String(localized: "Plug in to see the charger's rating and what it delivers.")) {
          EmptyView()
        }
      }
    }
  }

  private func detail(_ charger: ChargerInfo) -> String {
    var parts: [String] = []
    if let manufacturer = charger.manufacturer { parts.append(manufacturer) }
    if let volts = charger.volts, let amps = charger.amps {
      parts.append(String(localized: "negotiated \(Format.number(volts, digits: 0)) V at \(Format.number(amps, digits: 2)) A"))
    }
    if let powerIn = snapshot.powerIn { parts.append(String(localized: "\(Format.watts(powerIn)) coming in now")) }
    return parts.joined(separator: ", ") + "."
  }
}

// "Why is my battery draining?"
struct DrainPanel: View {
  let lines: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Why the battery drains").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      ForEach(lines, id: \.self) { line in
        Text(line)
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .panel(radius: 10)
  }
}
