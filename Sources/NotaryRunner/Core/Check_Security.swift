import Foundation

// MARK: 5.3 Reduce Sudo timeout period

private let sudoTimeoutPolicyPath = "/etc/sudoers.d/notary_sudo_timeout"
private let sudoHardeningPolicyPath = "/etc/sudoers.d/notary_sudo_hardening"

private func sudoVersionText(logger: HardenLogger? = nil) -> String? {
    let result = try? Shell.run(
        "/usr/bin/sudo",
        ["/usr/bin/sudo", "-V"],
        timeout: 8,
        logger: logger
    )
    guard let result else { return nil }
    return [result.stdout, result.stderr].joined(separator: "\n")
}

private func sudoersConfigurationText() -> String? {
    var chunks: [String] = []
    if let text = try? String(contentsOfFile: "/etc/sudoers") {
        chunks.append(text)
    }
    if let urls = try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: "/etc/sudoers.d", isDirectory: true),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) {
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let text = try? String(contentsOf: url) {
                chunks.append(text)
            }
        }
    }
    guard !chunks.isEmpty else { return nil }
    return chunks.joined(separator: "\n")
}

func checkSudoTimeout(expectedMinutes: Int) -> CheckResult {
    let path = sudoTimeoutPolicyPath

    guard FileManager.default.fileExists(atPath: path) else {
        return .init(
            name: "Sudo Timeout",
            status: .fail,
            details: "sudo timeout policy not configured."
        )
    }

    do {
        let content = try String(contentsOfFile: path)
        let pattern = #"timestamp_timeout\s*=\s*(-?\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .init(
                name: "Sudo Timeout",
                status: .unknown,
                details: "could not prepare sudo timeout parser."
            )
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        if let match = regex.firstMatch(in: content, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: content),
           let currentValue = Int(content[valueRange]) {
            if currentValue == expectedMinutes {
                return .init(
                    name: "Sudo Timeout",
                    status: .pass,
                    details: "sudo timeout is configured to \(currentValue) minute(s)."
                )
            }

            return .init(
                name: "Sudo Timeout",
                status: .fail,
                details: "sudo timeout is configured to \(currentValue) minute(s), expected \(expectedMinutes)."
            )
        }

        return .init(
            name: "Sudo Timeout",
            status: .fail,
            details: "sudo timeout policy invalid or timestamp_timeout is missing."
        )

    } catch {
        return .init(
            name: "Sudo Timeout",
            status: .unknown,
            details: "could not read sudo policy."
        )
    }
}

func enforceSudoTimeout(expectedMinutes: Int, logger: HardenLogger) -> CheckResult {
    let path = sudoTimeoutPolicyPath

    let policy = "Defaults timestamp_timeout=\(expectedMinutes)\n"

    try? policy.write(
        toFile: path,
        atomically: true,
        encoding: .utf8
    )

    _ = try? Shell.run(
        "/bin/chmod",
        ["440", path],
        timeout: 5,
        logger: logger
    )

    return checkSudoTimeout(expectedMinutes: expectedMinutes)
}

func checkSudoCommandLoggingEnabled(logger: HardenLogger) -> CheckResult {
    guard let text = sudoersConfigurationText() else {
        return .init(
            name: "Sudo Command Logging",
            status: .unknown,
            details: "Could not read sudoers configuration."
        )
    }

    if text.contains("Defaults !log_allowed") {
        return .init(
            name: "Sudo Command Logging",
            status: .fail,
            details: "sudo command logging is explicitly disabled."
        )
    }

    if text.contains("Defaults log_allowed") {
        return .init(
            name: "Sudo Command Logging",
            status: .pass,
            details: "sudo logs commands that are allowed by sudoers."
        )
    }

    return .init(
        name: "Sudo Command Logging",
        status: .fail,
        details: "sudo command logging is not configured."
    )
}

