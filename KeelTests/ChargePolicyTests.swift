import XCTest
@testable import Keel

final class ChargePolicyTests: XCTestCase {
  private let range = 80...100

  private func battery(
    percent: Int,
    hardware: Double? = nil,
    pluggedIn: Bool = true,
    charging: Bool = false,
    amperage: Double = 0
  ) -> BatterySnapshot {
    let full = 5000
    let remaining = Int(((hardware ?? Double(percent)) / 100 * Double(full)).rounded())
    return BatterySnapshot(
      macOSPercent: percent, remainingCapacity: remaining, fullChargeCapacity: full, designCapacity: 6000,
      cycleCount: 10, isPluggedIn: pluggedIn, isCharging: charging, isFullyCharged: false, voltage: 12,
      amperage: amperage, temperature: 30, systemLoad: 10, adapterWatts: 96, minutesToEmpty: nil,
      minutesToFull: nil
    )
  }

  private func decide(
    _ snapshot: BatterySnapshot,
    _ settings: ChargeSettings = ChargeSettings(limit: 80),
    topUp: Bool = false,
    heatPaused: Bool = false
  ) -> ChargePolicy.Decision {
    ChargePolicy.decide(snapshot: snapshot, settings: settings, topUp: topUp, heatPaused: heatPaused,
                        limitRange: range)
  }

  func testChargesTowardTheLimit() {
    let decision = decide(battery(percent: 60, charging: true, amperage: 2))
    XCTAssertEqual(decision, .init(limit: 80, state: .charging))
  }

  func testHeldAtTheLimit() {
    XCTAssertEqual(decide(battery(percent: 80)), .init(limit: 80, state: .paused))
  }

  func testLimitOf100RemovesTheLimit() {
    XCTAssertEqual(decide(battery(percent: 60, charging: true), ChargeSettings(limit: 100)).limit, nil)
  }

  func testLimitIsClampedToWhatMacOSAccepts() {
    XCTAssertEqual(decide(battery(percent: 60), ChargeSettings(limit: 50)).limit, 80)
  }

  func testAutomaticDischargeRunsDownToTheLimit() {
    let decision = decide(battery(percent: 92, amperage: -1.5))
    XCTAssertEqual(decision, .init(limit: 80, state: .discharging))
  }

  func testWithoutAutomaticDischargeTheBatteryStaysWhereItIs() {
    let settings = ChargeSettings(limit: 80, automaticDischarge: false)
    XCTAssertEqual(decide(battery(percent: 92), settings), .init(limit: 92, state: .paused))
  }

  func testWithoutAutomaticDischargeBelowTheLimitStillCharges() {
    let settings = ChargeSettings(limit: 80, automaticDischarge: false)
    XCTAssertEqual(decide(battery(percent: 70, charging: true), settings).limit, 80)
  }

  func testTopUpRemovesTheLimit() {
    XCTAssertEqual(decide(battery(percent: 80, charging: true), topUp: true), .init(limit: nil, state: .topUp))
  }

  func testHeatPausesChargingAtTheCurrentLevel() {
    let settings = ChargeSettings(limit: 95)
    XCTAssertEqual(decide(battery(percent: 86), settings, heatPaused: true), .init(limit: 86, state: .heatProtect))
  }

  func testHeatPauseNeverRaisesTheLimit() {
    XCTAssertEqual(decide(battery(percent: 90), ChargeSettings(limit: 85), heatPaused: true).limit, 85)
  }

  func testHeatCannotPauseBelowEightyPercent() {
    // macOS has no limit under 80%, so the battery still charges to 80%.
    let decision = decide(battery(percent: 60, charging: true), ChargeSettings(limit: 95), heatPaused: true)
    XCTAssertEqual(decision, .init(limit: 95, state: .charging))
  }

  func testTopUpWinsOverHeat() {
    XCTAssertEqual(decide(battery(percent: 85, charging: true), topUp: true, heatPaused: true).limit, nil)
  }

  func testUnpluggedIsOnBattery() {
    XCTAssertEqual(decide(battery(percent: 50, pluggedIn: false, amperage: -1)).state, .onBattery)
  }

  func testChargingWellPastTheLimitIsMacOS() {
    XCTAssertEqual(decide(battery(percent: 95, charging: true)).state, .macOSOverride)
  }

  func testChargingOnePointPastTheLimitIsRounding() {
    XCTAssertEqual(decide(battery(percent: 80, charging: true)).state, .charging)
  }

  func testHardwarePercentShiftsTheLimitByTheGap() {
    // macOS shows 90 while the battery controller reads 87: a hardware limit of 90 means
    // stopping when macOS shows 93.
    let settings = ChargeSettings(limit: 90, useHardwarePercent: true)
    XCTAssertEqual(decide(battery(percent: 90, hardware: 87, charging: true), settings).limit, 93)
  }

  func testHardwareShiftStaysInRange() {
    let settings = ChargeSettings(limit: 98, useHardwarePercent: true)
    XCTAssertNil(decide(battery(percent: 90, hardware: 85), settings).limit)
  }
}

final class HeatGuardTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  func testPausesWhenTooHot() {
    var guardian = HeatGuard()
    guardian.update(temperature: 36, limit: 35, now: start)
    XCTAssertTrue(guardian.isPaused)
  }

  func testStaysPausedForFiveMinutesEvenWhenCool() {
    var guardian = HeatGuard()
    guardian.update(temperature: 36, limit: 35, now: start)
    guardian.update(temperature: 30, limit: 35, now: start.addingTimeInterval(299))
    XCTAssertTrue(guardian.isPaused)
    guardian.update(temperature: 30, limit: 35, now: start.addingTimeInterval(300))
    XCTAssertFalse(guardian.isPaused)
  }

  func testStillHotAfterFiveMinutesStartsAnotherPause() {
    var guardian = HeatGuard()
    guardian.update(temperature: 36, limit: 35, now: start)
    guardian.update(temperature: 37, limit: 35, now: start.addingTimeInterval(300))
    XCTAssertEqual(guardian.phase, .paused(since: start.addingTimeInterval(300)))
  }

  func testChargesAtLeastFiveMinutesAfterResuming() {
    var guardian = HeatGuard()
    guardian.update(temperature: 36, limit: 35, now: start)
    guardian.update(temperature: 30, limit: 35, now: start.addingTimeInterval(300))
    guardian.update(temperature: 38, limit: 35, now: start.addingTimeInterval(400))
    XCTAssertFalse(guardian.isPaused)
    guardian.update(temperature: 38, limit: 35, now: start.addingTimeInterval(600))
    XCTAssertTrue(guardian.isPaused)
  }

  func testMissingTemperatureNeverPauses() {
    var guardian = HeatGuard()
    guardian.update(temperature: nil, limit: 35, now: start)
    XCTAssertFalse(guardian.isPaused)
  }
}
