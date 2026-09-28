import Foundation

enum HelperIdentity {
  static let label = "com.abiodunosagie.Keel.Helper"
  static let plistName = "\(label).plist"
  static let appIdentifier = "com.abiodunosagie.Keel"
  static let teamIdentifier = "R87873B42W"
  // Bumped whenever the helper's behaviour changes, so the app can re-register a stale copy.
  static let version = 2

  // Only a Keel build signed by this team may talk to the helper, and the app only talks to
  // a helper signed by the same team.
  static let clientRequirement = requirement(for: appIdentifier)
  static let helperRequirement = requirement(for: label)

  private static func requirement(for identifier: String) -> String {
    "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}

// MagSafe light colours the helper may set (SMC key ACLC). System hands the light back to macOS.
@objc enum MagSafeLight: Int {
  case system = 0
  case green = 3
  case orange = 4
}

// What the privileged helper does for the app. Each call does one fixed thing; the app never
// passes raw SMC keys or bytes.
@objc protocol HelperProtocol {
  func version(reply: @escaping (Int) -> Void)
  // Connects or disconnects the charger inside the Mac (SMC key CHIE). Disconnected, the Mac
  // runs from its battery while plugged in. The helper reconnects it when the app goes away,
  // when the helper starts or stops, and when the battery falls to its safety floor.
  func setChargerConnected(_ connected: Bool, reply: @escaping (Bool, String?) -> Void)
  func isChargerConnected(reply: @escaping (Bool) -> Void)
  func setMagSafeLight(_ light: MagSafeLight, reply: @escaping (Bool) -> Void)
  // Keeps the Mac awake with the lid closed (pmset disablesleep), for calibration. Undone when
  // the app goes away or the helper stops.
  func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)
  func setPowerMode(_ mode: PowerMode, reply: @escaping (Bool) -> Void)
  // Restores everything and exits so launchd starts the helper from the updated Keel.app on
  // the next connection. Updates need no new approval this way.
  func exitForUpdate(reply: @escaping () -> Void)
}

// macOS energy modes (pmset powermode). High Power only exists on some MacBook Pro models.
@objc enum PowerMode: Int, CaseIterable {
  case automatic = 0
  case low = 1
  case high = 2
}
