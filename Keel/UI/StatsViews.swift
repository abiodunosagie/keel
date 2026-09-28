import SwiftUI

// Where the power goes, drawn as a ribbon: charger to Mac (and battery), or battery to Mac.
struct PowerFlowRow: View {
  let snapshot: BatterySnapshot

  var body: some View {
    let flow = PowerFlow(snapshot: snapshot)
    HStack(spacing: 10) {
      endpoint(flow.sourceTitle, flow.sourceWatts)
      Ribbon(split: flow.batteryShare)
        .fill(flow.fromBattery ? Theme.moving.opacity(0.15) : Theme.held.opacity(0.15))
        .overlay(Ribbon(split: flow.batteryShare).stroke(flow.fromBattery ? Theme.moving : Theme.held, lineWidth: 0.8))
        .frame(height: 34)
      endpoint(flow.destinationTitle, flow.destinationWatts)
    }
  }

  private func endpoint(_ title: String, _ watts: Double?) -> some View {
    HStack(spacing: 4) {
      Text(title).foregroundStyle(Theme.ink2)
      if let watts {
        Text(Format.watts(watts)).font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.ink)
      }
    }
    .font(.system(size: 12))
    .fixedSize()
  }
}

// The numbers behind the ribbon. Battery watts are positive while charging.
struct PowerFlow {
  // Battery currents below this are gauge noise, not real charging or discharging.
  static let noiseWatts = 0.3

  let snapshot: BatterySnapshot

  // The battery covers a load spike or is being run down while plugged in.
  var fromBattery: Bool { snapshot.batteryWatts < -Self.noiseWatts }

  var sourceTitle: String {
    if snapshot.isPluggedIn { return fromBattery ? "Charger + battery" : "Charger" }
    return "Battery"
  }

  var sourceWatts: Double? {
    guard let load = snapshot.systemLoad else { return nil }
    return load + max(0, snapshot.batteryWatts)
  }

  var destinationTitle: String {
    snapshot.batteryWatts > Self.noiseWatts ? "Mac + battery" : "Mac"
  }

  var destinationWatts: Double? { sourceWatts }

  // How much of the ribbon's far end goes into the battery, 0 when nothing does.
  var batteryShare: Double {
    guard let total = sourceWatts, total > 0, snapshot.batteryWatts > Self.noiseWatts else { return 0 }
    return min(1, snapshot.batteryWatts / total)
  }
}

// A band that narrows slightly toward the Mac, splitting off the battery's share at the end.
private struct Ribbon: Shape {
  var split: Double

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let inset = rect.height * 0.12
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + inset),
                  control1: CGPoint(x: rect.midX, y: rect.minY),
                  control2: CGPoint(x: rect.midX, y: rect.minY + inset))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
    path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                  control1: CGPoint(x: rect.midX, y: rect.maxY - inset),
                  control2: CGPoint(x: rect.midX, y: rect.maxY))
    path.closeSubpath()
    if split > 0 {
      let y = rect.minY + inset + (rect.height - 2 * inset) * (1 - split)
      path.move(to: CGPoint(x: rect.maxX - rect.width * 0.25, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    return path
  }
}

struct StatsRow: View {
  let snapshot: BatterySnapshot

  var body: some View {
    StatStrip(items: [
      ("Health", Format.percent(snapshot.health)),
      ("Cycles", "\(snapshot.cycleCount)"),
      ("Temp", snapshot.temperature.map { String(format: "%.1f°", $0) } ?? "n/a"),
      ("Adapter", snapshot.adapterWatts.map { "\($0) W" } ?? "none"),
    ], valueSize: 13, padding: 7)
    .padding(.top, 10)
    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
  }
}

// Labels over monospaced values, split by hairlines: the popover's stats and the dashboard tiles.
struct StatStrip: View {
  let items: [(String, String)]
  var valueSize: CGFloat = 13
  var padding: CGFloat = 7

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        if index > 0 { Rectangle().fill(Theme.line).frame(width: 1).frame(maxHeight: .infinity) }
        VStack(alignment: .leading, spacing: 3) {
          Text(item.0).font(.system(size: 11)).foregroundStyle(Theme.ink3)
          Text(item.1).font(Theme.mono(valueSize, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, padding)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}
