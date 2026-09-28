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
    makeBattery(percent: percent, hardware: hardware, pluggedIn: pluggedIn, charging: charging, amperage: amperage)
  }

  private func decide(
    _ snapshot: BatterySnapshot,
    _ settings: ChargeSettings = ChargeSettings(limit: 80),
    topUp: Bool = false,
    mode: ChargeMode? = nil,
    heatPaused: Bool = false
  ) -> ChargePolicy.Decision {
    var offset = HardwareOffset()
    offset.update(macOS: snapshot.macOSPercent, hardware: snapshot.hardwarePercent)
    return ChargePolicy.decide(snapshot: snapshot, settings: settings, mode: mode ?? (topUp ? .topUp : .normal),
                               heatPaused: heatPaused, hardwareOffset: offset.value, limitRange: range)
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

  func testDischargeRunsDownEvenWithoutAutomaticDischarge() {
    let settings = ChargeSettings(limit: 80, automaticDischarge: false)
    XCTAssertEqual(decide(battery(percent: 92, amperage: -1.5), settings, mode: .discharge),
                   .init(limit: 80, state: .discharging))
  }

  func testTopUpUnpluggedIsOnBattery() {
    XCTAssertEqual(decide(battery(percent: 60, pluggedIn: false), topUp: true).state, .onBattery)
  }

  func testCalibrationDischargeCutsTheChargerWithNoLimit() {
    let decision = decide(battery(percent: 60), mode: .calibration(.dischargeLow))
    XCTAssertEqual(decision, .init(limit: nil, chargerConnected: false, state: .calibration))
  }

  func testCalibrationChargingStepsHaveNoLimitAndTheCharger() {
    for step in [CalibrationStep.chargeFull, .rechargeFull, .hold(until: .distantFuture)] {
      XCTAssertEqual(decide(battery(percent: 60), mode: .calibration(step)),
                     .init(limit: nil, chargerConnected: true, state: .calibration))
    }
  }

  func testCalibrationReturnsToTheLimit() {
    XCTAssertEqual(decide(battery(percent: 100), mode: .calibration(.returnToLimit)).limit, 80)
  }

  func testPauseHereWithHardwarePercentHoldsTheCurrentLevel() {
    // The reviewer's case: macOS 88, hardware 85.6. The paused limit must map back to 88.
    let snapshot = battery(percent: 88, hardware: 85.6)
    var settings = ChargeSettings(limit: 80, useHardwarePercent: true)
    var offset = HardwareOffset()
    offset.update(macOS: 88, hardware: snapshot.hardwarePercent)
    settings.limit = ChargePolicy.limitHoldingCurrentLevel(snapshot: snapshot, settings: settings,
                                                           hardwareOffset: offset.value, limitRange: range)
    XCTAssertEqual(decide(snapshot, settings).limit, 88)
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

final class HardwareOffsetTests: XCTestCase {
  func testIgnoresJitterAroundTheHalfPoint() {
    var offset = HardwareOffset()
    offset.update(macOS: 90, hardware: 87.6) // raw 2.4
    XCTAssertEqual(offset.value, 2)
    offset.update(macOS: 90, hardware: 87.45) // raw 2.55, would round to 3
    XCTAssertEqual(offset.value, 2)
    offset.update(macOS: 90, hardware: 87.1) // raw 2.9, clearly 3
    XCTAssertEqual(offset.value, 3)
  }
}

final class CalibrationTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  func testFullSequence() {
    XCTAssertEqual(Calibration.advance(.chargeFull, snapshot: makeBattery(percent: 100), target: 80, now: now),
                   .next(.dischargeLow))
    XCTAssertEqual(Calibration.advance(.dischargeLow, snapshot: makeBattery(percent: 11), target: 80, now: now), .stay)
    XCTAssertEqual(Calibration.advance(.dischargeLow, snapshot: makeBattery(percent: 10), target: 80, now: now),
                   .next(.rechargeFull))
    XCTAssertEqual(Calibration.advance(.rechargeFull, snapshot: makeBattery(percent: 100), target: 80, now: now),
                   .next(.hold(until: now.addingTimeInterval(Calibration.holdDuration))))
    let hold = CalibrationStep.hold(until: now.addingTimeInterval(60))
    XCTAssertEqual(Calibration.advance(hold, snapshot: makeBattery(percent: 100), target: 80, now: now), .stay)
    XCTAssertEqual(Calibration.advance(hold, snapshot: makeBattery(percent: 100), target: 80,
                                       now: now.addingTimeInterval(60)), .next(.returnToLimit))
    XCTAssertEqual(Calibration.advance(.returnToLimit, snapshot: makeBattery(percent: 90), target: 80, now: now), .stay)
    XCTAssertEqual(Calibration.advance(.returnToLimit, snapshot: makeBattery(percent: 80), target: 80, now: now),
                   .finished)
  }

  func testUnpluggingWhileChargingAborts() {
    XCTAssertEqual(Calibration.advance(.chargeFull, snapshot: makeBattery(percent: 50, pluggedIn: false),
                                       target: 80, now: now), .aborted)
  }

  func testUnpluggingDuringDischargeContinues() {
    XCTAssertEqual(Calibration.advance(.dischargeLow, snapshot: makeBattery(percent: 50, pluggedIn: false),
                                       target: 80, now: now), .stay)
  }
}
