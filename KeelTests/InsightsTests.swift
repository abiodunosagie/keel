import XCTest
@testable import Keel

@MainActor
final class InsightsTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_790_000_000)
  private let charger = ChargerInfo(name: "87W USB-C Power Adapter", manufacturer: "Apple Inc.", watts: 86,
                                    volts: 20, amps: 4.29)

  private func plugged(percent: Int, charging: Bool, amperage: Double, powerIn: Double? = 80,
                       load: Double = 10, slow: Int = 0) -> BatterySnapshot {
    var snapshot = makeBattery(percent: percent, charging: charging, amperage: amperage)
    snapshot.charger = charger
    snapshot.powerIn = powerIn
    snapshot.systemLoad = load
    snapshot.slowChargingReason = slow
    return snapshot
  }

  func testLogsAChargingSessionWithEnergy() {
    let insights = PowerInsights(fileURL: nil)
    // 5 A at 12 V = 60 W for 5 minutes = 5 Wh.
    for second in stride(from: 0, through: 300, by: 5) {
      insights.update(plugged(percent: 50 + second / 60, charging: true, amperage: 5), drainExpected: false,
                      now: start.addingTimeInterval(Double(second)))
    }
    insights.update(plugged(percent: 55, charging: false, amperage: 0), drainExpected: false,
                    now: start.addingTimeInterval(305))
    XCTAssertEqual(insights.sessions.count, 1)
    XCTAssertEqual(insights.sessions[0].startPercent, 50)
    XCTAssertEqual(insights.sessions[0].endPercent, 55)
    XCTAssertEqual(insights.sessions[0].energyWh, 5, accuracy: 0.01)
    XCTAssertEqual(insights.sessions[0].chargerName, "87W USB-C Power Adapter")
  }

  func testShortBlipsAreNotSessions() {
    let insights = PowerInsights(fileURL: nil)
    insights.update(plugged(percent: 80, charging: true, amperage: 1), drainExpected: false, now: start)
    insights.update(plugged(percent: 80, charging: false, amperage: 0), drainExpected: false,
                    now: start.addingTimeInterval(30))
    XCTAssertTrue(insights.sessions.isEmpty)
  }

  func testRemembersChargersAndConnections() {
    let insights = PowerInsights(fileURL: nil)
    insights.update(plugged(percent: 50, charging: true, amperage: 2), drainExpected: false, now: start)
    insights.update(makeBattery(percent: 50, pluggedIn: false), drainExpected: false, now: start.addingTimeInterval(5))
    insights.update(plugged(percent: 50, charging: true, amperage: 2), drainExpected: false, now: start.addingTimeInterval(10))
    XCTAssertEqual(insights.chargers.count, 1)
    XCTAssertEqual(insights.chargers[0].connections, 2)
  }

  func testWeakChargerIsReportedAfterItPersists() {
    let insights = PowerInsights(fileURL: nil)
    var reported: [ChargerProblem] = []
    insights.onProblem = { reported.append($0) }
    // The load changes every reading, as it does on a real Mac.
    let loads = [45.0, 47.3, 44.1]
    for (step, load) in loads.enumerated() {
      insights.update(plugged(percent: 60, charging: false, amperage: -2, powerIn: 20, load: load),
                      drainExpected: false, now: start.addingTimeInterval(Double(step) * 5))
    }
    XCTAssertEqual(reported, [.tooWeak(chargerWatts: 86, loadWatts: 44.1)])
    XCTAssertEqual(insights.chargers[0].shortfalls, 1)
  }

  func testNoPowerFromAPluggedCharger() {
    XCTAssertEqual(PowerInsights.problem(in: plugged(percent: 60, charging: false, amperage: -1, powerIn: 0),
                                         drainExpected: false), .noPower)
  }

  func testIntendedDrainIsNotAProblem() {
    XCTAssertNil(PowerInsights.problem(in: plugged(percent: 90, charging: false, amperage: -2, powerIn: 0),
                                       drainExpected: true))
  }

  func testLoadSpikeIsIgnored() {
    let insights = PowerInsights(fileURL: nil)
    var reported: [ChargerProblem] = []
    insights.onProblem = { reported.append($0) }
    insights.update(plugged(percent: 60, charging: false, amperage: -2, powerIn: 20, load: 45), drainExpected: false, now: start)
    insights.update(plugged(percent: 60, charging: true, amperage: 1), drainExpected: false, now: start.addingTimeInterval(5))
    XCTAssertTrue(reported.isEmpty)
  }

  func testOneHealthRecordPerDay() {
    let insights = PowerInsights(fileURL: nil)
    insights.update(makeBattery(percent: 50), drainExpected: false, now: start)
    insights.update(makeBattery(percent: 50), drainExpected: false, now: start.addingTimeInterval(60))
    insights.update(makeBattery(percent: 50), drainExpected: false, now: start.addingTimeInterval(86_400))
    XCTAssertEqual(insights.health.count, 2)
  }

  func testForecastFollowsTheTrend() {
    // Health falls 0.1 points a day from 90%: 80% is 100 days after the first record.
    let records = (0..<30).map { day in
      HealthRecord(day: start.addingTimeInterval(Double(day) * 86_400),
                   fullChargeCapacity: Int((90 - 0.1 * Double(day)) * 60), designCapacity: 6000, cycles: day)
    }
    let forecast = PowerInsights.forecast(records)
    XCTAssertNotNil(forecast)
    XCTAssertEqual(forecast!.timeIntervalSince(start) / 86_400, 100, accuracy: 1)
  }

  func testNoForecastWithoutTwoWeeksOrWhenStable() {
    let short = (0..<5).map { HealthRecord(day: start.addingTimeInterval(Double($0) * 86_400),
                                          fullChargeCapacity: 5400 - $0 * 10, designCapacity: 6000, cycles: 0) }
    XCTAssertNil(PowerInsights.forecast(short))
    let stable = (0..<20).map { HealthRecord(day: start.addingTimeInterval(Double($0) * 86_400),
                                            fullChargeCapacity: 5400, designCapacity: 6000, cycles: 0) }
    XCTAssertNil(PowerInsights.forecast(stable))
  }

  func testCSVQuotesFields() {
    XCTAssertEqual(CSV.field("plain"), "plain")
    XCTAssertEqual(CSV.field("a, b"), "\"a, b\"")
    XCTAssertEqual(CSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
  }

  func testDrainSummaryNamesTheBigUsers() {
    var snapshot = makeBattery(percent: 60, pluggedIn: false, amperage: -1)
    snapshot.systemLoad = 20
    snapshot.displayWatts = 4
    let lines = DrainSummary.sentences(
      snapshot: snapshot, averageWatts: 10, chip: ChipPower(cpu: 3, gpu: 9, neuralEngine: 0),
      apps: [EnergyApp(name: "Xcode", impact: 40), EnergyApp(name: "Notes", impact: 1)]
    )
    XCTAssertEqual(lines, [
      "The Mac uses 20.0 W right now, more than its recent average of 10.0 W.",
      "The chip takes 12.0 W (60%), mostly the graphics.",
      "The screen backlight takes 4.0 W (20%). Lower brightness saves the most.",
      "Busiest apps: Xcode.",
    ])
  }

  func testChipPowerFromPowermetrics() {
    // Mirrors the helper's parser for both plist shapes.
    XCTAssertEqual(ChipPowerParsing.parse(["processor": ["cpu_power": 1500, "gpu_power": 250, "ane_power": 0]])?.cpu, 1.5)
    XCTAssertEqual(ChipPowerParsing.parse(["processor": ["cpu_energy": 750, "gpu_energy": 100]], intervalMilliseconds: 500)?.cpu, 1.5)
    XCTAssertNil(ChipPowerParsing.parse(["processor": [:]]))
  }
}
