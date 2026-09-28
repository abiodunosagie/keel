import Foundation
import IOKit
import IOKit.ps

// Reads the AppleSmartBattery registry entry (and the SMC for temperature). Reading is
// unprivileged. Keys verified on macOS 27.0: the capacities in mAh only appear inside
// "BatteryData", and the registry no longer carries a temperature.
enum BatteryReader {
  static func read() -> BatterySnapshot? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var unmanaged: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
      return nil
    }
    return snapshot(from: properties, temperature: smcTemperature(), adapterWatts: adapterWatts())
  }

  static func snapshot(from properties: [String: Any], temperature: Double?, adapterWatts: Int?) -> BatterySnapshot {
    let data = properties["BatteryData"] as? [String: Any] ?? [:]
    let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]

    func int(_ key: String, in source: [String: Any]) -> Int? {
      (source[key] as? NSNumber).map { Int(truncating: $0) }
    }
    // Signed registry values arrive as unsigned 64-bit numbers.
    func signed(_ key: String) -> Int {
      guard let number = properties[key] as? NSNumber else { return 0 }
      return Int(truncatingIfNeeded: number.uint64Value)
    }
    func minutes(_ key: String) -> Int? {
      guard let value = int(key, in: properties), value > 0, value < 65535 else { return nil }
      return value
    }

    let load = int("SystemLoad", in: telemetry).map { Double($0) / 1000 }
    return BatterySnapshot(
      macOSPercent: int("CurrentCapacity", in: properties) ?? 0,
      remainingCapacity: int("RemainingCapacity", in: data) ?? int("AppleRawCurrentCapacity", in: properties) ?? 0,
      fullChargeCapacity: int("FullChargeCapacity", in: data) ?? int("AppleRawMaxCapacity", in: properties) ?? 0,
      designCapacity: int("DesignCapacity", in: data) ?? int("DesignCapacity", in: properties) ?? 0,
      cycleCount: int("CycleCount", in: properties) ?? 0,
      isPluggedIn: properties["ExternalConnected"] as? Bool ?? false,
      isCharging: properties["IsCharging"] as? Bool ?? false,
      isFullyCharged: properties["FullyCharged"] as? Bool ?? false,
      voltage: Double(int("Voltage", in: properties) ?? 0) / 1000,
      amperage: Double(signed("Amperage")) / 1000,
      temperature: temperature,
      systemLoad: load.flatMap { $0 > 0 ? $0 : nil },
      adapterWatts: adapterWatts,
      minutesToEmpty: minutes("AvgTimeToEmpty"),
      minutesToFull: minutes("AvgTimeToFull")
    )
  }

  // TB0T is the battery temperature sensor in degrees Celsius.
  private static func smcTemperature() -> Double? {
    guard let value = KeelSMC.shared()?.float(forKey: "TB0T"), value.isFinite, value > 0, value < 100 else {
      return nil
    }
    return value
  }

  private static func adapterWatts() -> Int? {
    guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
          let watts = details[kIOPSPowerAdapterWattsKey] as? NSNumber,
          watts.intValue > 0 else {
      return nil
    }
    return watts.intValue
  }
}
