import Foundation

// App behaviour that isn't part of the charge rules.
struct AppOptions: Equatable, Sendable {
  enum Light: String, Sendable, CaseIterable {
    case auto // green at the limit, orange while charging or discharging
    case system // macOS controls the light
  }

  var keepLimitWhenClosed = true
  var keepAwakeUntilLimit = false
  var notifications = true
  var magSafeLight: Light = .system
  var menuBarPercent = true
  var menuBarWatts = false
  var menuBarTemperature = false
}

// Keeps the settings, the calibration bookkeeping, and the macOS charge limit that was in
// place before Keel first ran so it can be put back when Keel is removed.
struct SettingsStore: @unchecked Sendable {
  private enum Key {
    static let limit = "chargeLimit"
    static let automaticDischarge = "automaticDischarge"
    static let heatProtection = "heatProtection"
    static let maxTemperature = "maxTemperature"
    static let useHardwarePercent = "useHardwarePercent"
    static let originalRecorded = "originalLimitRecorded"
    static let originalLimit = "originalLimit"
    static let keepLimitWhenClosed = "keepLimitWhenClosed"
    static let keepAwakeUntilLimit = "keepAwakeUntilLimit"
    static let notifications = "notifications"
    static let magSafeLight = "magSafeLight"
    static let menuBarPercent = "menuBarPercent"
    static let menuBarWatts = "menuBarWatts"
    static let menuBarTemperature = "menuBarTemperature"
    static let lastCalibration = "lastCalibration"
    static let calibrationRunning = "calibrationRunning"
  }

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  private func value<T>(_ key: String) -> T? {
    defaults.object(forKey: key) as? T
  }

  func load() -> ChargeSettings {
    let base = ChargeSettings()
    return ChargeSettings(
      limit: value(Key.limit) ?? base.limit,
      automaticDischarge: value(Key.automaticDischarge) ?? base.automaticDischarge,
      heatProtection: value(Key.heatProtection) ?? base.heatProtection,
      maxTemperature: value(Key.maxTemperature) ?? base.maxTemperature,
      useHardwarePercent: value(Key.useHardwarePercent) ?? base.useHardwarePercent
    )
  }

  func save(_ settings: ChargeSettings) {
    defaults.set(settings.limit, forKey: Key.limit)
    defaults.set(settings.automaticDischarge, forKey: Key.automaticDischarge)
    defaults.set(settings.heatProtection, forKey: Key.heatProtection)
    defaults.set(settings.maxTemperature, forKey: Key.maxTemperature)
    defaults.set(settings.useHardwarePercent, forKey: Key.useHardwarePercent)
  }

  func loadOptions() -> AppOptions {
    let base = AppOptions()
    return AppOptions(
      keepLimitWhenClosed: value(Key.keepLimitWhenClosed) ?? base.keepLimitWhenClosed,
      keepAwakeUntilLimit: value(Key.keepAwakeUntilLimit) ?? base.keepAwakeUntilLimit,
      notifications: value(Key.notifications) ?? base.notifications,
      magSafeLight: (value(Key.magSafeLight) as String?).flatMap(AppOptions.Light.init) ?? base.magSafeLight,
      menuBarPercent: value(Key.menuBarPercent) ?? base.menuBarPercent,
      menuBarWatts: value(Key.menuBarWatts) ?? base.menuBarWatts,
      menuBarTemperature: value(Key.menuBarTemperature) ?? base.menuBarTemperature
    )
  }

  func save(_ options: AppOptions) {
    defaults.set(options.keepLimitWhenClosed, forKey: Key.keepLimitWhenClosed)
    defaults.set(options.keepAwakeUntilLimit, forKey: Key.keepAwakeUntilLimit)
    defaults.set(options.notifications, forKey: Key.notifications)
    defaults.set(options.magSafeLight.rawValue, forKey: Key.magSafeLight)
    defaults.set(options.menuBarPercent, forKey: Key.menuBarPercent)
    defaults.set(options.menuBarWatts, forKey: Key.menuBarWatts)
    defaults.set(options.menuBarTemperature, forKey: Key.menuBarTemperature)
  }

  var lastCalibration: Date? {
    get { value(Key.lastCalibration) }
    nonmutating set { defaults.set(newValue, forKey: Key.lastCalibration) }
  }

  // Set while calibration runs, so a launch after a crash knows it was cut short.
  var calibrationWasRunning: Bool {
    get { defaults.bool(forKey: Key.calibrationRunning) }
    nonmutating set { defaults.set(newValue, forKey: Key.calibrationRunning) }
  }

  // nil means macOS had no limit.
  var originalLimit: Int? {
    value(Key.originalLimit)
  }

  // Skipped when reading fails, so a later launch tries again.
  func recordOriginalLimitIfNeeded(_ read: () throws -> Int?) {
    guard !defaults.bool(forKey: Key.originalRecorded) else { return }
    let limit: Int?
    do {
      limit = try read()
    } catch {
      return
    }
    if let limit {
      defaults.set(limit, forKey: Key.originalLimit)
    } else {
      defaults.removeObject(forKey: Key.originalLimit)
    }
    defaults.set(true, forKey: Key.originalRecorded)
  }
}
