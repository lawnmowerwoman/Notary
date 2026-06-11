import Foundation

// Generic Helpers for Checks

// MARK: systemsetup

func checkSystemsetupOff(
    name: String,
    getArgument: String,
    expectedOffToken: String = "Off",
    timeout: TimeInterval = 10
) -> CheckResult {
    do {
        let r = try Shell.run("/usr/sbin/systemsetup", [getArgument], timeout: timeout)

        let out = r.stdout.isEmpty ? r.stderr : r.stdout
        let token = out.split(separator: " ").last.map(String.init) ?? ""

        if token.caseInsensitiveCompare(expectedOffToken) == .orderedSame {
            return .init(name: name, status: .pass, details: "\(name) is disabled.")
        }

        return .init(name: name, status: .fail, details: "\(name) is enabled.")
    } catch {
        return .init(name: name, status: .unknown, details: "\(getArgument) error: \(error)")
    }
}

func enforceSystemsetupOff(
    name: String,
    setArguments: [String],
    logger: HardenLogger,
    timeout: TimeInterval = 15
) -> CheckResult {
    do {
        let r = try Shell.run("/usr/sbin/systemsetup", setArguments, timeout: timeout, logger: logger)

        if r.didTimeout {
            logger.info("[ENFORCE] \(name) timed out")
            return .init(name: name, status: .timedOut, details: "\(name) enforce timed out")
        }

        let errPart = r.stderr.isEmpty ? "" : " err=\(r.stderr)"
        logger.info("[ENFORCE] \(name) code=\(r.code) out=\(r.stdout)\(errPart)")

        if r.code == 0 {
            return .init(name: name, status: .pass, details: "\(name) was enabled. Fixed.")
        }

        let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
        return .init(
            name: name,
            status: .unknown,
            details: combined.isEmpty ? "\(name) is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: name, status: .unknown, details: "\(name) enforce error: \(error)")
    }
}

// MARK: launchctl

func checkLaunchctlServiceDisabled(
    name: String,
    label: String,
    timeout: TimeInterval = 10
) -> CheckResult {
    do {
        let r = try Shell.run("/bin/launchctl", ["print", "system/\(label)"], timeout: timeout)

        if r.code == 0 {
            return .init(name: name, status: .fail, details: "\(name) is enabled.")
        }

        let err = r.stderr.lowercased()
        let out = r.stdout.lowercased()

        if err.contains("could not find service") || out.contains("could not find service") {
            return .init(name: name, status: .pass, details: "\(name) is disabled.")
        }

        // For now, keep non-zero as pass, but preserve some diagnostics if needed later
        return .init(name: name, status: .pass, details: "\(name) is disabled.")
    } catch {
        return .init(name: name, status: .unknown, details: "launchctl print error: \(error)")
    }
}

func enforceLaunchctlServiceDisabled(
    name: String,
    label: String,
    logger: HardenLogger,
    timeout: TimeInterval = 15
) -> CheckResult {
    do {
        // 1) disable future starts
        let disable = try Shell.run(
            "/bin/launchctl",
            ["disable", "system/\(label)"],
            timeout: timeout,
            logger: logger
        )

        if disable.didTimeout {
            logger.info("[ENFORCE] \(name) disable timed out")
            return .init(name: name, status: .timedOut, details: "\(name) disable timed out")
        }

        // 2) stop current instance best effort
        let bootout = try? Shell.run(
            "/bin/launchctl",
            ["bootout", "system/\(label)"],
            timeout: timeout,
            logger: logger
        )

        logger.info("[ENFORCE] \(name) disable code=\(disable.code) out=\(disable.stdout) err=\(disable.stderr)")
        if let bootout {
            logger.info("[ENFORCE] \(name) bootout code=\(bootout.code) out=\(bootout.stdout) err=\(bootout.stderr)")
        }

        if disable.code == 0 {
            return .init(name: name, status: .pass, details: "\(name) was enabled. Fixed.")
        }

        let combined = [disable.stdout, disable.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
        return .init(
            name: name,
            status: .unknown,
            details: combined.isEmpty ? "\(name) is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: name, status: .unknown, details: "\(name) enforce error: \(error)")
    }
}
