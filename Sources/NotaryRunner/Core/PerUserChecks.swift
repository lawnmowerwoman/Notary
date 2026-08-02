import Foundation

// Per-user checks use post-enforcement verification only.
// This keeps reports focused on remaining deviations instead of pre-fix findings.
func runPerUserWithPolicy(
    name: String,
    mode: PentaMode,
    logger: HardenLogger,
    users: [String],
    check: (_ user: String) -> CheckResult,
    enforce: ((_ user: String) -> Void)? = nil
) -> CheckResult {

    guard shouldRun(mode) else {
        // Per-user benchmarks follow the same Proof policy as global checks:
        // mode=off is configuration intent, not a runtime skip.
        return .init(name: name, status: .notConfigured, details: "not configured (mode=off)")
    }

    let sev = severity(for: mode)

    guard !users.isEmpty else {
        return .init(name: name, status: .skipped, details: "no local users found")
    }

    var failures: [String] = []
    var unknowns: [String] = []

    switch mode {
    case .check, .hardCheck:
        for user in users {
            let raw = check(user)
            let result = normalized(raw, mode: mode)

            switch result.status {
            case .pass, .skipped, .notConfigured:
                continue
            case .fail:
                failures.append("User \(user): \(result.details)")
            case .unknown:
                if mode == .hardCheck {
                    failures.append("User \(user): hard-check: unknown treated as fail – \(result.details)")
                } else {
                    unknowns.append("User \(user): \(result.details)")
                }
            case .cancelled:
                return .init(name: name, status: .cancelled, details: result.details)
            case .timedOut:
                failures.append("User \(user): \(result.details)")
            }
        }

    case .enforce, .hardEnforce:
        guard let enforce else {
            return .init(name: name, status: .fail, details: "enforce requested but not implemented", severity: sev)
        }

        logger.develop("[PERUSER] \(name): enforcing for \(users.count) users")

        for user in users {
            enforce(user)
        }

        for user in users {
            let raw = check(user)
            let result = normalized(raw, mode: mode)

            switch result.status {
            case .pass, .skipped, .notConfigured:
                continue
            case .fail:
                failures.append("User \(user): \(result.details)")
            case .unknown:
                if mode == .hardEnforce {
                    failures.append("User \(user): enforced but not verified – \(result.details)")
                } else {
                    unknowns.append("User \(user): \(result.details)")
                }
            case .cancelled:
                return .init(name: name, status: .cancelled, details: result.details)
            case .timedOut:
                failures.append("User \(user): \(result.details)")
            }
        }

    case .ignore:
        return .init(name: name, status: .notConfigured, details: "not configured (mode=off)")
    }

    if !failures.isEmpty {
        return .init(
            name: name,
            status: .fail,
            details: failures.joined(separator: "\n"),
            severity: sev
        )
    }

    if !unknowns.isEmpty {
        return .init(
            name: name,
            status: .unknown,
            details: unknowns.joined(separator: "\n"),
            severity: sev
        )
    }

    switch mode {
    case .enforce, .hardEnforce:
        return .init(name: name, status: .pass, details: "enforced + verified for all users", severity: sev)
    default:
        return .init(name: name, status: .pass, details: "compliant for all users", severity: sev)
    }
}

func runPerUserEnforceOnly(
    name: String,
    mode: PentaMode,
    logger: HardenLogger,
    users: [String],
    enforce: (_ user: String) -> CheckResult
) -> CheckResult {

    guard shouldRun(mode) else {
        // Keep disabled enforce-only checks out of the admin-facing skip count.
        return .init(name: name, status: .notConfigured, details: "not configured (mode=off)")
    }

    guard !users.isEmpty else {
        return .init(name: name, status: .skipped, details: "no local users found")
    }

    var failures: [String] = []
    var unknowns: [String] = []

    for user in users {
        let result = enforce(user)

        switch result.status {
        case .pass, .skipped, .notConfigured:
            continue
        case .fail:
            failures.append("User \(user): \(result.details)")
        case .unknown:
            unknowns.append("User \(user): \(result.details)")
        case .cancelled:
            return .init(name: name, status: .cancelled, details: result.details)
        case .timedOut:
            failures.append("User \(user): \(result.details)")
        }
    }

    if !failures.isEmpty {
        return .init(name: name, status: .fail, details: failures.joined(separator: "\n"))
    }

    if !unknowns.isEmpty {
        return .init(name: name, status: .unknown, details: unknowns.joined(separator: "\n"))
    }

    return .init(name: name, status: .pass, details: "enforced for all users")
}
