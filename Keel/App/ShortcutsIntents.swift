import AppIntents
import Foundation

// Keel in the Shortcuts app, matching AlDente's list of actions.

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
  case unavailable
  case notPossible(String)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .unavailable: return "Keel can't control charging on this Mac."
    case .notPossible(let reason): return "\(reason)"
    }
  }
}

struct GetBatteryPercentageIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Battery Percentage"
  static let description = IntentDescription("The battery level Keel uses: the hardware percentage when that setting is on, otherwise the macOS one.")

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> {
    guard let percent = AppModel.shared.controller.displayPercent else { throw IntentError.unavailable }
    return .result(value: Int(percent.rounded()))
  }
}

struct GetChargeLimitIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Charge Limit"

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> {
    .result(value: AppModel.shared.controller.settings.limit)
  }
}

struct GetStateIntent: AppIntent {
  static let title: LocalizedStringResource = "Get State"
  static let description = IntentDescription("One of Charging, Pause, Discharging, Topup, HeatProtect, Calibration, OnBattery, MacOSOverride or Exit.")

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: AppModel.shared.controller.state.rawValue)
  }
}

struct GetTemperatureIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Battery Temperature"

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Double> {
    guard let temperature = AppModel.shared.controller.snapshot?.temperature else { throw IntentError.unavailable }
    return .result(value: (temperature * 10).rounded() / 10)
  }
}

struct SetChargeLimitIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Charge Limit"
  static let description = IntentDescription("Higher than the battery: it charges. Lower: charging stops (and with Automatic Discharge on, it runs down to the limit).")

  @Parameter(title: "Percent", inclusiveRange: (80, 100))
  var percent: Int

  @MainActor
  func perform() async throws -> some IntentResult {
    AppModel.shared.controller.setLimit(percent)
    return .result()
  }
}

struct PauseChargingIntent: AppIntent {
  static let title: LocalizedStringResource = "Pause Charging"
  static let description = IntentDescription("Sets the limit to the current level so the battery neither charges nor discharges.")

  @MainActor
  func perform() async throws -> some IntentResult {
    let controller = AppModel.shared.controller
    guard controller.canPauseHere else { throw IntentError.notPossible("macOS can't hold the battery below 80%.") }
    controller.pauseCharging()
    return .result()
  }
}

struct TopUpIntent: AppIntent {
  static let title: LocalizedStringResource = "Top Up"
  static let description = IntentDescription("Charges to 100% until the charger is unplugged once.")

  @MainActor
  func perform() async throws -> some IntentResult {
    let controller = AppModel.shared.controller
    guard controller.snapshot?.isPluggedIn == true else { throw IntentError.notPossible("Plug in the charger to top up.") }
    controller.startTopUp()
    return .result()
  }
}

struct StartDischargeIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Discharge"
  static let description = IntentDescription("Runs on battery down to the charge limit. The limit must be lower than the battery.")

  @MainActor
  func perform() async throws -> some IntentResult {
    let controller = AppModel.shared.controller
    guard controller.canDischarge else {
      throw IntentError.notPossible("Discharge needs the charger plugged in and the battery above the limit.")
    }
    controller.startDischarge()
    return .result()
  }
}

struct StartCalibrationIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Calibration Mode"

  @MainActor
  func perform() async throws -> some IntentResult {
    let controller = AppModel.shared.controller
    if let blocker = controller.calibrationBlocker { throw IntentError.notPossible(blocker) }
    controller.startCalibration()
    return .result()
  }
}

enum LightChoice: String, AppEnum {
  case keel, macOS

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe Light"
  static let caseDisplayRepresentations: [LightChoice: DisplayRepresentation] = [
    .keel: "Keel (green at limit, orange while charging)",
    .macOS: "macOS",
  ]
}

struct SetMagSafeLightIntent: AppIntent {
  static let title: LocalizedStringResource = "Set MagSafe Light"

  @Parameter(title: "Light")
  var light: LightChoice

  @MainActor
  func perform() async throws -> some IntentResult {
    guard AppModel.shared.helper.isReady else { throw IntentError.notPossible("Install Keel Helper first.") }
    AppModel.shared.controller.options.magSafeLight = light == .keel ? .auto : .system
    return .result()
  }
}

enum PowerModeChoice: String, AppEnum {
  case automatic, low, high

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Power Mode"
  static let caseDisplayRepresentations: [PowerModeChoice: DisplayRepresentation] = [
    .automatic: "Automatic", .low: "Low Power", .high: "High Power",
  ]

  var mode: PowerMode {
    switch self {
    case .automatic: return .automatic
    case .low: return .low
    case .high: return .high
    }
  }
}

struct SetPowerModeIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Power Mode"
  static let description = IntentDescription("Low Power, High Power or Automatic, like the macOS Battery settings.")

  @Parameter(title: "Mode")
  var mode: PowerModeChoice

  @MainActor
  func perform() async throws -> some IntentResult {
    let helper = AppModel.shared.helper
    guard helper.isReady else { throw IntentError.notPossible("Install Keel Helper first.") }
    guard await helper.setPowerMode(mode.mode) else { throw IntentError.notPossible("macOS didn't switch the power mode.") }
    return .result()
  }
}

struct KeelShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: TopUpIntent(), phrases: ["Top up with \(.applicationName)"],
                shortTitle: "Top Up", systemImageName: "bolt")
    AppShortcut(intent: PauseChargingIntent(), phrases: ["Pause charging with \(.applicationName)"],
                shortTitle: "Pause Charging", systemImageName: "pause")
    AppShortcut(intent: GetStateIntent(), phrases: ["Get the \(.applicationName) state"],
                shortTitle: "Get State", systemImageName: "battery.75percent")
  }
}
