import Charts
import SwiftUI
import UniformTypeIdentifiers

struct HistoryPane: View {
  @Environment(PowerInsights.self) private var insights
  @Environment(BatteryHistory.self) private var history
  @State private var exportError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        PaneHeader(title: String(localized: "Health and history"), lede: String(localized: "How the battery ages, every charging session, and every charger Keel has seen."))
        Spacer()
        Menu("Export") {
          Button("Readings (every minute)…") { export(history.csv(), name: String(localized: "Keel readings")) }
          Button("Charging sessions…") { export(insights.sessionsCSV(), name: String(localized: "Keel charging sessions")) }
        }
        .fixedSize()
      }
      if let exportError {
        ProblemBanner(text: exportError)
      }
      healthPanel
      sessionsPanel
      chargersPanel
    }
  }

  private var healthPanel: some View {
    let records = insights.health
    return VStack(alignment: .leading, spacing: 10) {
      Text("Battery health").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      if records.count >= 2 {
        Chart(records) { record in
          LineMark(x: .value(String(localized: "Day"), record.day), y: .value(String(localized: "Health"), record.health))
            .foregroundStyle(Theme.held)
          PointMark(x: .value(String(localized: "Day"), record.day), y: .value(String(localized: "Health"), record.health))
            .foregroundStyle(Theme.held)
        }
        .chartYScale(domain: max(0, (records.map(\.health).min() ?? 80) - 5)...100)
        .frame(height: 120)
      }
      Text(healthText(records))
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .panel(radius: 10)
  }

  private func healthText(_ records: [HealthRecord]) -> String {
    guard let last = records.last else { return String(localized: "Keel records the battery's capacity once a day.") }
    var text = String(localized: "Now \(Format.percent(last.health)) of its original capacity after \(last.cycles) cycles.")
    if let date = PowerInsights.forecast(records) {
      text += String(localized: " At this rate it reaches 80%, Apple's service mark, around \(date.formatted(.dateTime.month(.wide).year())).")
    } else if records.count >= 3,
              let first = records.first, last.day.timeIntervalSince(first.day) >= 14 * 86_400 {
      text += String(localized: " It hasn't dropped over the recorded period.")
    } else {
      text += String(localized: " A forecast appears after two weeks of daily records.")
    }
    return text
  }

  private var sessionsPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Charging sessions").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      if insights.sessions.isEmpty {
        Text("Each time the Mac charges, Keel logs how long it took and how much energy went in.")
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink3)
      } else {
        RowGroup {
          ForEach(insights.sessions.prefix(12)) { session in
            HStack {
              Text("\(session.startPercent)% to \(session.endPercent)%").foregroundStyle(Theme.ink)
              Text(String(localized: "\(Format.number(session.energyWh, digits: 1)) Wh in \(Format.duration(max(1, session.minutes)))"))
                .foregroundStyle(Theme.ink2)
              Spacer()
              Text(session.start.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.ink2)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
          }
        }
      }
    }
  }

  private var chargersPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Chargers").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      if insights.chargers.isEmpty {
        Text("Chargers you plug in appear here with their rating and how they coped.")
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink3)
      } else {
        RowGroup {
          ForEach(insights.chargers) { record in
            SettingRow(title: record.charger.name, detail: detail(record)) {
              ValueChip(text: "\(record.charger.watts) W")
            }
          }
        }
      }
    }
  }

  private func detail(_ record: ChargerRecord) -> String {
    let last = record.lastSeen.formatted(date: .abbreviated, time: .shortened)
    var text = String(localized: "Connections: \(record.connections). Last seen \(last).")
    if record.shortfalls > 0 {
      text += " " + String(localized: "Times it couldn't keep up and the battery had to help: \(record.shortfalls).")
    }
    return text
  }

  private func export(_ csv: String, name: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = String(localized: "\(name).csv")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try csv.write(to: url, atomically: true, encoding: .utf8)
      exportError = nil
    } catch {
      exportError = String(localized: "Couldn't save the file there. Pick another folder.")
    }
  }
}
