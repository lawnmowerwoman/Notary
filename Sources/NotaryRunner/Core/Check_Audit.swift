import Foundation

private let auditControlPath = "/etc/security/audit_control"
private let requiredAuditFlags = ["aa", "ad", "-ex", "-fm", "-fr", "-fw", "lo"]

private func auditControlContents() throws -> String {
    try String(contentsOfFile: auditControlPath, encoding: .utf8)
}

private func auditControlLine(prefix: String, in content: String) -> String? {
    content
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) })
}

private func auditLineTokens(_ line: String) -> [String] {
    guard let raw = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last else {
        return []
    }
    return raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
}

private func auditControlSummary(policy: [String], flags: [String]) -> String {
    "policy=\(policy.joined(separator: ",")); flags=\(flags.joined(separator: ","))"
}

private func rewriteAuditControlLine(prefix: String, replacement: String, in content: String) -> String {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var replaced = false
    let updated = lines.map { line -> String in
        if line.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
            replaced = true
            return replacement
        }
        return line
    }
    if replaced {
        return updated.joined(separator: "\n")
    }
    var appended = updated
    appended.append(replacement)
    return appended.joined(separator: "\n")
}

private func refreshAuditConfiguration(logger: HardenLogger) {
    if let refresh = try? Shell.run("/usr/sbin/audit", ["-s"], timeout: 10, logger: logger) {
        logger.info("[ENFORCE] audit -s code=\(refresh.code) out=\(refresh.stdout) err=\(refresh.stderr)")
    }
}

func checkAuditFailureHaltEnabled() -> CheckResult {
    do {
        let content = try auditControlContents()
        let policyLine = auditControlLine(prefix: "policy", in: content) ?? ""
        let tokens = auditLineTokens(policyLine)

        if tokens.contains("ahlt") {
            return .init(
                name: "Audit Failure Halt",
                status: .pass,
                details: "audit failure halt is enabled (\(policyLine.trimmingCharacters(in: .whitespacesAndNewlines)))."
            )
        }

        return .init(
            name: "Audit Failure Halt",
            status: .fail,
            details: "audit failure halt missing – \(policyLine.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    } catch {
        return .init(
            name: "Audit Failure Halt",
            status: .unknown,
            details: "Could not read \(auditControlPath): \(error)"
        )
    }
}

func enforceAuditFailureHaltEnabled(logger: HardenLogger) -> CheckResult {
    do {
        let content = try auditControlContents()
        let policyLine = auditControlLine(prefix: "policy", in: content) ?? "policy:"
        var tokens = auditLineTokens(policyLine)

        if !tokens.contains("ahlt") {
            tokens.append("ahlt")
        }

        let updated = rewriteAuditControlLine(
            prefix: "policy",
            replacement: "policy:\(tokens.joined(separator: ","))",
            in: content
        )
        try updated.write(toFile: auditControlPath, atomically: true, encoding: .utf8)
        refreshAuditConfiguration(logger: logger)
        return checkAuditFailureHaltEnabled()
    } catch {
        return .init(
            name: "Audit Failure Halt",
            status: .unknown,
            details: "Failed to update \(auditControlPath): \(error)"
        )
    }
}

func checkAuditFlagsCoreConfigured() -> CheckResult {
    do {
        let content = try auditControlContents()
        let flagsLine = auditControlLine(prefix: "flags", in: content) ?? ""
        let tokens = auditLineTokens(flagsLine)
        let missing = requiredAuditFlags.filter { !tokens.contains($0) }

        if missing.isEmpty {
            return .init(
                name: "Audit Core Flags",
                status: .pass,
                details: "required audit flags present (\(auditControlSummary(policy: [], flags: tokens)))."
            )
        }

        return .init(
            name: "Audit Core Flags",
            status: .fail,
            details: "missing audit flags: \(missing.joined(separator: ", ")) – current \(flagsLine.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    } catch {
        return .init(
            name: "Audit Core Flags",
            status: .unknown,
            details: "Could not read \(auditControlPath): \(error)"
        )
    }
}

func enforceAuditFlagsCoreConfigured(logger: HardenLogger) -> CheckResult {
    do {
        let content = try auditControlContents()
        let flagsLine = auditControlLine(prefix: "flags", in: content) ?? "flags:"
        var tokens = auditLineTokens(flagsLine)

        for flag in requiredAuditFlags where !tokens.contains(flag) {
            tokens.append(flag)
        }

        let updated = rewriteAuditControlLine(
            prefix: "flags",
            replacement: "flags:\(tokens.joined(separator: ","))",
            in: content
        )
        try updated.write(toFile: auditControlPath, atomically: true, encoding: .utf8)
        refreshAuditConfiguration(logger: logger)
        return checkAuditFlagsCoreConfigured()
    } catch {
        return .init(
            name: "Audit Core Flags",
            status: .unknown,
            details: "Failed to update \(auditControlPath): \(error)"
        )
    }
}

// MARK: 2.5.5 Diagnostic and usage reporting to Apple
func checkDiagnosticsReportingDisabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/com.apple.SubmitDiagInfo", "AutoSubmit"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value == "0" || value == "false" {
            return .init(
                name: "Diagnostics Reporting",
                status: .pass,
                details: "Diagnostic and usage reporting to Apple is disabled."
            )
        }

        return .init(
            name: "Diagnostics Reporting",
            status: .fail,
            details: "Diagnostic and usage reporting to Apple is enabled."
        )

    } catch {
        return .init(
            name: "Diagnostics Reporting",
            status: .unknown,
            details: "Could not read diagnostics reporting state."
        )
    }
}

func enforceDiagnosticsReportingDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        [
            "write",
            "/Library/Preferences/com.apple.SubmitDiagInfo",
            "AutoSubmit",
            "-bool",
            "false"
        ],
        timeout: 5,
        logger: logger
    )

    return checkDiagnosticsReportingDisabled()
}

// MARK: 3.1 Security auditing

func checkSecurityAuditingEnabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/bin/launchctl",
            ["print", "system/com.apple.auditd"],
            timeout: 10
        )

        let text = (r.stdout + r.stderr).lowercased()

        if text.contains("state = running") {
            return .init(
                name: "Security Auditing",
                status: .pass,
                details: "auditd is running."
            )
        }

        return .init(
            name: "Security Auditing",
            status: .fail,
            details: "auditd is not running."
        )

    } catch {
        return .init(
            name: "Security Auditing",
            status: .unknown,
            details: "launchctl auditd check failed: \(error)"
        )
    }
}

func enforceSecurityAuditingEnabled(logger: HardenLogger) -> CheckResult {

    _ = try? Shell.run(
        "/bin/launchctl",
        ["enable", "system/com.apple.auditd"],
        timeout: 10,
        logger: logger
    )

    _ = try? Shell.run(
        "/bin/launchctl",
        [
            "bootstrap",
            "system",
            "/System/Library/LaunchDaemons/com.apple.auditd.plist"
        ],
        timeout: 10,
        logger: logger
    )

    return checkSecurityAuditingEnabled()
}

// MARK: 3.3 Retain install.log for 365 days

private let installLogConfigPath = "/etc/asl/com.apple.install"
private let installLogPath = "/var/log/install.log"
private let desiredInstallLogRule = "* file /var/log/install.log format='$((Time)(JZ)) $Host $(Sender)[$(PID)]: $Message' rotate=utc compress file_max=50M size_only ttl=365"

func checkInstallLogRetentionConfigured() -> CheckResult {
    do {
        let content = try String(contentsOfFile: installLogConfigPath, encoding: .utf8)
        guard let ruleLine = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first(where: { $0.contains(installLogPath) }) else {
            return .init(
                name: "Install Log Retention",
                status: .fail,
                details: "No install.log rule found in \(installLogConfigPath)."
            )
        }

        if ruleLine.contains("all_max=") {
            return .init(
                name: "Install Log Retention",
                status: .fail,
                details: "install.log rule still uses all_max retention instead of ttl=365."
            )
        }

        let pattern = #"ttl=(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: ruleLine, range: NSRange(ruleLine.startIndex..., in: ruleLine)),
           let ttlRange = Range(match.range(at: 1), in: ruleLine),
           let ttl = Int(ruleLine[ttlRange]),
           ttl >= 365 {
            return .init(
                name: "Install Log Retention",
                status: .pass,
                details: "install.log retention is configured with ttl=\(ttl)."
            )
        }

        return .init(
            name: "Install Log Retention",
            status: .fail,
            details: "install.log retention is missing ttl=365 or higher."
        )
    } catch {
        return .init(
            name: "Install Log Retention",
            status: .unknown,
            details: "Could not read \(installLogConfigPath): \(error)"
        )
    }
}

func enforceInstallLogRetentionConfigured(logger: HardenLogger) -> CheckResult {
    do {
        let content = try String(contentsOfFile: installLogConfigPath, encoding: .utf8)
        guard content.contains(installLogPath) else {
            return .init(
                name: "Install Log Retention",
                status: .unknown,
                details: "No install.log rule found in \(installLogConfigPath)."
            )
        }

        let updatedLines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { line in
                line.contains(installLogPath) ? desiredInstallLogRule : line
            }
        let updatedContent = updatedLines.joined(separator: "\n")

        if updatedContent != content {
            try updatedContent.write(toFile: installLogConfigPath, atomically: true, encoding: .utf8)
            logger.info("[ENFORCE] Install Log Retention updated in \(installLogConfigPath)")
        } else {
            logger.info("[ENFORCE] Install Log Retention already set in \(installLogConfigPath)")
        }

        return checkInstallLogRetentionConfigured()
    } catch {
        return .init(
            name: "Install Log Retention",
            status: .unknown,
            details: "Failed to update \(installLogConfigPath): \(error)"
        )
    }
}

// MARK: 3.5 Audit log permissions - root only

func checkAuditLogPermissions() -> CheckResult {

    let path = "/var/audit"

    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)

        let owner = attrs[.ownerAccountName] as? String ?? ""
        let group = attrs[.groupOwnerAccountName] as? String ?? ""
        let perms = attrs[.posixPermissions] as? NSNumber

        if owner == "root",
           group == "wheel",
           perms?.intValue == 0o700 {

            return .init(
                name: "Audit Log Permissions",
                status: .pass,
                details: "/var/audit permissions are secure."
            )
        }

        return .init(
            name: "Audit Log Permissions",
            status: .fail,
            details: "Audit log permissions incorrect (owner=\(owner), group=\(group), mode=\(String(perms?.intValue ?? 0, radix:8)))."
        )

    } catch {
        return .init(
            name: "Audit Log Permissions",
            status: .unknown,
            details: "Could not read /var/audit attributes: \(error)"
        )
    }
}

func enforceAuditLogPermissions(logger: HardenLogger) -> CheckResult {

    _ = try? Shell.run(
        "/usr/sbin/chown",
        ["root:wheel", "/var/audit"],
        timeout: 5,
        logger: logger
    )

    _ = try? Shell.run(
        "/bin/chmod",
        ["700", "/var/audit"],
        timeout: 5,
        logger: logger
    )

    return checkAuditLogPermissions()
}
