import Foundation
import Darwin

enum ShellError: Error, CustomStringConvertible {
    case nonZeroExit(code: Int32, stdout: String, stderr: String)

    var description: String {
        switch self {
        case .nonZeroExit(let code, let out, let err):
            return "exit=\(code)\nstdout=\(out)\nstderr=\(err)"
        }
    }
}

struct Shell {

    static func run(
        _ launchPath: String,
        _ args: [String],
        timeout: TimeInterval = 10,
        killGrace: TimeInterval = 2,
        logger: HardenLogger? = nil
    ) throws -> (stdout: String, stderr: String, code: Int32, didTimeout: Bool) {

        logger?.develop("[EXEC] \(describeCommand(launchPath, args)) (timeout=\(Int(timeout))s)")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        try p.run()

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            p.waitUntilExit()
            done.signal()
        }

        var didTimeout = false
        let pollInterval: TimeInterval = 0.2
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if done.wait(timeout: .now() + pollInterval) == .success {
                break
            }

            if ShutdownCoordinator.shared.isShutdownRequested {
                logger?.warn("[EXEC] cancelling \(describeCommand(launchPath, args)) due to \(ShutdownCoordinator.shared.reason)")
                if p.isRunning {
                    p.terminate()
                }
                if done.wait(timeout: .now() + killGrace) == .timedOut {
                    let pid = p.processIdentifier
                    if pid > 0 {
                        kill(pid, SIGKILL)
                    }
                    _ = done.wait(timeout: .now() + 1)
                }
                break
            }

            if Date() >= deadline {
                didTimeout = true
                p.terminate()

                // Grace period after terminate()
                if done.wait(timeout: .now() + killGrace) == .timedOut {
                    // Escalate: SIGKILL as last resort
                    let pid = p.processIdentifier
                    if pid > 0 {
                        kill(pid, SIGKILL)
                    }
                    _ = done.wait(timeout: .now() + 1)
                }
                break
            }
        }

        // Important: close write ends before reading to EOF (Process may have already exited, but safe)
        out.fileHandleForWriting.closeFile()
        err.fileHandleForWriting.closeFile()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()

        out.fileHandleForReading.closeFile()
        err.fileHandleForReading.closeFile()

        var stdout = String(data: outData, encoding: .utf8) ?? ""
        var stderr = String(data: errData, encoding: .utf8) ?? ""
        let code = p.terminationStatus

        stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        // Optional: annotate timeout without changing signature
        if didTimeout {
            if stderr.isEmpty {
                stderr = "TIMED OUT after \(Int(timeout))s"
            } else {
                stderr += "\nTIMED OUT after \(Int(timeout))s"
            }
        }

        return (stdout, stderr, code, didTimeout)
    }
}

/* Call format:
 let out = try Shell.runOrThrow(
     "/usr/bin/fdesetup",
     ["status"],
     timeout: 8
 )
 */
extension Shell {
    static func runOrThrow(
        _ launchPath: String,
        _ args: [String],
        timeout: TimeInterval = 10,
        killGrace: TimeInterval = 2
    ) throws -> (stdout: String, stderr: String) {

        let r = try run(launchPath, args, timeout: timeout, killGrace: killGrace)

        if r.didTimeout {
            throw ShellError.nonZeroExit(
                code: Int32(ETIMEDOUT),
                stdout: r.stdout,
                stderr: "timeout after \(Int(timeout))s"
            )
        }

        if r.code != 0 {
            throw ShellError.nonZeroExit(code: r.code, stdout: r.stdout, stderr: r.stderr)
        }

        return (r.stdout, r.stderr)
    }
}

extension Shell {
    static func runStdoutOrThrow(
        _ launchPath: String,
        _ args: [String],
        timeout: TimeInterval = 10,
        killGrace: TimeInterval = 2
    ) throws -> String {
        let r = try runOrThrow(launchPath, args, timeout: timeout, killGrace: killGrace)
        return r.stdout
    }
}

extension Shell {
    static func describeCommand(_ launchPath: String, _ args: [String]) -> String {
        let parts = [launchPath] + args
        return parts.map { shellQuote($0) }.joined(separator: " ")
    }

    private static func shellQuote(_ s: String) -> String {
        // Minimal robust: quote when needed, escape single quotes safely
        if s.isEmpty { return "''" }
        let needsQuotes = s.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" || $0 == "\\" || $0 == "$" || $0 == "`" })
        guard needsQuotes else { return s }

        // POSIX-safe single-quote escaping:  abc'def  -> 'abc'"'"'def'
        let escaped = s.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}


extension Shell {
    static func detailsForReport(
        command launchPath: String,
        args: [String],
        result: (stdout: String, stderr: String, code: Int32, didTimeout: Bool),
        timeout: TimeInterval
    ) -> String {
        let cmd = describeCommand(launchPath, args)

        if result.didTimeout {
            return "timeout (shell) after \(Int(timeout))s – \(cmd)"
        }

        // Prefer stdout; if empty, use stderr; if both empty, show exit code + cmd.
        let primary = !result.stdout.isEmpty ? result.stdout : result.stderr
        if !primary.isEmpty {
            return primary
        }

        return "exit=\(result.code) – \(cmd)"
    }

    static func failureDetailsForReport(
        command launchPath: String,
        args: [String],
        result: (stdout: String, stderr: String, code: Int32, didTimeout: Bool),
        timeout: TimeInterval
    ) -> String {
        // Same as above, but includes exit code when non-zero for easier debugging.
        let cmd = describeCommand(launchPath, args)

        if result.didTimeout {
            return "timeout (shell) after \(Int(timeout))s – \(cmd)"
        }

        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.code != 0 {
            // Keep it short but informative
            if !err.isEmpty {
                return "exit=\(result.code) – \(err) – \(cmd)"
            }
            if !out.isEmpty {
                return "exit=\(result.code) – \(out) – \(cmd)"
            }
            return "exit=\(result.code) – \(cmd)"
        }

        // code == 0 fallback
        if !out.isEmpty { return out }
        if !err.isEmpty { return err }
        return "ok – \(cmd)"
    }
}
