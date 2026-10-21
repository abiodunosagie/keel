import Charts
import SwiftUI

// Where the power comes from and how much the Mac is using.
struct PowerSection: View {
  let snapshot: BatterySnapshot

  var body: some View {
    let flow = PowerFlow(snapshot: snapshot)
    DetailGrid {
      DetailRow(String(localized: "Power from"), flow.sourceTitle)
      if let watts = flow.sourceWatts {
        DetailRow(String(localized: "Mac is using"), Format.watts(watts))
      }
      if snapshot.batteryWatts > PowerFlow.noiseWatts {
        DetailRow(String(localized: "Into the battery"), Format.watts(snapshot.batteryWatts))
      }
    }
  }
}

struct BatteryDetailsSection: View {
  @Environment(ChargeController.self) private var controller
  let snapshot: BatterySnapshot

  var body: some View {
    DetailGrid {
      DetailRow(String(localized: "Health"), Format.percent(snapshot.health))
      DetailRow(String(localized: "Cycles"), "\(snapshot.cycleCount)")
      if let temperature = snapshot.temperature {
        DetailRow(String(localized: "Temperature"), Format.temperature(temperature))
      }
      // With the hardware scale on, the popover's number differs from the macOS menu bar; say so here.
      if controller.settings.useHardwarePercent {
        DetailRow(String(localized: "macOS shows"), "\(snapshot.macOSPercent)%")
      }
    }
  }
}

struct ChargerSection: View {
  let snapshot: BatterySnapshot

  var body: some View {
    DetailGrid {
      if let charger = snapshot.charger {
        DetailRow(String(localized: "Charger"), charger.name)
        DetailRow(String(localized: "Rated"), "\(charger.watts) W")
        if let powerIn = snapshot.powerIn {
          DetailRow(String(localized: "Coming in"), Format.watts(powerIn))
        }
      } else {
        DetailRow(String(localized: "Charger"), String(localized: "Not connected"))
      }
    }
  }
}

// Label and value rows that line up across a section.
private struct DetailGrid<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      content
    }
    .font(.callout)
    .padding(.vertical, 10)
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  init(_ label: String, _ value: String) {
    self.label = label
    self.value = value
  }

  var body: some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value)
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

// The last 24 hours of charge, small.
struct MiniChart: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let samples = model.history.samples(since: .now.addingTimeInterval(-86_400))
    VStack(alignment: .leading, spacing: 6) {
      Text("Last 24 hours")
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
      Chart(samples) { sample in
        AreaMark(x: .value(String(localized: "Time"), sample.date), y: .value(String(localized: "Percent"), sample.percent))
          .foregroundStyle(Theme.held.opacity(0.18))
        LineMark(x: .value(String(localized: "Time"), sample.date), y: .value(String(localized: "Percent"), sample.percent))
          .foregroundStyle(Theme.held)
      }
      .chartYScale(domain: 0...100)
      .chartXAxis(.hidden)
      .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { AxisValueLabel() } }
      .frame(height: 56)
    }
    .padding(.vertical, 10)
  }
}