func enforceSudoCommandLoggingEnabled(logger: HardenLogger) -> CheckResult {
    let policy = "Defaults log_allowed\n"

    try? policy.write(
        toFile: sudoHardeningPolicyPath,
        atomically: true,
        encoding: .utf8
    )

    _ = try? Shell.run(
        "/bin/chmod",
        ["440", sudoHardeningPolicyPath],
        timeout: 5,
        logger: logger
    )

    return checkSudoCommandLoggingEnabled(logger: logger)
}

func checkSudoTimestampTypeTTY(logger: HardenLogger) -> CheckResult {
    guard let text = sudoVersionText(logger: logger) else {
        return .init(
            name: "Sudo Timestamp Type",
            status: .unknown,
            details: "Could not read sudo configuration summary."
        )
    }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if let line = lines.first(where: { $0.contains("Type of authentication timestamp record:") }) {
        let value = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if value == "tty" {
            return .init(
                name: "Sudo Timestamp Type",
                status: .pass,
                details: "sudo timestamp records are scoped per tty."
            )
        }
        return .init(
            name: "Sudo Timestamp Type",
            status: .fail,
            details: "sudo timestamp type is \(value), expected tty."
        )
    }

    return .init(
        name: "Sudo Timestamp Type",
        status: .unknown,
        details: "sudo timestamp type could not be determined."
    )
}

func enforceSudoTimestampTypeTTY(logger: HardenLogger) -> CheckResult {
    let existing = (try? String(contentsOfFile: sudoHardeningPolicyPath)) ?? ""
    let lines = existing
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("Defaults timestamp_type=") }

    var normalized = lines.filter { !$0.isEmpty }
    normalized.append("Defaults timestamp_type=tty")
    let policy = normalized.joined(separator: "\n") + "\n"

    try? policy.write(
        toFile: sudoHardeningPolicyPath,
        atomically: true,
        encoding: .utf8
    )

    _ = try? Shell.run(
        "/bin/chmod",
        ["440", sudoHardeningPolicyPath],
        timeout: 5,
        logger: logger
    )

    return checkSudoTimestampTypeTTY(logger: logger)
}

// MARK: 5.20 Library Validation / Mobile File Integrity

private let amfiBypassToken = "amfi_get_out_of_my_way=1"

func checkLibraryValidationEnabled() -> CheckResult {
    guard let result = try? Shell.run(
        "/usr/sbin/nvram",
        ["-p"],
        timeout: 10
    ) else {
        return .init(
            name: "Library Validation",
            status: .unknown,
            details: "Could not read NVRAM settings."
        )
    }

    let text = [result.stdout, result.stderr].joined(separator: "\n")
    if text.contains(amfiBypassToken) {
        return .init(
            name: "Library Validation",
            status: .fail,
            details: "AMFI bypass token \(amfiBypassToken) is present in NVRAM."
        )
    }

    return .init(
        name: "Library Validation",
        status: .pass,
        details: "No AMFI bypass token found in NVRAM."
    )
}

func enforceLibraryValidationEnabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/sbin/nvram",
        ["-d", "amfi_get_out_of_my_way"],
        timeout: 10,
        logger: logger
    )

    if let bootArgs = try? Shell.run(
        "/usr/sbin/nvram",
        ["boot-args"],
        timeout: 10,
        logger: logger
    ) {
        let combined = [bootArgs.stdout, bootArgs.stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if combined.contains("boot-args") {
            let value = combined
                .replacingOccurrences(of: #"^boot-args\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let updated = value
                .replacingOccurrences(of: amfiBypassToken, with: "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if updated != value {
                if updated.isEmpty {
                    _ = try? Shell.run(
                        "/usr/sbin/nvram",
                        ["-d", "boot-args"],
                        timeout: 10,
                        logger: logger
                    )
                } else {
                    _ = try? Shell.run(
                        "/usr/sbin/nvram",
                        ["boot-args=\(updated)"],
                        timeout: 10,
                        logger: logger
                    )
                }
            }
        }
    }

    return checkLibraryValidationEnabled()
}

// MARK: - 5.11 Admin password for system-wide preferences

// TODO: implement AuthorizationDB Helper
// readAuthorizationDB(rule:)
// writeAuthorizationDB(rule:plist:)
func checkAdminPasswordForPreferencesRequired() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/security",
            ["authorizationdb", "read", "system.preferences"],
            timeout: 10
        )

        let text = (r.stdout + r.stderr).lowercased()

        if text.contains("<key>shared</key>") && text.contains("<false/>") {
            return .init(
                name: "Admin Password for Preferences",
                status: .pass,
                details: "Administrator password is required for system-wide preferences."
            )
        }

        if text.contains("<key>shared</key>") && text.contains("<true/>") {
            return .init(
                name: "Admin Password for Preferences",
                status: .fail,
                details: "Administrator password is not required for system-wide preferences."
            )
        }

        return .init(
            name: "Admin Password for Preferences",
            status: .unknown,
            details: "Could not determine authorizationdb shared state for system.preferences."
        )
    } catch {
        return .init(
            name: "Admin Password for Preferences",
            status: .unknown,
            details: "security authorizationdb read failed: \(error)"
        )
    }
}

func enforceAdminPasswordForPreferencesRequired(logger: HardenLogger) -> CheckResult {
    let fm = FileManager.default
    let tempPath = "/tmp/notary.system.preferences.\(UUID().uuidString).plist"

    defer {
        try? fm.removeItem(atPath: tempPath)
    }

    do {
        let read = try Shell.run(
            "/usr/bin/security",
            ["authorizationdb", "read", "system.preferences"],
            timeout: 10,
            logger: logger
        )

        if read.didTimeout {
            return .init(
                name: "Admin Password for Preferences",
                status: .timedOut,
                details: "authorizationdb read timed out"
            )
        }

        if read.code != 0 || read.stdout.isEmpty {
            let combined = [read.stdout, read.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
            return .init(
                name: "Admin Password for Preferences",
                status: .unknown,
                details: combined.isEmpty ? "Failed to read authorizationdb for system.preferences." : combined
            )
        }

        try read.stdout.write(toFile: tempPath, atomically: true, encoding: .utf8)

        let set = try Shell.run(
            "/usr/libexec/PlistBuddy",
            ["-c", "Set :shared false", tempPath],
            timeout: 10,
            logger: logger
        )

        if set.didTimeout {
            return .init(
                name: "Admin Password for Preferences",
                status: .timedOut,
                details: "PlistBuddy update timed out"
            )
        }

        if set.code != 0 {
            let combined = [set.stdout, set.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
            return .init(
                name: "Admin Password for Preferences",
                status: .unknown,
                details: combined.isEmpty ? "Failed to set shared=false in authorization plist." : combined
            )
        }

        /*
         let write = try Shell.run(
            "/usr/bin/security",
            ["authorizationdb", "write", "system.preferences"],
            timeout: 10,
            logger: logger,
            stdin: try String(contentsOfFile: tempPath, encoding: .utf8)
        )
         */
        let write = try Shell.run(
            "/bin/sh",
            ["-c", "/usr/bin/security authorizationdb write system.preferences < '\(tempPath)'"],
            timeout: 10,
            logger: logger
        )

        if write.didTimeout {
            return .init(
                name: "Admin Password for Preferences",
                status: .timedOut,
                details: "authorizationdb write timed out"
            )
        }

        if write.code != 0 {
            let combined = [write.stdout, write.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
            return .init(
                name: "Admin Password for Preferences",
                status: .unknown,
                details: combined.isEmpty ? "Failed to write authorizationdb for system.preferences." : combined
            )
        }

        return checkAdminPasswordForPreferencesRequired()

    } catch {
        return .init(
            name: "Admin Password for Preferences",
            status: .unknown,
            details: "Enforce error: \(error)"
        )
    }
}
