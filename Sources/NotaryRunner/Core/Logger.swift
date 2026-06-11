import Foundation
import os.log

enum LogLevel: String {
    case start = "START"
    case info = "INFO"
    case issue = "ISSUE"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"
    case debug = "DEBUG"
    case develop = "DEVELOP"
    case check = "CHECK"
}

package final class HardenLogger : @unchecked Sendable {

    private let mainURL: URL
    private let runURL: URL
    private let debugLevel: Int
    private let scriptName: String

    // Rotation
    private let maxBytes: Int
    private let maxFiles: Int

    // Unified Logging
    private let ulog: Logger

    private let echoToConsole: Bool
    private let isRoot: Bool

    package init(mainPath: String = "/var/log/notary/main.log",
         runPath: String = "/var/log/notary/run.log",
         debugLevel: Int = 0,
         scriptName: String = "notary",
         subsystem: String = "de.twocent.notary",
         category: String = "runner",
         echoToConsole: Bool = true,
         rotateMaxBytes: Int = 5 * 1024 * 1024,
         rotateMaxFiles: Int = 5) {

        self.isRoot = (geteuid() == 0)
        self.debugLevel = debugLevel
        self.scriptName = scriptName
        self.maxBytes = rotateMaxBytes
        self.maxFiles = rotateMaxFiles
        self.echoToConsole = echoToConsole
        self.ulog = Logger(subsystem: subsystem, category: category)

        // If not running as root, fall back to /tmp for development.
        let effectiveMainPath = self.isRoot ? mainPath : "/tmp/notary.main.log"
        let effectiveRunPath  = self.isRoot ? runPath  : "/tmp/notary.run.log"

        self.mainURL = URL(fileURLWithPath: effectiveMainPath)
        self.runURL  = URL(fileURLWithPath: effectiveRunPath)

        ensureDirectory(mainURL)
        ensureDirectory(runURL)

        // Ensure files exist; fix permissions only when root
        touchAndFixPermissions(mainURL)
        touchAndFixPermissions(runURL)

        if !self.isRoot {
            info("Not running as root – logging redirected to /tmp (dev mode) ✨")
        }
    }

    // MARK: - Public API

    package func start(_ message: String? = nil) {
        log(.start, message ?? "")
    }

    package func info(_ message: String) { log(.info, message) }
    package func check(_ message: String) { log(.check, message) }
    package func issue(_ message: String) { log(.issue, message) }
    package func warn(_ message: String) { log(.warn, message) }
    package func error(_ message: String) { log(.error, message) }

    package func debug(_ message: String) {
        guard debugLevel >= 1 else { return }
        log(.debug, message)
    }

    package func develop(_ message: String) {
        guard debugLevel >= 2 else { return }
        log(.develop, message)
    }

    package func fatal(_ code: Int = 1, _ message: String) -> Never {
        log(.fatal, "(\(code)) \(message)")
        Foundation.exit(Int32(code))
    }

    func log(_ level: LogLevel, _ message: String = "") {
        let ts = timestampString()

        // Unified log first (so you still get logs even if file IO fails)
        unified(level: level, message: message)

        switch level {

        case .start:
            let bar = String(repeating: "-", count: 80)
            write(line: bar, to: mainURL, rotate: true)

            let msg = message.isEmpty ? "Starting \(scriptName)" : message
            let mainLine = "\(ts) \(scriptName): \(msg)"
            let runLine  = "\(ts) \(msg)"

            echo(mainLine)
            write(line: mainLine, to: mainURL, rotate: true)
            write(line: runLine,  to: runURL,  rotate: true)

        case .fatal:
            let line = "\(ts) [FATAL] \(message)"
            echo(line, isError: true)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)

        case .warn:
            let line = "\(ts) [WARN] \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)

        case .error:
            let line = "\(ts) [ERROR] \(message)"
            echo(line, isError: true)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)

        case .issue:
            let line = "\(ts) [ISSUE] \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)

        case .debug:
            let line = "\(ts) [DEBUG] \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)

        case .develop:
            let line = "\(ts) [DEVELOP] \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)

        case .info:
            let line = "\(ts) [INFO] \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)

        case .check:
            let line = "\(ts) \(message)"
            echo(line)
            write(line: line, to: mainURL, rotate: true)
            write(line: line, to: runURL, rotate: true)
        }
    }

    // MARK: - Console echo

    private func echo(_ line: String, isError: Bool = false) {
        guard echoToConsole else { return }
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if isError {
            FileHandle.standardError.write(data)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }

    // MARK: - Unified logging

    private func unified(level: LogLevel, message: String) {
        switch level {
        case .fatal, .error:
            ulog.error("\(message, privacy: .public)")
        case .warn:
            ulog.warning("\(message, privacy: .public)")
        case .issue:
            ulog.notice("\(message, privacy: .public)")
        case .debug, .develop:
            ulog.debug("\(message, privacy: .public)")
        case .start, .info, .check:
            ulog.info("\(message, privacy: .public)")
        }
    }

    // MARK: - File IO + rotation + permissions

    private func write(line: String, to url: URL, rotate: Bool) {
        if rotate { rotateIfNeeded(url) }

        let text = line + "\n"
        guard let data = text.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let fh = try FileHandle(forWritingTo: url)
                try fh.seekToEnd()
                try fh.write(contentsOf: data)
                try fh.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // ignore; unified logging + console echo already got it
        }

        // keep permissions correct (esp. after rotation/creation)
        touchAndFixPermissions(url)
    }

    private func rotateIfNeeded(_ url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
            return
        }
        guard size >= maxBytes else { return }

        // Move .(maxFiles-1) -> .maxFiles, ... base -> .1
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let src = URL(fileURLWithPath: "\(url.path).\(i)")
            let dst = URL(fileURLWithPath: "\(url.path).\(i+1)")
            if FileManager.default.fileExists(atPath: src.path) {
                _ = try? FileManager.default.removeItem(at: dst)
                _ = try? FileManager.default.moveItem(at: src, to: dst)
            }
        }

        let first = URL(fileURLWithPath: "\(url.path).1")
        _ = try? FileManager.default.removeItem(at: first)
        _ = try? FileManager.default.moveItem(at: url, to: first)

        // Recreate empty base file
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    private func ensureDirectory(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // ignore
        }
    }

    private func touchAndFixPermissions(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        // Only root can/should enforce ownership/mode on /var/log
        guard isRoot else { return }

        // Set mode 0640
        chmod(url.path, 0o640)

        // Set owner root:wheel (0:0)
        chown(url.path, 0, 0)
    }

    private func timestampString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: Date())
    }
}
