import Foundation
@testable import Keel

// A battery reading for tests. `hardware` defaults to the macOS percentage.
func makeBattery(
  percent: Int,
  hardware: Double? = nil,
  pluggedIn: Bool = true,
  charging: Bool = false,
  amperage: Double = 0,
  temperature: Double? = 30
) -> BatterySnapshot {
  let full = 5000
  let remaining = Int(((hardware ?? Double(percent)) / 100 * Double(full)).rounded())
  return BatterySnapshot(
    macOSPercent: percent, remainingCapacity: remaining, fullChargeCapacity: full, designCapacity: 6000,
    cycleCount: 10, isPluggedIn: pluggedIn, isCharging: charging, isFullyCharged: false, voltage: 12,
    amperage: amperage, temperature: temperature, systemLoad: 10, adapterWatts: 96, minutesToEmpty: nil,
    minutesToFull: nil
  )
}
