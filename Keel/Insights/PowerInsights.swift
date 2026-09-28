import Foundation
import Observation

// A charger Keel has seen, and how it did.
struct ChargerRecord: Codable, Equatable, Identifiable, Sendable {
  var charger: ChargerInfo
  var firstSeen: Date
  var lastSeen: Date
  var connections: Int
  // Times the battery had to help because this charger couldn't cover the Mac's draw.
  var shortfalls: Int

  var id: String { "\(charger.name)|\(charger.watts)" }
}

// One charging session, from when charging starts until it stops.
struct ChargingSession: Codable, Equatable, Identifiable, Sendable {
  var start: Date
  var end: Date
  var startPercent: Int
  var endPercent: Int
  var energyWh: Double
  var chargerName: String?

  var id: Date { start }
  var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

// The battery's capacity on one day, for the health trend.
struct HealthRecord: Codable, Equatable, Identifiable, Sendable {
  var day: Date
  var fullChargeCapacity: Int
  var designCapacity: Int
  var cycles: Int

  var id: Date { day }
  var health: Double {
    designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) * 100 : 0
  }
}

// Something wrong with the charger right now.
enum ChargerProblem: Equatable, Sendable {
  // Plugged in, but no power comes in: a bad cable, port or monitor that doesn't supply power.
  case noPower
  // Power comes in, but less than the Mac uses, so the battery drains anyway.
  case tooWeak(chargerWatts: Int?, loadWatts: Double)
  // The battery controller is slowing charging (heat or a limited charger).
  case slowCharging

  var message: String {
    switch self {
    case .noPower:
      return "A charger is plugged in but isn't powering the Mac. Try another cable, port or charger."
    case .tooWeak(let watts, let load):
      let rating = watts.map { "The \($0) W charger" } ?? "The charger"
      return "\(rating) can't keep up with the Mac's \(Format.watts(load)), so the battery is draining."
    case .slowCharging:
      return "macOS is charging slowly, usually because of heat or a low-power charger."
    }
  }
}

// Watches every battery reading for charger history, charging sessions, the health trend and
// charger problems. Kept on disk so the history survives relaunches.
@MainActor
@Observable
final class PowerInsights {
  // A problem must last this many readings (about 15 s) before Keel mentions it.
  static let problemConfirmations = 3
  static let minimumSessionMinutes = 2.0
  static let keepSessions = 200

  private(set) var chargers: [ChargerRecord] = []
  private(set) var sessions: [ChargingSession] = []
  private(set) var health: [HealthRecord] = []
  private(set) var problem: ChargerProblem?
  var onProblem: ((ChargerProblem) -> Void)?

  private var previous: BatterySnapshot?
  private var lastUpdate: Date?
  private var openSession: ChargingSession?
  private var candidate: ChargerProblem?
  private var candidateCount = 0
  private var announced = false
  private let fileURL: URL?

  private struct Saved: Codable {
    var chargers: [ChargerRecord]
    var sessions: [ChargingSession]
    var health: [HealthRecord]
  }

  init(fileURL: URL? = PowerInsights.defaultFileURL()) {
    self.fileURL = fileURL
    if let fileURL, let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode(Saved.self, from: data) {
      chargers = saved.chargers
      sessions = saved.sessions
      health = saved.health
    }
  }

  // `drainExpected` is true while Keel itself runs the Mac on battery (Discharge, calibration,
  // or macOS bringing the battery down to the limit).
  func update(_ snapshot: BatterySnapshot, drainExpected: Bool, now: Date) {
    let seconds = lastUpdate.map { min(now.timeIntervalSince($0), 60) } ?? 0
    var changed = trackCharger(snapshot, now: now)
    changed = trackSession(snapshot, seconds: seconds, now: now) || changed
    changed = trackHealth(snapshot, now: now) || changed
    trackProblem(snapshot, drainExpected: drainExpected)
    previous = snapshot
    lastUpdate = now
    if changed { save() }
  }

  // Where health is heading: the day it is expected to reach `threshold` percent, from a
  // straight-line fit over the recorded days. nil until there are two weeks of records or
  // while health is not falling.
  static func forecast(_ records: [HealthRecord], threshold: Double = 80) -> Date? {
    guard records.count >= 3, let first = records.first, let last = records.last,
          last.day.timeIntervalSince(first.day) >= 14 * 86_400 else {
      return nil
    }
    let xs = records.map { $0.day.timeIntervalSince(first.day) / 86_400 }
    let ys = records.map(\.health)
    let n = Double(records.count)
    let meanX = xs.reduce(0, +) / n
    let meanY = ys.reduce(0, +) / n
    let covariance = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
    let variance = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
    guard variance > 0 else { return nil }
    let slope = covariance / variance // health points per day
    guard slope < 0 else { return nil }
    let intercept = meanY - slope * meanX
    let day = (threshold - intercept) / slope
    guard day.isFinite, day > xs.last ?? 0 else { return nil }
    return first.day.addingTimeInterval(day * 86_400)
  }

