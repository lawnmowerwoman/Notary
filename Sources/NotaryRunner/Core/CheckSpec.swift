import Foundation

struct ModeDecision {
    let mode: PentaMode
    let section: String
    let key: String
}


func modeFor(_ rawSnapshot: [String: Any], section: String, key: String) -> PentaMode {
    guard
        let sec = rawSnapshot[section] as? [String: Any]
    else { return .ignore }

    return toPentabool(sec[key])
}

func modeForAny(_ rawSnapshot: [String: Any], section: String, keys: [String]) -> PentaMode {
    guard let sec = rawSnapshot[section] as? [String: Any] else {
        return .ignore
    }

    for key in keys {
        if sec[key] != nil {
            return toPentabool(sec[key])
        }
    }

    return .ignore
}



package struct CheckSpec : @unchecked Sendable {
    package let name: String
    package let section: String
    package let key: String
    package let benchmarkID: String?

    /// Optional override for cases where "mode" isn't a PentaMode key in schema (e.g. ForceTimeServer Bool).
    let modeOverride: (([String: Any], ManagedConfig) -> PentaMode)?

    package let timeoutSeconds: TimeInterval  // ✅ neu

    let check: (HardenLogger, ManagedConfig) -> CheckResult
    let enforce: ((HardenLogger, ManagedConfig) -> CheckResult)?

    // ✅ Add a custom init with defaults
    init(
        name: String,
        section: String,
        key: String,
        benchmarkID: String? = nil,
        modeOverride: (([String: Any], ManagedConfig) -> PentaMode)? = nil,
        timeoutSeconds: TimeInterval = 16, // ✅ Default
        check: @escaping (HardenLogger, ManagedConfig) -> CheckResult,
        enforce: ((HardenLogger, ManagedConfig) -> CheckResult)? = nil
    ) {
        self.name = name
        self.section = section
        self.key = key
        self.benchmarkID = benchmarkID
        self.modeOverride = modeOverride
        self.timeoutSeconds = timeoutSeconds
        self.check = check
        self.enforce = enforce
    }

    package var persistenceKey: String {
        if let benchmarkID, !benchmarkID.isEmpty {
            return benchmarkID
        }
        return "\(section).\(key)"
    }

    package var issueValue: String {
        [benchmarkID, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func run(rawSnapshot: [String: Any], config: ManagedConfig, logger: HardenLogger, caps: RunnerCapabilities) -> CheckResult {
        let mode = modeOverride?(rawSnapshot, config) ?? modeFor(rawSnapshot, section: section, key: key)
        let isAdmin = (geteuid() == 0)

        // optional: Hinweis, falls Default genutzt wurde
        if timeoutSeconds == 16 {
            logger.develop("[CFG] \(name): using default timeout \(timeoutSeconds)s")
        }

        return runWithPolicy(
            name: name,
            mode: mode,
            logger: logger,
            isAdmin: isAdmin,
            caps: caps,
            check: { check(logger, config) },
            enforce: enforce.map { fn in { fn(logger, config) } }
        )
    }
}

package struct CheckIssueReference: Sendable {
    package let section: String
    package let key: String
    package let benchmarkID: String?
    package let name: String
    package let issueValue: String

    package var keyPath: String {
        "\(section).\(key)"
    }
}

package enum CheckIssueCatalog {
    package static func all() -> [CheckIssueReference] {
        CheckRegistry.all().map { spec in
            CheckIssueReference(
                section: spec.section,
                key: spec.key,
                benchmarkID: spec.benchmarkID,
                name: spec.name,
                issueValue: spec.issueValue
            )
        }
    }

    package static func referenceByKeyPath() -> [String: CheckIssueReference] {
        var result: [String: CheckIssueReference] = [:]
        for reference in all() {
            result[reference.keyPath] = reference
        }
        return result
    }

    package static func sectionByIssueValue() -> [String: String] {
        var result: [String: String] = [:]
        for reference in all() {
            result[reference.issueValue] = reference.section
        }
        return result
    }
}
