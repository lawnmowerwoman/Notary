import Foundation

// MARK: - 2.2.1 Time/NTP

/// Checks whether network time is enabled and (optionally) whether the configured NTP server and timezone match.
/// Intended to be called only when policy says we should run (mode != ignore).
///
/// - Parameters:
///   - usingNTPShouldBeOn: Usually `true` when SetTimeNTP/ForceTimeServer is enabled.
///   - expectedServer: Optional server name (e.g. "time.apple.com").
///   - expectedTimeZone: Optional IANA timezone (e.g. "Europe/Berlin").
/// - Returns: CheckResult with pass/fail/unknown.
func checkNetworkTime(
  usingNTPShouldBeOn: Bool = true,
  expectedServer: String?,
  expectedTimeZone: String?
) -> CheckResult {

    // Helper to normalize systemsetup output like:
    // "Network Time: On" or "Network Time: Off"
    func parseOnOff(_ s: String) -> Bool? {
        let l = s.lowercased()
        if l.contains(" on") || l.hasSuffix(": on") { return true }
        if l.contains(" off") || l.hasSuffix(": off") { return false }
        return nil
    }

    var details: [String] = []
    var mismatchFound = false

    // 1) Network time (NTP) on/off
    do {
        let r = try Shell.run("/usr/sbin/systemsetup", ["-getusingnetworktime"], timeout: 10)
        let onOff = parseOnOff(r.stdout) ?? parseOnOff(r.stderr)
        if let onOff {
            details.append("network time is \(onOff ? "ON" : "OFF")")
            if usingNTPShouldBeOn && !onOff { mismatchFound = true }
        } else {
            return .init(name: "Time/NTP", status: .unknown, details: r.stdout.isEmpty ? r.stderr : r.stdout)
        }
    } catch {
        return .init(name: "Time/NTP", status: .unknown, details: "systemsetup -getusingnetworktime error: \(error)")
    }

    // 2) Time server (best effort)
    if let expectedServer, !expectedServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        do {
            let r = try Shell.run("/usr/sbin/systemsetup", ["-getnetworktimeserver"], timeout: 10)
            // Example: "Network Time Server: time.apple.com"
            let server = r.stdout.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            if !server.isEmpty {
                details.append("server=\(server)")
                if server.caseInsensitiveCompare(expectedServer) != .orderedSame {
                    mismatchFound = true
                }
            } else {
                // Some systems may print to stderr; try that too
                let s2 = r.stderr.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                if !s2.isEmpty {
                    details.append("server=\(s2)")
                    if s2.caseInsensitiveCompare(expectedServer) != .orderedSame {
                        mismatchFound = true
                    }
                } else {
                    // If we can’t read it, mark unknown rather than fail (strictness can be policy-driven later)
                    return .init(name: "Time/NTP", status: .unknown, details: "Could not read network time server")
                }
            }
        } catch {
            return .init(name: "Time/NTP", status: .unknown, details: "systemsetup -getnetworktimeserver error: \(error)")
        }
    } else {
        // optional server check intentionally skipped
    }

    // 3) Time zone (best effort)
    if let expectedTimeZone, !expectedTimeZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        do {
            let r = try Shell.run("/usr/sbin/systemsetup", ["-gettimezone"], timeout: 10)
            // Example: "Time Zone: Europe/Berlin"
            let tz = r.stdout.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            if !tz.isEmpty {
                details.append("tz=\(tz)")
                if tz.caseInsensitiveCompare(expectedTimeZone) != .orderedSame {
                    mismatchFound = true
                }
            } else {
                let tz2 = r.stderr.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                if !tz2.isEmpty {
                    details.append("tz=\(tz2)")
                    if tz2.caseInsensitiveCompare(expectedTimeZone) != .orderedSame {
                        mismatchFound = true
                    }
                } else {
                    return .init(name: "Time/NTP", status: .unknown, details: "Could not read timezone")
                }
            }
        } catch {
            return .init(name: "Time/NTP", status: .unknown, details: "systemsetup -gettimezone error: \(error)")
        }
    } else {
        // optional timezone check intentionally skipped
    }

    if mismatchFound {
        return .init(name: "Time/NTP", status: .fail, details: details.joined(separator: " | "))
    }
    return .init(name: "Time/NTP", status: .pass, details: details.isEmpty ? "OK" : details.joined(separator: " | "))
}

