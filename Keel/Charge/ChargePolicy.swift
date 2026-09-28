import Foundation

// What Keel is doing right now. The raw values match the states AlDente reports, plus
// onBattery (unplugged) and macOSOverride (macOS charging past the limit on its own, for
// example to recalibrate its battery gauge).
enum ChargeState: String, Sendable, CaseIterable {
  case charging = "Charging"
  case paused = "Pause"
  case discharging = "Discharging"
  case topUp = "Topup"
  case heatProtect = "HeatProtect"
  case onBattery = "OnBattery"
  case macOSOverride = "MacOSOverride"
  case unavailable = "Exit"
}

struct ChargeSettings: Equatable, Sendable {
  var limit: Int = 80
  var automaticDischarge = true
  var heatProtection = false
  var maxTemperature: Double = 35
  var useHardwarePercent = false
}

// Heat Protection's hysteresis, as AlDente documents it: when the battery gets hotter than
// the limit, charging pauses for at least five minutes. After that, if it is still too hot it
// pauses for another five; if it has cooled, charging runs for at least five minutes even if
// the temperature climbs again.
struct HeatGuard: Equatable, Sendable {
  enum Phase: Equatable, Sendable {
    case idle
    case paused(since: Date)
    case resumed(since: Date)
  }

  static let window: TimeInterval = 5 * 60

  private(set) var phase: Phase = .idle

  var isPaused: Bool {
    if case .paused = phase { return true }
    return false
  }

  mutating func update(temperature: Double?, limit: Double, now: Date) {
    let tooHot = (temperature ?? 0) > limit
    switch phase {
    case .idle:
      if tooHot { phase = .paused(since: now) }
    case .paused(let since):
      guard now.timeIntervalSince(since) >= Self.window else { return }
      phase = tooHot ? .paused(since: now) : .resumed(since: now)
    case .resumed(let since):
      guard now.timeIntervalSince(since) >= Self.window else { return }
      phase = tooHot ? .paused(since: now) : .idle
    }
  }

  mutating func reset() {
    phase = .idle
  }
}

// Decides which limit to hand to macOS and what to call the current state. Pure, so the whole
// behaviour is covered by tests without touching powerd.
enum ChargePolicy {
  struct Decision: Equatable, Sendable {
    // nil removes the limit (charge to 100%).
    var limit: Int?
    var state: ChargeState
  }

  static func decide(
    snapshot: BatterySnapshot,
    settings: ChargeSettings,
    topUp: Bool,
    heatPaused: Bool,
    limitRange: ClosedRange<Int>
  ) -> Decision {
    // macOS enforces its limit on the percentage it shows. With the hardware percentage on,
    // the limit is shifted by the gap between the two scales so the battery really stops at
    // the chosen hardware level.
    let offset = settings.useHardwarePercent
      ? Int((Double(snapshot.macOSPercent) - snapshot.hardwarePercent).rounded())
      : 0
    let clamp = { (value: Int) in min(max(value, limitRange.lowerBound), limitRange.upperBound) }
    let target = clamp(settings.limit + offset)
    // Holding "where it is now" means the macOS percentage the battery has reached.
    let here = clamp(snapshot.macOSPercent)

    let limit: Int?
    if topUp {
      limit = nil
    } else if heatPaused, snapshot.isPluggedIn, snapshot.macOSPercent >= limitRange.lowerBound {
      limit = min(target, here)
    } else if !settings.automaticDischarge, snapshot.macOSPercent > target {
      // Without automatic discharge a battery above the limit stays where it is instead of
      // being run down to the limit.
      limit = here
    } else {
      limit = target
    }
    let normalized = limit.flatMap { $0 >= limitRange.upperBound ? nil : $0 }
    return Decision(limit: normalized, state: state(snapshot: snapshot, limit: normalized,
                                                     topUp: topUp, heatPaused: heatPaused))
  }

  private static func state(
    snapshot: BatterySnapshot,
    limit: Int?,
    topUp: Bool,
    heatPaused: Bool
  ) -> ChargeState {
    guard snapshot.isPluggedIn else { return .onBattery }
    if topUp { return .topUp }
    if heatPaused, !snapshot.isCharging { return .heatProtect }
    let percent = Double(snapshot.macOSPercent)
    let ceiling = Double(limit ?? 100)
    if snapshot.isCharging {
      // Charging one point past the limit is normal rounding; more than that is macOS itself.
      return percent >= ceiling + 1 ? .macOSOverride : .charging
    }
    if snapshot.amperage < -0.05, percent > ceiling { return .discharging }
    return .paused
  }
}
