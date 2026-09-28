import Charts
import SwiftUI

struct DashboardPane: View {
  @Environment(ChargeController.self) private var controller
  @Environment(BatteryHistory.self) private var history
  @Environment(HelperClient.self) private var helper
  @Environment(PowerInsights.self) private var insights
  @State private var apps: [EnergyApp]?
  @State private var chip: ChipPower?
  @State private var range: ChartRange = .day
  @State private var metric: ChartMetric = .charge
  @State private var averageMinutes = 15

  var body: some View {
    PaneHeader(title: "Battery at a glance", lede: "Live readings from the battery controller, refreshed every few seconds.")
      .background(sampling())
    if let snapshot = controller.snapshot {
      if let problem = insights.problem {
        ProblemBanner(text: problem.message)
      }
      tiles(snapshot)
      RowGroup {
        PowerFlowRow(snapshot: snapshot)
          .padding(14)
        PowerBreakdown(snapshot: snapshot, chip: chip, helperReady: helper.isReady)
      }
      ChargerPanel(snapshot: snapshot)
      DrainPanel(lines: DrainSummary.sentences(
        snapshot: snapshot, averageWatts: history.averageWatts(lastMinutes: 15), chip: chip, apps: apps ?? []
      ))
      chartPanel
      consumption(snapshot)
      EnergyAppsPanel(apps: apps)
    }
  }

  // Live samples that cost something (a `top` run, a powermetrics run in the helper) are only
  // taken while the dashboard is on screen.
  func sampling() -> some View {
    EmptyView()
      .task {
        while !Task.isCancelled {
          apps = await Task.detached(priority: .utility) { EnergyApp.sample() }.value
          try? await Task.sleep(for: .seconds(15))
        }
      }
      .task(id: helper.isReady) {
        guard helper.isReady else { return }
        while !Task.isCancelled {
          chip = await helper.readChipPower()
          try? await Task.sleep(for: .seconds(10))
        }
      }
  }

  private func tiles(_ snapshot: BatterySnapshot) -> some View {
    StatStrip(items: [
      ("Full charge capacity", "\(snapshot.fullChargeCapacity.formatted()) mAh"),
      ("Design capacity", "\(snapshot.designCapacity.formatted()) mAh"),
      ("Health", Format.percent(snapshot.health)),
      ("Cycles", "\(snapshot.cycleCount)"),
    ], valueSize: 18, padding: 14)
    .padding(.vertical, 14)
    .panel(radius: 10)
  }

  private var chartPanel: some View {
    let from = Date.now.addingTimeInterval(-range.seconds)
    let points = history.samples(since: from).compactMap { sample -> ChartPoint? in
      guard let value = metric.value(of: sample) else { return nil }
      return ChartPoint(date: sample.date, value: value)
    }
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Picker("Chart", selection: $metric) {
          ForEach(ChartMetric.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        Spacer()
        Picker("Range", selection: $range) {
          ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      if points.count < 2 {
        Text(metric.emptyText)
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink3)
          .frame(maxWidth: .infinity, minHeight: 150)
      } else {
        Chart {
          ForEach(points) { point in
            AreaMark(x: .value("Time", point.date), yStart: .value("Base", metric.domain.lowerBound),
                     yEnd: .value(metric.title, point.value))
              .foregroundStyle(metric.color.opacity(0.14))
            LineMark(x: .value("Time", point.date), y: .value(metric.title, point.value))
              .foregroundStyle(metric.color)
          }
          if metric == .charge, let limit = controller.appliedLimit {
            RuleMark(y: .value("Limit", limit))
              .foregroundStyle(Theme.held.opacity(0.6))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          }
          if metric == .temperature, controller.settings.heatProtection {
            RuleMark(y: .value("Max", controller.settings.maxTemperature))
              .foregroundStyle(Theme.heat.opacity(0.6))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          }
        }
        .chartXScale(domain: from...Date.now)
        .chartYScale(domain: metric.domain(for: points.map(\.value)))
        .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel() } }
        .frame(height: 150)
      }
      Text(metric.footnote)
        .font(.system(size: 11))
        .foregroundStyle(Theme.ink3)
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

struct ChartPoint: Identifiable {
  var date: Date
  var value: Double
  var id: Date { date }
}

enum ChartMetric: String, CaseIterable, Identifiable {
  case charge, power, temperature

  var id: String { rawValue }

  var title: String {
    switch self {
    case .charge: return "Charge"
    case .power: return "Power"
    case .temperature: return "Temperature"
    }
  }

  var color: Color {
    switch self {
    case .charge: return Theme.held
    case .power: return Theme.accent
    case .temperature: return Theme.moving
    }
  }

  var domain: ClosedRange<Double> {
    switch self {
    case .charge: return 0...100
    case .power: return 0...10
    case .temperature: return 20...45
    }
  }

  // Charge keeps a fixed 0 to 100 scale; the others grow to fit the data.
  func domain(for values: [Double]) -> ClosedRange<Double> {
    guard self != .charge, let high = values.max(), let low = values.min() else { return domain }
    return min(domain.lowerBound, low.rounded(.down))...max(domain.upperBound, (high * 1.1).rounded(.up))
  }

  func value(of sample: BatterySample) -> Double? {
    switch self {
    case .charge: return Double(sample.percent)
    case .power: return sample.watts
    case .temperature: return sample.temperature
    }
  }

  var emptyText: String {
    switch self {
    case .charge: return "No readings in this range yet."
    case .power, .temperature: return "Collecting data. Keel records a reading every minute."
    }
  }

  var footnote: String {
    switch self {
    case .charge: return "Keel's readings every minute, plus the levels macOS logged at each sleep and wake. Dashed line: your limit."
    case .power: return "Watts the whole Mac used, recorded every minute."
    case .temperature: return "Battery temperature, recorded every minute. Dashed line: Heat Protection's limit."
    }
  }
}
