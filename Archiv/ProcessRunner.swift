import Foundation
import os.log

final class Log {
  private let logger = Logger(subsystem: "de.steffi.hardening", category: "runner")
  private let sinkURL: URL?

  init(sinkPath: String?) {
    if let sinkPath {
      self.sinkURL = URL(fileURLWithPath: sinkPath)
    } else {
      self.sinkURL = nil
    }
  }

  func info(_ msg: String) {
    logger.info("\(msg, privacy: .public)")
    writeToFile("[INFO] \(msg)")
  }

  func warn(_ msg: String) {
    logger.warning("\(msg, privacy: .public)")
    writeToFile("[WARN] \(msg)")
  }

  func error(_ msg: String) {
    logger.error("\(msg, privacy: .public)")
    writeToFile("[ERR ] \(msg)")
  }

  private func writeToFile(_ line: String) {
    guard let url = sinkURL else { return }
    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    if let data = stamped.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: url.path) {
        if let fh = try? FileHandle(forWritingTo: url) {
          _ = try? fh.seekToEnd()
          try? fh.write(contentsOf: data)
          try? fh.close()
        }
      } else {
        try? data.write(to: url, options: .atomic)
      }
    }
  }
}

struct ProcessResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

final class ProcessRunner {
  private let log: Log
  init(log: Log) { self.log = log }

  @discardableResult
  func run(_ launchPath: String, _ args: [String], timeoutSeconds: TimeInterval = 30) -> ProcessResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args

    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err

    do {
      try proc.run()
    } catch {
      log.error("Failed to start process: \(launchPath) \(args.joined(separator: " ")) – \(error)")
      return .init(exitCode: 127, stdout: "", stderr: "\(error)")
    }

    // crude timeout: terminate if still running
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while proc.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if proc.isRunning {
      proc.terminate()
      log.error("Process timeout: \(launchPath) \(args.joined(separator: " "))")
      return .init(exitCode: 124, stdout: "", stderr: "timeout")
    }

    let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
    let stderrData = err.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

    return .init(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
  }
}
