import Foundation

// The steps of AlDente's Calibration Mode: charge to 100%, run down to 10% even on the charger,
// charge to 100% again, rest there for an hour, then return to the normal limit.
enum CalibrationStep: Codable, Equatable, Sendable {
  case chargeFull
  case dischargeLow
  case rechargeFull
  case hold(until: Date)
  case returnToLimit

  var title: String {
    switch self {
    case .chargeFull: return "Charge to 100%"
    case .dischargeLow: return "Discharge to \(Calibration.floor)%"
    case .rechargeFull: return "Charge to 100%"
    case .hold: return "Hold \(Int(Calibration.holdDuration / 3600)) hour"
    case .returnToLimit: return "Back to limit"
    }
  }

  // Position in the five-step sequence, for the progress display.
  var index: Int {
    switch self {
    case .chargeFull: return 0
    case .dischargeLow: return 1
    case .rechargeFull: return 2
    case .hold: return 3
    case .returnToLimit: return 4
    }
  }
}

enum Calibration {
  static let floor = HelperIdentity.batteryFloor
  static let holdDuration: TimeInterval = 60 * 60

  enum Outcome: Equatable {
    case next(CalibrationStep)
    case stay
    case finished
    // The charger was unplugged during a step that needs it.
    case aborted
  }

  static func advance(
    _ step: CalibrationStep,
    snapshot: BatterySnapshot,
    target: Int,
    now: Date
  ) -> Outcome {
    let isFull = snapshot.macOSPercent >= 100 || snapshot.isFullyCharged
    switch step {
    case .chargeFull:
      guard snapshot.isPluggedIn else { return .aborted }
      return isFull ? .next(.dischargeLow) : .stay
    case .dischargeLow:
      // Running on battery is the goal here, so unplugging does not stop it.
      return snapshot.macOSPercent <= floor ? .next(.rechargeFull) : .stay
    case .rechargeFull:
      guard snapshot.isPluggedIn else { return .aborted }
      return isFull ? .next(.hold(until: now.addingTimeInterval(holdDuration))) : .stay
    case .hold(let until):
      guard snapshot.isPluggedIn else { return .aborted }
      return now >= until ? .next(.returnToLimit) : .stay
    case .returnToLimit:
      return snapshot.macOSPercent <= target || !snapshot.isPluggedIn ? .finished : .stay
    }
  }
}
