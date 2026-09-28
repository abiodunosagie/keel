import Foundation

// Keeps the charge settings, and the macOS charge limit that was in place before Keel first
// ran so it can be put back when Keel is removed.
struct SettingsStore: @unchecked Sendable {
  private enum Key {
    static let limit = "chargeLimit"
    static let automaticDischarge = "automaticDischarge"
    static let heatProtection = "heatProtection"
    static let maxTemperature = "maxTemperature"
    static let useHardwarePercent = "useHardwarePercent"
    static let originalRecorded = "originalLimitRecorded"
    static let originalLimit = "originalLimit"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> ChargeSettings {
    var settings = ChargeSettings()
    if let limit = defaults.object(forKey: Key.limit) as? Int { settings.limit = limit }
    if let value = defaults.object(forKey: Key.automaticDischarge) as? Bool { settings.automaticDischarge = value }
    if let value = defaults.object(forKey: Key.heatProtection) as? Bool { settings.heatProtection = value }
    if let value = defaults.object(forKey: Key.maxTemperature) as? Double { settings.maxTemperature = value }
    if let value = defaults.object(forKey: Key.useHardwarePercent) as? Bool { settings.useHardwarePercent = value }
    return settings
  }

  func save(_ settings: ChargeSettings) {
    defaults.set(settings.limit, forKey: Key.limit)
    defaults.set(settings.automaticDischarge, forKey: Key.automaticDischarge)
    defaults.set(settings.heatProtection, forKey: Key.heatProtection)
    defaults.set(settings.maxTemperature, forKey: Key.maxTemperature)
    defaults.set(settings.useHardwarePercent, forKey: Key.useHardwarePercent)
  }

  // nil means macOS had no limit.
  var originalLimit: Int? {
    defaults.object(forKey: Key.originalLimit) as? Int
  }

  // Skipped when reading fails, so a later launch tries again.
  func recordOriginalLimitIfNeeded(_ read: () throws -> Int?) {
    guard !defaults.bool(forKey: Key.originalRecorded), let limit = try? Optional(read()) else { return }
    if let limit {
      defaults.set(limit, forKey: Key.originalLimit)
    } else {
      defaults.removeObject(forKey: Key.originalLimit)
    }
    defaults.set(true, forKey: Key.originalRecorded)
  }
}
