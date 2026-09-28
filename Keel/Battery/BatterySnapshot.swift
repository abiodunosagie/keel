import Foundation

// One reading of the battery and charger.
struct BatterySnapshot: Equatable, Sendable {
  // The percentage macOS shows in the menu bar.
  var macOSPercent: Int
  var remainingCapacity: Int // mAh
  var fullChargeCapacity: Int // mAh
  var designCapacity: Int // mAh
  var cycleCount: Int
  var isPluggedIn: Bool
  var isCharging: Bool
  var isFullyCharged: Bool
  var voltage: Double // volts
  var amperage: Double // amps, negative while the battery is discharging
  var temperature: Double? // degrees Celsius
  var systemLoad: Double? // watts drawn by the whole Mac
  var adapterWatts: Int?
  var minutesToEmpty: Int?
  var minutesToFull: Int?
  var charger: ChargerInfo? = nil
  // Watts coming in from the charger, after its own losses.
  var powerIn: Double? = nil
  // Non-zero when the battery controller refuses or slows charging (thermal, weak charger).
  var notChargingReason = 0
  var slowChargingReason = 0
  // Display backlight power (SMC PDBR), when the Mac reports it.
  var displayWatts: Double? = nil

  // The battery controller's own charge level, usually a few points below the macOS figure.
  var hardwarePercent: Double {
    guard fullChargeCapacity > 0 else { return Double(macOSPercent) }
    return min(100, Double(remainingCapacity) / Double(fullChargeCapacity) * 100)
  }

  var health: Double {
    guard designCapacity > 0 else { return 0 }
    return Double(fullChargeCapacity) / Double(designCapacity) * 100
  }

  // Watts flowing into (+) or out of (-) the battery.
  var batteryWatts: Double { voltage * amperage }

  func percent(useHardware: Bool) -> Double {
    useHardware ? hardwarePercent : Double(macOSPercent)
  }
}

// The connected power adapter, as the battery controller reports it.
struct ChargerInfo: Codable, Equatable, Hashable, Sendable {
  var name: String
  var manufacturer: String?
  var watts: Int
  var volts: Double?
  var amps: Double?
}
