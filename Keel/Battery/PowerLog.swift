import Foundation

// Reads the charge levels macOS writes to its power log at every sleep, wake and power change.
enum PowerLog {
  nonisolated static func read() -> [BatterySample] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "log"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return parse(String(decoding: data, as: UTF8.self))
  }

  // Lines look like:
  // 2026-09-27 08:06:13 +0100 Sleep  Entering ... Using Batt (Charge:41%)
  nonisolated static func parse(_ log: String) -> [BatterySample] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    var samples: [BatterySample] = []
    for line in log.split(separator: "\n") {
      guard line.count > 25,
            let date = formatter.date(from: String(line.prefix(25))),
            let using = line.range(of: "Using "),
            let charge = line.range(of: "(Charge:", range: using.upperBound..<line.endIndex) else {
        continue
      }
      let source = line[using.upperBound..<charge.lowerBound].trimmingCharacters(in: .whitespaces).uppercased()
      let digits = line[charge.upperBound...].prefix { $0.isNumber || $0 == " " }
      guard let percent = Int(digits.trimmingCharacters(in: .whitespaces)), (0...100).contains(percent) else {
        continue
      }
      samples.append(BatterySample(date: date, percent: percent, watts: nil, temperature: nil,
                                   pluggedIn: source == "AC"))
    }
    return samples
  }
}