/// Enforces network time ON and optionally sets NTP server and timezone.
/// Requires root/admin; will return FAIL if not root.
///
/// Notes:
/// - We keep time server/timezone optional:
///   - If expectedServer is nil => only ensure network time ON.
///   - If expectedTimeZone is nil => don’t change timezone.
func enforceTimeSettings(
  expectedServer: String?,
  expectedTimeZone: String?,
  logger: HardenLogger
) -> CheckResult {

    if geteuid() != 0 {
        return .init(name: "Time/NTP", status: .fail, details: "enforce requires admin/root")
    }

    func filteredSystemsetupStderr(_ s: String, exitCode: Int32) -> String {
        guard exitCode == 0 else { return s }
        let lines = s.split(separator: "\n").map(String.init)
        let cleaned = lines.filter { line in
            // Known benign noise on some macOS builds
            !line.contains("### Error:-99") &&
            !line.contains("/AppleInternal/Library/BuildRoots/")
        }
        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var steps: [String] = []

    // 1) Set NTP server (optional)
    if let expectedServer, !expectedServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        do {
            let r = try Shell.run("/usr/sbin/systemsetup", ["-setnetworktimeserver", expectedServer], timeout: 30)

            let errClean = filteredSystemsetupStderr(r.stderr, exitCode: r.code)
            let errPart = errClean.isEmpty ? "" : " err=\(errClean)"
            logger.info("[ENFORCE] TimeNTP set server code=\(r.code) out=\(r.stdout)\(errPart)")

            if r.code != 0 {
                let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
                return .init(name: "Time/NTP", status: .fail, details: combined.isEmpty ? "Failed to set NTP server (code \(r.code))" : combined)
            }
            steps.append("server=\(expectedServer)")
        } catch {
            return .init(name: "Time/NTP", status: .fail, details: "Failed to set NTP server: \(error)")
        }
    } else {
        logger.develop("[ENFORCE] TimeNTP server unchanged (no expected server configured)")
    }

    // 2) Set timezone (optional)
    if let expectedTimeZone, !expectedTimeZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        do {
            let r = try Shell.run("/usr/sbin/systemsetup", ["-settimezone", expectedTimeZone], timeout: 30)

            let errClean = filteredSystemsetupStderr(r.stderr, exitCode: r.code)
            let errPart = errClean.isEmpty ? "" : " err=\(errClean)"
            logger.info("[ENFORCE] TimeNTP set timezone code=\(r.code) out=\(r.stdout)\(errPart)")

            if r.code != 0 {
                let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
                return .init(name: "Time/NTP", status: .fail, details: combined.isEmpty ? "Failed to set timezone (code \(r.code))" : combined)
            }
            steps.append("tz=\(expectedTimeZone)")
        } catch {
            return .init(name: "Time/NTP", status: .fail, details: "Failed to set timezone: \(error)")
        }
    } else {
        logger.develop("[ENFORCE] TimeNTP timezone unchanged (no expected timezone configured)")
    }

    // 3) Enable network time
    do {
        let r = try Shell.run("/usr/sbin/systemsetup", ["-setusingnetworktime", "on"], timeout: 30)

        let errClean = filteredSystemsetupStderr(r.stderr, exitCode: r.code)
        let errPart = errClean.isEmpty ? "" : " err=\(errClean)"
        logger.info("[ENFORCE] TimeNTP enable network time code=\(r.code) out=\(r.stdout)\(errPart)")

        if r.code != 0 {
            let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
            return .init(name: "Time/NTP", status: .fail, details: combined.isEmpty ? "Failed to enable network time (code \(r.code))" : combined)
        }
        steps.append("network time=ON")
    } catch {
        return .init(name: "Time/NTP", status: .fail, details: "Failed to enable network time: \(error)")
    }

    // 4) Verify post-state
    let post = checkNetworkTime(usingNTPShouldBeOn: true, expectedServer: expectedServer, expectedTimeZone: expectedTimeZone)
    if post.status == .pass {
        let d = steps.isEmpty ? "enforced + verified" : "enforced + verified – \(steps.joined(separator: ", "))"
        return .init(name: "Time/NTP", status: .pass, details: d)
    }

    // If verification cannot be read, bubble up details but treat as fail (policy/normalizedStatus may adjust)
    return .init(name: "Time/NTP", status: .fail, details: "enforced but not verified (post=\(post.status)) – \(post.details)")
}
