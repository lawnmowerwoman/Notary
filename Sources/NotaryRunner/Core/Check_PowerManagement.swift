import Foundation

// MARK: - 2.8 Wake for Network Access

func checkWakeForNetworkAccessOff() -> CheckResult {
    checkSystemsetupOff(
        name: "Wake for Network Access",
        getArgument: "-getwakeonnetworkaccess"
    )
}

func enforceWakeForNetworkAccessOff(logger: HardenLogger) -> CheckResult {
    enforceSystemsetupOff(
        name: "Wake for Network Access",
        setArguments: ["-setwakeonnetworkaccess", "off"],
        logger: logger
    )
}

// MARK: - 2.9 Power Nap

func checkPowerNapOff() -> CheckResult {
    if HardwareInfo.isAppleSilicon() {
        return .init(
            name: "Power Nap",
            status: .skipped,
            details: "not applicable on Apple Silicon"
        )
    }

    do {
        let r = try Shell.run("/usr/bin/pmset", ["-g", "custom"], timeout: 10)
        let text = (r.stdout + r.stderr).lowercased()

        if text.contains("powernap") {
            let enabled = text
                .split(separator: "\n")
                .map(String.init)
                .first(where: { $0.lowercased().contains("powernap") })?
                .contains("1") ?? false

            return enabled
                ? .init(name: "Power Nap", status: .fail, details: "Power Nap is enabled.")
                : .init(name: "Power Nap", status: .pass, details: "Power Nap is disabled.")
        }

        return .init(name: "Power Nap", status: .unknown, details: "powernap setting not found in pmset output")
    } catch {
        return .init(name: "Power Nap", status: .unknown, details: "pmset error: \(error)")
    }
}

func enforcePowerNapOff(logger: HardenLogger) -> CheckResult {
    if HardwareInfo.isAppleSilicon() {
        return .init(
            name: "Power Nap",
            status: .skipped,
            details: "not applicable on Apple Silicon"
        )
    }

    do {
        let r = try Shell.run("/usr/bin/pmset", ["-a", "powernap", "0"], timeout: 15, logger: logger)

        if r.didTimeout {
            return .init(name: "Power Nap", status: .timedOut, details: "Power Nap enforce timed out")
        }

        if r.code != 0 {
            let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
            return .init(
                name: "Power Nap",
                status: .unknown,
                details: combined.isEmpty ? "Could not disable Power Nap." : combined
            )
        }

        return checkPowerNapOff()
    } catch {
        return .init(name: "Power Nap", status: .unknown, details: "Power Nap enforce error: \(error)")
    }
}
