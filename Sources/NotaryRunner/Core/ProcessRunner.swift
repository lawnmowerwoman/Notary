import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

final class ProcessRunner {

    private let logger: HardenLogger

    init(logger: HardenLogger) {
        self.logger = logger
    }

    /// Runs a process and returns stdout/stderr and exit code.
    /// - Parameters:
    ///   - launchPath: Full path to executable (e.g. /bin/launchctl)
    ///   - args: Arguments array
    ///   - timeoutSeconds: Hard timeout; process will be terminated if exceeded
    @discardableResult
    func run(_ launchPath: String,
             _ args: [String],
             timeoutSeconds: TimeInterval = 30) -> ProcessResult {

        logger.develop("PROC: \(launchPath) \(args.joined(separator: " "))")

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
            logger.error("Failed to start process: \(launchPath) \(args.joined(separator: " ")) – \(error)")
            return .init(exitCode: 127, stdout: "", stderr: "\(error)")
        }

        // Wait with timeout (no busy loop)
        let timeoutResult = waitForExit(proc, timeoutSeconds: timeoutSeconds)
        if timeoutResult == false {
            proc.terminate()
            logger.error("Process timeout after \(Int(timeoutSeconds))s: \(launchPath) \(args.joined(separator: " "))")
            // read whatever output is available
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return .init(exitCode: 124, stdout: stdout, stderr: stderr.isEmpty ? "timeout" : stderr)
        }

        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return .init(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
    }

    // MARK: - Helpers

    private func waitForExit(_ process: Process, timeoutSeconds: TimeInterval) -> Bool {
        let group = DispatchGroup()
        group.enter()

        process.terminationHandler = { _ in
            group.leave()
        }

        // If the process already terminated very quickly, terminationHandler might not fire.
        if !process.isRunning {
            return true
        }

        let waitResult = group.wait(timeout: .now() + timeoutSeconds)
        return waitResult == .success
    }
}
