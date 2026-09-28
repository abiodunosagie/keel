import Foundation

// What Keel is doing right now. The raw values match the states AlDente reports to Shortcuts,
// plus onBattery (unplugged) and macOSOverride (macOS charging past the limit on its own, for
// example to recalibrate its battery gauge).
enum ChargeState: String, Sendable {
  case charging = "Charging"
  case paused = "Pause"
  case discharging = "Discharging"
  case topUp = "Topup"
  case heatProtect = "HeatProtect"
  case calibration = "Calibration"
  case onBattery = "OnBattery"
  case macOSOverride = "MacOSOverride"
  case unavailable = "Exit"
}

// A temporary mode layered over the normal limit.
enum ChargeMode: Equatable, Sendable {
  case normal
  // Charge to 100% until the charger is unplugged once.
  case topUp
  // Run on battery down to the limit once, even with Automatic Discharge off.
  case discharge
  case calibration(CalibrationStep)
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
  // What the Max temperature setting allows, in °C. Apple advises below 35.
  static let temperatureRange: ClosedRange<Double> = 25...45

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

extension ClosedRange where Bound == Int {
  func clamped(_ value: Int) -> Int {
    Swift.min(Swift.max(value, lowerBound), upperBound)
  }
}

// Decides which limit to hand to macOS, whether the charger stays connected, and what to call
// the current state. Pure, so the whole behaviour is covered by tests without touching powerd.
enum ChargePolicy {
  struct Decision: Equatable, Sendable {
    // nil removes the limit (charge to 100%).
    var limit: Int?
    // false cuts the charger inside the Mac so it runs from the battery (needs the helper).
    var chargerConnected = true
    var state: ChargeState
  }

  // The limit on the macOS scale. macOS enforces its limit on the percentage it shows; with the
  // hardware percentage on, `hardwareOffset` (macOS minus hardware, in points) shifts it so the
  // battery really stops at the chosen hardware level.
  static func target(settings: ChargeSettings, hardwareOffset: Int, limitRange: ClosedRange<Int>) -> Int {
    limitRange.clamped(settings.limit + (settings.useHardwarePercent ? hardwareOffset : 0))
  }

  // The user-facing limit that holds the battery exactly where it is now.
  static func limitHoldingCurrentLevel(
    snapshot: BatterySnapshot,
    settings: ChargeSettings,
    hardwareOffset: Int,
    limitRange: ClosedRange<Int>
  ) -> Int {
    let offset = settings.useHardwarePercent ? hardwareOffset : 0
    return limitRange.clamped(snapshot.macOSPercent - offset)
  }

  static func decide(
    snapshot: BatterySnapshot,
    settings: ChargeSettings,
    mode: ChargeMode,
    heatPaused: Bool,
    hardwareOffset: Int,
    limitRange: ClosedRange<Int>
  ) -> Decision {
    let target = target(settings: settings, hardwareOffset: hardwareOffset, limitRange: limitRange)
    let here = limitRange.clamped(snapshot.macOSPercent)

    switch mode {
    case .topUp:
      return Decision(limit: nil, state: snapshot.isPluggedIn ? .topUp : .onBattery)
    case .calibration(let step):
      return calibrationDecision(step: step, target: target, snapshot: snapshot)
    case .discharge:
      let limit = normalize(target, limitRange)
      return Decision(limit: limit, state: state(snapshot: snapshot, limit: limit, heatPaused: false))
    case .normal:
      let limit: Int
      if heatPaused, snapshot.isPluggedIn, snapshot.macOSPercent >= limitRange.lowerBound {
        limit = min(target, here)
      } else if !settings.automaticDischarge, snapshot.macOSPercent > target {
        // Without automatic discharge a battery above the limit stays where it is instead of
        // being run down to the limit.
        limit = here
      } else {
        limit = target
      }
      let normalized = normalize(limit, limitRange)
      return Decision(limit: normalized, state: state(snapshot: snapshot, limit: normalized, heatPaused: heatPaused))
    }
  }

  // Calibration charges with no limit, cuts the charger to run down to the floor, charges to
  // full again, holds, then hands back to the normal limit (macOS drains down to it).
  private static func calibrationDecision(step: CalibrationStep, target: Int, snapshot: BatterySnapshot) -> Decision {
    switch step {
    case .chargeFull, .rechargeFull, .hold:
      return Decision(limit: nil, state: .calibration)
    case .dischargeLow:
      return Decision(limit: nil, chargerConnected: false, state: .calibration)
    case .returnToLimit:
      return Decision(limit: target >= 100 ? nil : target, state: .calibration)
    }
  }

  private static func normalize(_ limit: Int, _ range: ClosedRange<Int>) -> Int? {
    limit >= range.upperBound ? nil : limit
  }

  private static func state(snapshot: BatterySnapshot, limit: Int?, heatPaused: Bool) -> ChargeState {
    guard snapshot.isPluggedIn else { return .onBattery }
    if heatPaused, !snapshot.isCharging { return .heatProtect }
    let percent = snapshot.macOSPercent
    let ceiling = limit ?? 100
    if snapshot.isCharging {
      // Charging one point past the limit is normal rounding; more than that is macOS itself.
      return percent >= ceiling + 1 ? .macOSOverride : .charging
    }
    // A small negative current while plugged in is the battery covering a load spike; only a
    // steady drain above the limit counts as discharging.
    if snapshot.amperage < -0.05, percent > ceiling { return .discharging }
    return .paused
  }
}
