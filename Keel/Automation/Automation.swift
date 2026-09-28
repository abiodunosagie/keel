import AppKit
import CoreLocation
import CoreWLAN
import EventKit
import Foundation
import IOKit
import Observation

// A charge limit for one Wi-Fi network, like "Office: 80%".
struct NetworkRule: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var network: String
  var limit: Int
}

struct AutomationSettings: Codable, Equatable, Sendable {
  var calendarTopUp = false
  // Words that mark an event as a long day away; matched in the title, case-insensitive.
  var calendarKeywords = String(localized: "flight, trip, travel, conference, offsite")
  var calendarLeadHours = 3
  var networkRules: [NetworkRule] = []
  var displayOffWhenIdle = true
  var displayIdleMinutes = 10
  var lockOnLidClose = true
}

// Calendar Top Up, Wi-Fi limits, display off while Keel keeps the Mac awake, and locking the
// screen when the lid closes. Checks every 30 seconds.
@MainActor
@Observable
final class Automation: NSObject, CLLocationManagerDelegate {
  static let checkInterval: TimeInterval = 30
  private static let settingsKey = "automation"
  private static let handledEventsKey = "calendarHandledEvents"

  var settings: AutomationSettings {
    didSet {
      guard settings != oldValue else { return }
      defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
      if settings.calendarTopUp, !oldValue.calendarTopUp { requestCalendarAccess() }
      if !settings.networkRules.isEmpty, oldValue.networkRules.isEmpty { requestLocationAccess() }
      check()
    }
  }

  private(set) var currentNetwork: String?
  private(set) var calendarAccess: Bool?
  private(set) var locationAccess: Bool?
  private(set) var nextTrip: (title: String, start: Date)?

  private let controller: ChargeController
  private let defaults: UserDefaults
  private let events = EKEventStore()
  private let location = CLLocationManager()
  private var timer: Timer?
  private var displayOffDoneForIdle = false
  private var lidWasClosed = false
  private var handledEvents: Set<String>

  init(controller: ChargeController, defaults: UserDefaults = .standard) {
    self.controller = controller
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.settingsKey),
       let saved = try? JSONDecoder().decode(AutomationSettings.self, from: data) {
      settings = saved
    } else {
      settings = AutomationSettings()
    }
    handledEvents = Set(defaults.stringArray(forKey: Self.handledEventsKey) ?? [])
    super.init()
    location.delegate = self
  }

  func start() {
    if settings.calendarTopUp { requestCalendarAccess() }
    if !settings.networkRules.isEmpty { requestLocationAccess() }
    check()
    timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
  }

  func check() {
    checkNetwork()
    checkCalendar()
    checkDisplayAndLid()
  }

  // MARK: Wi-Fi limits

  private func checkNetwork() {
    currentNetwork = CWWiFiClient.shared().interface()?.ssid()
    let rule = currentNetwork.flatMap { name in settings.networkRules.first { $0.network == name } }
    let wanted = rule.map { NetworkLimit(network: $0.network, limit: controller.limitRange.clamped($0.limit)) }
    if wanted != lastAppliedNetwork {
      // Only a change of network moves the limit, so a manual change sticks while on it.
      lastAppliedNetwork = wanted
      controller.networkLimit = wanted
    }
  }

  private var lastAppliedNetwork: NetworkLimit?

  private func requestLocationAccess() {
    switch location.authorizationStatus {
    case .notDetermined: location.requestWhenInUseAuthorization()
    default: updateLocationAccess()
    }
  }

  private func updateLocationAccess() {
    let status = location.authorizationStatus
    locationAccess = status == .authorizedAlways || status == .authorized
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      self.updateLocationAccess()
      self.check()
    }
  }

  // MARK: Calendar Top Up

  private func requestCalendarAccess() {
    Task {
      calendarAccess = (try? await events.requestFullAccessToEvents()) ?? false
      check()
    }
  }

  private func checkCalendar() {
    guard settings.calendarTopUp, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      nextTrip = nil
      return
    }
    let now = Date.now
    let horizon = now.addingTimeInterval(7 * 86_400)
    let predicate = events.predicateForEvents(withStart: now, end: horizon, calendars: nil)
    let keywords = Self.keywords(settings.calendarKeywords)
    let trips = events.events(matching: predicate)
      .filter { Self.matches($0.title ?? "", keywords: keywords) }
      .sorted { $0.startDate < $1.startDate }
    nextTrip = trips.first.map { ($0.title ?? String(localized: "Event"), $0.startDate) }
    guard let trip = trips.first, let id = trip.eventIdentifier, !handledEvents.contains(id) else { return }
    let lead = TimeInterval(settings.calendarLeadHours) * 3600
    guard trip.startDate.timeIntervalSince(now) <= lead, controller.snapshot?.isPluggedIn == true else { return }
    controller.startTopUp()
    handledEvents.insert(id)
    defaults.set(Array(handledEvents.suffix(200)), forKey: Self.handledEventsKey)
  }

  nonisolated static func keywords(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
  }

  nonisolated static func matches(_ title: String, keywords: [String]) -> Bool {
    let lowered = title.lowercased()
    return keywords.contains { lowered.contains($0) }
  }

  // MARK: Display and lid

  // Only while Keel itself keeps the Mac awake (calibration or keep-awake-until-limit): macOS's
  // own display sleep and lid behaviour apply otherwise.
  private func checkDisplayAndLid() {
    let keepingAwake = controller.calibrationStep != nil
      || (controller.options.keepAwakeUntilLimit && [.charging, .discharging].contains(controller.state))
    guard keepingAwake else {
      displayOffDoneForIdle = false
      lidWasClosed = Self.isLidClosed()
      return
    }
    if settings.displayOffWhenIdle {
      let idle = Self.idleSeconds()
      if idle >= Double(settings.displayIdleMinutes * 60), !displayOffDoneForIdle {
        displayOffDoneForIdle = true
        Task.detached(priority: .utility) { _ = Shell.run("/usr/bin/pmset", ["displaysleepnow"]) }
      } else if idle < Self.checkInterval {
        displayOffDoneForIdle = false
      }
    }
    let lidClosed = Self.isLidClosed()
    if settings.lockOnLidClose, lidClosed, !lidWasClosed {
      ScreenLock.lock()
    }
    lidWasClosed = lidClosed
  }

  // Seconds since the last keyboard or mouse input.
  static func idleSeconds() -> Double {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != IO_OBJECT_NULL else { return 0 }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)
    guard let nanoseconds = value?.takeRetainedValue() as? NSNumber else { return 0 }
    return nanoseconds.doubleValue / 1_000_000_000
  }

  static func isLidClosed() -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != IO_OBJECT_NULL else { return false }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? Bool) ?? false
  }
}

// Locks the screen the way the Lock Screen menu item does (login.framework, loaded at runtime).
enum ScreenLock {
  private typealias LockFunction = @convention(c) () -> Void

  static func lock() {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
          let symbol = dlsym(handle, "SACLockScreenImmediate") else {
      return
    }
    unsafeBitCast(symbol, to: LockFunction.self)()
  }
}
