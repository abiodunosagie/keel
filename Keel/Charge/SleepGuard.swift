import Foundation
import IOKit.pwr_mgt

// Keeps the Mac awake while Keel still has work to do on the charger.
@MainActor
final class SleepGuard {
  private var assertion: IOPMAssertionID = 0
  private var lidSleepDisabled = false

  // Stops idle sleep. On the charger this also keeps the Mac awake with the lid closed as long
  // as macOS allows it (verify on the owner's Mac for clamshell use).
  func set(awake: Bool) {
    if awake, assertion == 0 {
      var id: IOPMAssertionID = 0
      let reason = String(localized: "Keel is charging or discharging to your limit") as CFString
      if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
        assertion = id
      }
    } else if !awake, assertion != 0 {
      IOPMAssertionRelease(assertion)
      assertion = 0
    }
  }

  // Closing the lid sleeps the Mac even with the assertion, so calibration also turns sleep
  // off entirely through the helper, which undoes it when Keel quits.
  func setLidSleepDisabled(_ disabled: Bool, using charger: ChargerControl) {
    guard disabled != lidSleepDisabled else { return }
    lidSleepDisabled = disabled
    Task { _ = await charger.setSleepDisabled(disabled) }
  }
}
