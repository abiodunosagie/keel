import Charts
import SwiftUI

struct DashboardPane: View {
  @Environment(ChargeController.self) private var controller
  @Environment(BatteryHistory.self) private var history
  @State private var range: ChartRange = .day
  @State private var averageMinutes = 15

  var body: some View {
    PaneHeader(title: "Battery at a glance", lede: "Live readings from the battery controller, refreshed every few seconds.")
    if let snapshot = controller.snapshot {
      tiles(snapshot)
      RowGroup {
        PowerFlowRow(snapshot: snapshot)
          .padding(14)
      }
      chartPanel
      consumption(snapshot)
      EnergyAppsPanel()
    }
  }

  private func tiles(_ snapshot: BatterySnapshot) -> some View {
    HStack(spacing: 0) {
      tile("Full charge capacity", "\(snapshot.fullChargeCapacity.formatted()) mAh")
      divider
      tile("Design capacity", "\(snapshot.designCapacity.formatted()) mAh")
      divider
      tile("Health", String(format: "%.1f%%", snapshot.health))
      divider
      tile("Cycles", "\(snapshot.cycleCount)")
    }
    .panel(radius: 10)
  }

  private var divider: some View {
    Rectangle().fill(Theme.line).frame(width: 1)
  }

  private func tile(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.system(size: 11)).foregroundStyle(Theme.ink3)
      Text(value).font(Theme.mono(18, weight: .semibold)).foregroundStyle(Theme.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
  }

  private var chartPanel: some View {
    let samples = history.samples(since: .now.addingTimeInterval(-range.seconds))
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Charge level").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
        Spacer()
        Picker("Range", selection: $range) {
          ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      if samples.count < 2 {
        Text("Collecting data. The chart fills in as Keel records a reading every minute.")
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink3)
          .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        Chart {
          ForEach(samples) { sample in
            AreaMark(x: .value("Time", sample.date), y: .value("Percent", sample.percent))
              .foregroundStyle(Theme.held.opacity(0.15))
            LineMark(x: .value("Time", sample.date), y: .value("Percent", sample.percent))
              .foregroundStyle(Theme.held)
          }
          if let limit = controller.appliedLimit {
            RuleMark(y: .value("Limit", limit))
              .foregroundStyle(Theme.held.opacity(0.6))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          }
        }
        .chartYScale(domain: 0...100)
        .frame(height: 140)
      }
    }
    .padding(14)
    .panel(radius: 10)
  }

  private func consumption(_ snapshot: BatterySnapshot) -> some View {
    let average = history.averageWatts(lastMinutes: averageMinutes)
    return RowGroup {
      SettingRow(title: "Power consumption", detail: consumptionDetail(snapshot, average: average)) {
        Picker("Average over", selection: $averageMinutes) {
          Text("5 min").tag(5)
          Text("15 min").tag(15)
          Text("30 min").tag(30)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
    }
  }

  private func consumptionDetail(_ snapshot: BatterySnapshot, average: Double?) -> String {
    let now = snapshot.systemLoad.map { "Now \(Format.watts($0))" } ?? "Now n/a"
    guard let average else { return "\(now). No average yet." }
    var text = "\(now), average \(Format.watts(average))."
    // Time remaining from the chosen window: energy left in the battery over average draw.
    if !snapshot.isPluggedIn, average > 0.5 {
      let whLeft = Double(snapshot.remainingCapacity) / 1000 * snapshot.voltage
      text += " About \(Format.duration(Int(whLeft / average * 60))) left at this rate."
    }
    return text
  }
}

enum ChartRange: String, CaseIterable, Identifiable {
  case hour, day, week

  var id: String { rawValue }
  var title: String { self == .hour ? "1 h" : self == .day ? "24 h" : "7 days" }
  var seconds: TimeInterval { self == .hour ? 3600 : self == .day ? 86_400 : 604_800 }
}
