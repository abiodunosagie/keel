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
  var temperatureAlert = true
  var temperatureAlertLimit: Double = 40
  var overLimitAlert = true
  var iconStyle: IconStyle = .mark
  var rightClick: RightClick = .menu
  var hideMenuBarIcon = false
  var showDockIcon = false
  var appearance: Appearance = .system
  var reduceTransparency = true

  enum IconStyle: String, Sendable, CaseIterable {
    case mark // the Keel mark: the level fills the ring up to the limit line
    case symbol // state symbols: plug, bolt, thermometer
    case battery // iPhone-style battery with the level inside
    case graph // a tiny charge graph of the last half hour
  }

  enum RightClick: String, Sendable, CaseIterable {
    case menu // a short menu of actions
    case dashboard
    case topUp
    case popover // same as a left click
  }

  enum Appearance: String, Sendable, CaseIterable {
    case system, light, dark
  }
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
    static let temperatureAlert = "temperatureAlert"
    static let temperatureAlertLimit = "temperatureAlertLimit"
    static let overLimitAlert = "overLimitAlert"
    static let iconStyle = "iconStyle"
    static let rightClick = "rightClick"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let appearance = "appearance"
    static let reduceTransparency = "reduceTransparency"
    static let popoverLayout = "popoverLayout"
    static let lastSeenVersion = "lastSeenVersion"
    static let onboarded = "onboarded"
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
      menuBarTemperature: value(Key.menuBarTemperature) ?? base.menuBarTemperature,
      temperatureAlert: value(Key.temperatureAlert) ?? base.temperatureAlert,
      temperatureAlertLimit: value(Key.temperatureAlertLimit) ?? base.temperatureAlertLimit,
      overLimitAlert: value(Key.overLimitAlert) ?? base.overLimitAlert,
      iconStyle: (value(Key.iconStyle) as String?).flatMap(AppOptions.IconStyle.init) ?? base.iconStyle,
      rightClick: (value(Key.rightClick) as String?).flatMap(AppOptions.RightClick.init) ?? base.rightClick,
      hideMenuBarIcon: value(Key.hideMenuBarIcon) ?? base.hideMenuBarIcon,
      showDockIcon: value(Key.showDockIcon) ?? base.showDockIcon,
      appearance: (value(Key.appearance) as String?).flatMap(AppOptions.Appearance.init) ?? base.appearance,
      reduceTransparency: value(Key.reduceTransparency) ?? base.reduceTransparency
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
    defaults.set(options.temperatureAlert, forKey: Key.temperatureAlert)
    defaults.set(options.temperatureAlertLimit, forKey: Key.temperatureAlertLimit)
    defaults.set(options.overLimitAlert, forKey: Key.overLimitAlert)
    defaults.set(options.iconStyle.rawValue, forKey: Key.iconStyle)
    defaults.set(options.rightClick.rawValue, forKey: Key.rightClick)
    defaults.set(options.hideMenuBarIcon, forKey: Key.hideMenuBarIcon)
    defaults.set(options.showDockIcon, forKey: Key.showDockIcon)
    defaults.set(options.appearance.rawValue, forKey: Key.appearance)
    defaults.set(options.reduceTransparency, forKey: Key.reduceTransparency)
  }

  var lastCalibration: Date? {
    get { value(Key.lastCalibration) }
    nonmutating set { defaults.set(newValue, forKey: Key.lastCalibration) }
  }

  var popoverLayout: PopoverLayout {
    get {
      guard let data = defaults.data(forKey: Key.popoverLayout),
            let layout = try? JSONDecoder().decode(PopoverLayout.self, from: data) else { return PopoverLayout() }
      return layout.normalized()
    }
    nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.popoverLayout) }
  }

  // The version whose What's New the owner has seen; nil on a first install.
  var lastSeenVersion: String? {
    get { value(Key.lastSeenVersion) }
    nonmutating set { defaults.set(newValue, forKey: Key.lastSeenVersion) }
  }

  var hasOnboarded: Bool {
    get { defaults.bool(forKey: Key.onboarded) }
    nonmutating set { defaults.set(newValue, forKey: Key.onboarded) }
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
