import Foundation

// Runs a fixed system tool and returns its exit status and output. Blocks, so callers run it
// off the main thread.
enum Shell {
  struct Result: Sendable {
    var status: Int32
    var output: String
  }

  nonisolated static func run(_ path: String, _ arguments: [String]) -> Result? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
  }
}
