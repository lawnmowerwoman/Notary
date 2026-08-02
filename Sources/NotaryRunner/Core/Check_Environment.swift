import Foundation

private let defaultSecurityProductIndicators: [String] = [
    "JamfProtect",
    "Microsoft Defender",
    "CrowdStrike Falcon",
    "SentinelOne",
    "Sophos",
    "ESET",
    "Trellix",
    "Carbon Black",
    "Cylance"
]

func checkMDMEnrollment(logger: HardenLogger) -> CheckResult {
    do {
        let result = try Shell.run(
            "/usr/bin/profiles",
            ["status", "-type", "enrollment"],
            timeout: 10,
            logger: logger
        )

        let text = [result.stdout, result.stderr].joined(separator: "\n")
        let lower = text.lowercased()

        if lower.contains("mdm enrollment: yes") {
            let summary = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.lowercased().contains("mdm enrollment:") || $0.lowercased().contains("mdm server:") }
                .joined(separator: " | ")

            return .init(
                name: "MDM Enrollment",
                status: .pass,
                details: summary.isEmpty ? "device is enrolled in MDM." : summary
            )
        }

        if lower.contains("mdm enrollment: no") {
            return .init(
                name: "MDM Enrollment",
                status: .fail,
                details: "device is not enrolled in MDM."
            )
        }

        return .init(
            name: "MDM Enrollment",
            status: .unknown,
            details: "MDM enrollment state could not be determined."
        )
    } catch {
        return .init(
            name: "MDM Enrollment",
            status: .unknown,
            details: "profiles status error: \(error)"
        )
    }
}

func checkDirectoryServiceConfigured(logger: HardenLogger) -> CheckResult {
    do {
        let result = try Shell.run(
            "/usr/bin/dscl",
            ["/Search", "-read", "/", "CSPSearchPath"],
            timeout: 10,
            logger: logger
        )

        let entries = result.stdout
            .split(separator: "\n")
            .map { rawLine -> String in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("CSPSearchPath:") {
                    return line.replacingOccurrences(of: "CSPSearchPath:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return line
            }
            .filter { !$0.isEmpty }

        let remoteEntries = entries.filter {
            let lower = $0.lowercased()
            return lower != "/local/default" && lower != "/bsd/local"
        }

        if remoteEntries.isEmpty {
            return .init(
                name: "Directory Service",
                status: .fail,
                details: "only local directory nodes are configured (\(entries.joined(separator: ", ")))."
            )
        }

        return .init(
            name: "Directory Service",
            status: .pass,
            details: "directory search path includes \(remoteEntries.joined(separator: ", "))."
        )
    } catch {
        return .init(
            name: "Directory Service",
            status: .unknown,
            details: "directory service state could not be determined."
        )
    }
}

func checkSecurityAgentInstalled(expectedProducts: [String], logger: HardenLogger) -> CheckResult {
    let indicators = expectedProducts.isEmpty ? defaultSecurityProductIndicators : expectedProducts
    let normalizedIndicators = indicators.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    guard !normalizedIndicators.isEmpty else {
        return .init(
            name: "Security Agent",
            status: .unknown,
            details: "no security product indicators are configured."
        )
    }

    let snapshots = [
        shellText("/bin/ps", ["-axo", "comm"], timeout: 8, logger: logger),
        shellText("/usr/bin/systemextensionsctl", ["list"], timeout: 8, logger: logger),
        directoryListing("/Applications"),
        directoryListing("/Library/Application Support")
    ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .lowercased()

    let matches = normalizedIndicators.filter { indicator in
        snapshots.contains(indicator.lowercased())
    }

    if matches.isEmpty {
        return .init(
            name: "Security Agent",
            status: .fail,
            details: "none of the expected security products were detected (\(normalizedIndicators.joined(separator: ", ")))."
        )
    }

    return .init(
        name: "Security Agent",
        status: .pass,
        details: "detected security product(s): \(matches.joined(separator: ", "))."
    )
}

private func shellText(_ launchPath: String, _ args: [String], timeout: TimeInterval, logger: HardenLogger) -> String? {
    guard let result = try? Shell.run(launchPath, args, timeout: timeout, logger: logger) else {
        return nil
    }
    return [result.stdout, result.stderr].joined(separator: "\n")
}

private func directoryListing(_ path: String) -> String? {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
        return nil
    }
    return entries.joined(separator: "\n")
}
