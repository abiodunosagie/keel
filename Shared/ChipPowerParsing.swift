import Foundation

// Reads CPU, GPU and Neural Engine watts from a powermetrics plist. Newer macOS reports
// *_power in milliwatts; older reports *_energy in millijoules over the sample interval.
enum ChipPowerParsing {
  nonisolated static func parse(
    _ root: [String: Any], intervalMilliseconds: Int = 500
  ) -> (cpu: Double, gpu: Double, ane: Double)? {
    let processor = root["processor"] as? [String: Any] ?? root
    func watts(_ name: String) -> Double? {
      if let power = processor["\(name)_power"] as? NSNumber { return power.doubleValue / 1000 }
      if let energy = processor["\(name)_energy"] as? NSNumber {
        return energy.doubleValue / Double(intervalMilliseconds)
      }
      return nil
    }
    guard let cpu = watts("cpu") else { return nil }
    return (cpu, watts("gpu") ?? 0, watts("ane") ?? 0)
  }
}
