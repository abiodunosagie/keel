import Foundation

// Runs a fixed system tool and returns its exit status and output. Blocks, so callers run it
// off the main thread. A tool still running after `timeout` seconds is stopped and counts as
// a failure.
enum Shell {
  struct Result: Sendable {
    var status: Int32
    var output: String
  }

  nonisolated static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 30) -> Result? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
      try process.run()
    } catch {
      return nil
    }
    // Read while waiting, so a large output can't fill the pipe and stall the tool.
    let output = Output()
    let readDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
      output.data = pipe.fileHandleForReading.readDataToEndOfFile()
      readDone.signal()
    }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      _ = finished.wait(timeout: .now() + 2)
      _ = readDone.wait(timeout: .now() + 2)
      return nil
    }
    readDone.wait()
    return Result(status: process.terminationStatus, output: String(decoding: output.data, as: UTF8.self))
  }

  // Written once by the reader before readDone is signalled, read only after the wait.
  private final class Output: @unchecked Sendable {
    var data = Data()
  }
}