  // Charging sessions and chargers as CSV, for a spreadsheet.
  func sessionsCSV() -> String {
    var lines = ["start,end,minutes,start_percent,end_percent,energy_wh,charger"]
    for session in sessions {
      lines.append([
        CSV.date(session.start), CSV.date(session.end), "\(session.minutes)", "\(session.startPercent)",
        "\(session.endPercent)", String(format: "%.2f", session.energyWh), CSV.field(session.chargerName ?? ""),
      ].joined(separator: ","))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func trackCharger(_ snapshot: BatterySnapshot, now: Date) -> Bool {
    guard let charger = snapshot.charger else { return false }
    let justPlugged = previous?.charger == nil
    if let index = chargers.firstIndex(where: { $0.charger.name == charger.name && $0.charger.watts == charger.watts }) {
      chargers[index].lastSeen = now
      chargers[index].charger = charger
      if justPlugged { chargers[index].connections += 1 }
      return justPlugged
    }
    chargers.append(ChargerRecord(charger: charger, firstSeen: now, lastSeen: now, connections: 1, shortfalls: 0))
    return true
  }

  private func trackSession(_ snapshot: BatterySnapshot, seconds: TimeInterval, now: Date) -> Bool {
    if snapshot.isCharging {
      if openSession == nil {
        openSession = ChargingSession(start: now, end: now, startPercent: snapshot.macOSPercent,
                                      endPercent: snapshot.macOSPercent, energyWh: 0, chargerName: snapshot.charger?.name)
      }
      openSession?.end = now
      openSession?.endPercent = snapshot.macOSPercent
      openSession?.energyWh += max(0, snapshot.batteryWatts) * seconds / 3600
      return false
    }
    guard let session = openSession else { return false }
    openSession = nil
    guard session.end.timeIntervalSince(session.start) >= Self.minimumSessionMinutes * 60 else { return false }
    sessions.insert(session, at: 0)
    if sessions.count > Self.keepSessions { sessions.removeLast(sessions.count - Self.keepSessions) }
    return true
  }

  private func trackHealth(_ snapshot: BatterySnapshot, now: Date) -> Bool {
    guard snapshot.fullChargeCapacity > 0, snapshot.designCapacity > 0 else { return false }
    let day = Calendar.current.startOfDay(for: now)
    guard health.last?.day != day else { return false }
    health.append(HealthRecord(day: day, fullChargeCapacity: snapshot.fullChargeCapacity,
                               designCapacity: snapshot.designCapacity, cycles: snapshot.cycleCount))
    return true
  }

  private func trackProblem(_ snapshot: BatterySnapshot, drainExpected: Bool) {
    let found = Self.problem(in: snapshot, drainExpected: drainExpected)
    if found == nil || found != candidate {
      candidate = found
      candidateCount = found == nil ? 0 : 1
    } else {
      candidateCount += 1
    }
    if !snapshot.isPluggedIn { announced = false }
    let confirmed = candidateCount >= Self.problemConfirmations ? candidate : nil
    if confirmed != problem {
      problem = confirmed
      if let confirmed, !announced {
        announced = true
        if case .tooWeak = confirmed, let name = snapshot.charger?.name,
           let index = chargers.firstIndex(where: { $0.charger.name == name }) {
          chargers[index].shortfalls += 1
          save()
        }
        onProblem?(confirmed)
      }
    }
  }

  static func problem(in snapshot: BatterySnapshot, drainExpected: Bool) -> ChargerProblem? {
    guard snapshot.isPluggedIn, !drainExpected else { return nil }
    let draining = snapshot.batteryWatts < -1
    if draining, (snapshot.powerIn ?? 0) < 2 { return .noPower }
    if draining { return .tooWeak(chargerWatts: snapshot.charger?.watts, loadWatts: snapshot.systemLoad ?? 0) }
    if snapshot.isCharging, snapshot.slowChargingReason != 0 { return .slowCharging }
    return nil
  }

  private func save() {
    guard let fileURL,
          let data = try? JSONEncoder().encode(Saved(chargers: chargers, sessions: sessions, health: health)) else {
      return
    }
    try? data.write(to: fileURL, options: .atomic)
  }

  nonisolated private static func defaultFileURL() -> URL? {
    guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Keel", isDirectory: true) else {
      return nil
    }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("insights.json")
  }
}

enum CSV {
  static func date(_ date: Date) -> String {
    date.ISO8601Format()
  }

  // Quotes a field when it holds a comma, quote or line break.
  static func field(_ text: String) -> String {
    guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
