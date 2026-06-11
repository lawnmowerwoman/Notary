import Foundation

struct LaunchDaemonAudit: Audit {
    let label: String
    let plistPath: String

    func check(process: ProcessRunner, logger: HardenLogger) -> AuditResult {
        var res = AuditResult()

        // File exists?
        let exists = FileManager.default.fileExists(atPath: plistPath)
        res.facts.append(.init(key: "launchdaemon.plist.exists.\(label)", value: exists ? "true" : "false"))

        if !exists {
            res.issues.append(.init(id: "LD_PLIST_MISSING", severity: .high,
                                    message: "LaunchDaemon plist missing: \(plistPath)"))
            return res
        }

        // launchctl status
        let r = process.run("/bin/launchctl", ["print", "system/\(label)"], timeoutSeconds: 10)
        if r.exitCode == 0 {
            res.facts.append(.init(key: "launchdaemon.loaded.\(label)", value: "true"))
        } else {
            res.facts.append(.init(key: "launchdaemon.loaded.\(label)", value: "false"))
            res.issues.append(.init(id: "LD_NOT_LOADED", severity: .low,
                                    message: "LaunchDaemon not loaded or not printable: \(label) (exit \(r.exitCode))."))
            logger.warn("launchctl print failed: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return res
    }

    func remediate(process: ProcessRunner, logger: HardenLogger) -> AuditResult {
        // Placeholder: in real use you’d load/reload daemon if policy requires.
        // Example only; typically you’ll deploy the plist via pkg/Jamf and then do:
        // launchctl bootout system/<label>
        // launchctl bootstrap system <plistPath>
        var res = AuditResult()
        logger.info("Remediation not implemented for \(label).")
        res.facts.append(.init(key: "remediation.\(label)", value: "skipped"))
        return res
    }
}
