import Foundation
import Observation

// A reading kept for the dashboard charts.
struct BatterySample: Codable, Equatable, Identifiable, Sendable {
  var date: Date
  var percent: Int
  // Whole-Mac power draw. nil for readings imported from the macOS power log, which only
  // records the charge level.
  var watts: Double?
  var temperature: Double?
  var pluggedIn: Bool

  var id: Date { date }
}

// Records one sample a minute and keeps the last seven days on disk, so the charts have data
// right after a relaunch.
@MainActor
@Observable
final class BatteryHistory {
  static let interval: TimeInterval = 60
  static let keep: TimeInterval = 7 * 24 * 60 * 60

  private(set) var samples: [BatterySample] = []
  private var timer: Timer?
  private var unsaved = 0
  private let fileURL: URL?

  init(fileURL: URL? = BatteryHistory.defaultFileURL()) {
    self.fileURL = fileURL
    if let fileURL, let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode([BatterySample].self, from: data) {
      samples = saved
    }
  }

  // Fills the time before Keel's first reading with the charge levels macOS logged at every
  // sleep and wake (`pmset -g log`, about the last week), so the chart shows real history at once.
  func importPowerLog() async {
    let firstOwn = samples.first(where: { $0.watts != nil })?.date ?? .now
    let imported = await Task.detached(priority: .utility) { PowerLog.read() }.value
    let older = imported.filter { $0.date < firstOwn && $0.date > firstOwn.addingTimeInterval(-Self.keep) }
    let known = Set(samples.map(\.date))
    let fresh = older.filter { !known.contains($0.date) }
    guard !fresh.isEmpty else { return }
    samples = (fresh + samples).sorted { $0.date < $1.date }
    unsaved += fresh.count
    flush()
  }

  func start(reading: @escaping @MainActor () -> BatterySnapshot?) {
    if let snapshot = reading() { record(snapshot, at: .now) }
    timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let snapshot = reading() else { return }
        self?.record(snapshot, at: .now)
      }
    }
  }

  func record(_ snapshot: BatterySnapshot, at date: Date) {
    samples.append(BatterySample(
      date: date,
      percent: snapshot.macOSPercent,
      watts: snapshot.systemLoad ?? abs(snapshot.batteryWatts),
      temperature: snapshot.temperature,
      pluggedIn: snapshot.isPluggedIn
    ))
    samples.removeAll { date.timeIntervalSince($0.date) > Self.keep }
    // Seven days is about a megabyte of JSON, so it is written every ten samples and on quit.
    unsaved += 1
    if unsaved >= 10 { flush() }
  }

  func flush() {
    guard unsaved > 0, let fileURL, let data = try? JSONEncoder().encode(samples) else { return }
    try? data.write(to: fileURL, options: .atomic)
    unsaved = 0
  }

  func samples(since date: Date) -> [BatterySample] {
    samples.filter { $0.date >= date }
  }

  // Average power draw over the last `minutes`, for the time-remaining estimate.
  func averageWatts(lastMinutes minutes: Int, now: Date = .now) -> Double? {
    let recent = samples(since: now.addingTimeInterval(-Double(minutes) * 60))
    let watts = recent.compactMap(\.watts)
    guard !watts.isEmpty else { return nil }
    return watts.reduce(0, +) / Double(watts.count)
  }

  nonisolated private static func defaultFileURL() -> URL? {
    guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Keel", isDirectory: true) else {
      return nil
    }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("history.json")
  }
}
