import Foundation

// MARK: 5.10 Ensure system is set to hibernate

func checkHibernateMode() -> CheckResult {
    if HardwareInfo.isDesktopMac() {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .skipped,
            details: "not applicable on desktop Mac"
        )
    }

    guard let r = try? Shell.run("/usr/bin/pmset", ["-g"], timeout: 10) else {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .unknown,
            details: "pmset check failed."
        )
    }

    let text = (r.stdout + r.stderr).lowercased()
    let lines = text.split(separator: "\n").map(String.init)

    guard let line = lines.first(where: { $0.contains("hibernatemode") }) else {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .unknown,
            details: "hibernatemode not found."
        )
    }

    let parts = line.split(whereSeparator: \.isWhitespace)
    guard let last = parts.last else {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .unknown,
            details: "Could not parse hibernatemode."
        )
    }

    if last == "25" {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .pass,
            details: "hibernatemode is 25."
        )
    }

    return .init(
        name: "Force Hibernate on Sleep",
        status: .fail,
        details: "hibernatemode is \(last), expected 25."
    )
}

func enforceHibernateMode(logger: HardenLogger) -> CheckResult {

    if HardwareInfo.isDesktopMac() {
        return .init(
            name: "Force Hibernate on Sleep",
            status: .skipped,
            details: "not applicable on desktop Mac"
        )
    }

    _ = try? Shell.run(
        "/usr/bin/pmset",
        ["-a", "hibernatemode", "25"],
        timeout: 10,
        logger: logger
    )

    return checkHibernateMode()
}

// MARK: 5.10.1 Destroy FileVault Key on Sleep

func checkDestroyFVKeyOnStandby() -> CheckResult {
    guard let r = try? Shell.run("/usr/bin/pmset", ["-g"], timeout: 10) else {
        return .init(
            name: "Destroy FileVault Key on Standby",
            status: .unknown,
            details: "pmset check failed."
        )
    }

    let text = r.stdout + r.stderr
    let lines = text.split(separator: "\n").map(String.init)

    guard let line = lines.first(where: { $0.lowercased().contains("destroyfvkeyonstandby") }) else {
        return .init(
            name: "Destroy FileVault Key on Standby",
            status: .unknown,
            details: "destroyfvkeyonstandby setting not found."
        )
    }

    let parts = line.split(whereSeparator: \.isWhitespace)

    guard let last = parts.last else {
        return .init(
            name: "Destroy FileVault Key on Standby",
            status: .unknown,
            details: "Could not parse destroyfvkeyonstandby."
        )
    }

    if last == "1" {
        return .init(
            name: "Destroy FileVault Key on Standby",
            status: .pass,
            details: "destroyfvkeyonstandby is enabled."
        )
    }

    return .init(
        name: "Destroy FileVault Key on Standby",
        status: .fail,
        details: "destroyfvkeyonstandby is disabled."
    )
}

func enforceDestroyFVKeyOnStandby(logger: HardenLogger) -> CheckResult {

    _ = try? Shell.run(
        "/usr/bin/pmset",
        ["-a", "destroyfvkeyonstandby", "1"],
        timeout: 10,
        logger: logger
    )

    return checkDestroyFVKeyOnStandby()
}
