import Foundation

// Whatever holds the battery at a charge limit. The app talks only to this protocol so the
// tests can run against a fake and never touch powerd.
protocol ChargeBackend: Sendable {
  var isAvailable: Bool { get }
  var limitRange: ClosedRange<Int> { get }
  // The active limit in percent, or nil when charging is unlimited.
  func currentLimit() throws -> Int?
  // Pass nil to remove the limit.
  func apply(limit: Int?) throws
}

// The charge limit built into macOS 26.4 and later. powerd enforces it on its own, so it keeps
// working while the Mac sleeps, after a restart and when Keel is closed. When the battery is
// above the limit on the charger, macOS runs the Mac from the battery until it is back down.
struct NativeChargeBackend: ChargeBackend {
  // KeelPowerUI serializes every call internally, so sharing it across threads is safe.
  private nonisolated(unsafe) let powerUI = KeelPowerUI.shared()

  // A round trip to powerd: ChargeController asks once, off the main thread, and caches it.
  var isAvailable: Bool { powerUI?.isSupported() ?? false }

  var limitRange: ClosedRange<Int> { KeelPowerUI.minimumLimit...KeelPowerUI.maximumLimit }

  func currentLimit() throws -> Int? {
    guard let powerUI else { throw ChargeBackendError.unavailable }
    guard try powerUI.limitEnabled().boolValue else { return nil }
    let limit = try powerUI.limitPercent().intValue
    return limit >= KeelPowerUI.maximumLimit ? nil : limit
  }

  func apply(limit: Int?) throws {
    guard let powerUI else { throw ChargeBackendError.unavailable }
    if let limit {
      guard limitRange.contains(limit) else { throw ChargeBackendError.outOfRange(limit) }
      try powerUI.setLimit(limit)
    } else {
      try powerUI.disableLimit()
    }
  }
}

enum ChargeBackendError: LocalizedError, Equatable {
  case unavailable
  case outOfRange(Int)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "This Mac has no built-in charge limit. It needs macOS 26.4 or later on Apple silicon."
    case .outOfRange(let limit):
      return "macOS can't hold the battery at \(limit)%. Pick \(KeelPowerUI.minimumLimit)% or higher."
    }
  }
}
