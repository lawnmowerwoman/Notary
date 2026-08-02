import Foundation

package enum CheckStatus {
    case pass
    case fail
    case unknown
    case skipped
    // User-disabled benchmarks are not technical skips; keep them visible in logs
    // without inflating the Proof "skipped" count shown to admins.
    case notConfigured
    case cancelled
    case timedOut   // ✅ neu
}

package struct CheckResult {
    package let name: String
    package let status: CheckStatus
    package let details: String
    package let severity: Severity?

    init(name: String, status: CheckStatus, details: String, severity: Severity? = nil) {
        self.name = name
        self.status = status
        self.details = details
        self.severity = severity
    }
}

package struct CheckRun {
    package let spec: CheckSpec
    package let result: CheckResult
}

package enum CheckExecutionError: Error {
    case timeoutCascade(consecutive: Int, total: Int)
}


func isTCCBlockedMessage(_ text: String) -> Bool {
    text.lowercased().contains("requires full disk access")
}

func readPlistDict(at path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return obj as? [String: Any] ?? [:]
}



final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: Check Runtime

func runConfiguredChecks(
    rawSnapshot: [String: Any],
    config: ManagedConfig,
    logger: HardenLogger,
    caps: RunnerCapabilities
) throws -> [CheckRun] {
    let snapshotBox = UncheckedBox(rawSnapshot)
    var runs: [CheckRun] = []
    var consecutiveOuterTimeouts = 0
    var totalOuterTimeouts = 0
    let consecutiveOuterTimeoutLimit = 3
    let totalOuterTimeoutLimit = 6

    for spec in CheckRegistry.all() {
        if ShutdownCoordinator.shared.isShutdownRequested {
            throw ShutdownError.requested(reason: ShutdownCoordinator.shared.reason)
        }

        // Most checks already use Shell.run(...) with their own command-level timeout.
        // Give the outer guard additional headroom so it does not fire at the same
        // moment as the inner shell timeout and leave slow cleanup work behind.
        let effectiveTimeout = max(spec.timeoutSeconds + 5, spec.timeoutSeconds * 1.5)

        let r = runWithTimeout(
            name: spec.name,
            timeoutSeconds: effectiveTimeout,
            logger: logger
        ) {
            // Per-user checks manage their own policy flow internally:
            // - check only in check mode
            // - enforce first, then verify in enforce mode
            // Therefore they must NOT be wrapped by the normal spec.run path.
            if spec.section == "PerUser" {
                return spec.check(logger, config)
            }

            return spec.run(
                rawSnapshot: snapshotBox.value,
                config: config,
                logger: logger,
                caps: caps
            )
        }

        if r.status == .cancelled {
            throw ShutdownError.requested(reason: ShutdownCoordinator.shared.reason)
        }

        runs.append(CheckRun(spec: spec, result: r))

        if r.status == .timedOut {
            consecutiveOuterTimeouts += 1
            totalOuterTimeouts += 1

            if consecutiveOuterTimeouts >= consecutiveOuterTimeoutLimit || totalOuterTimeouts >= totalOuterTimeoutLimit {
                logger.error(
                    "[TIMEOUT] Aborting remaining checks after \(consecutiveOuterTimeouts) consecutive / \(totalOuterTimeouts) total outer timeouts; this cycle is likely stalled by unfinished background check work."
                )
                logRuns(runs, logger: logger)
                throw CheckExecutionError.timeoutCascade(consecutive: consecutiveOuterTimeouts, total: totalOuterTimeouts)
            }
        } else {
            consecutiveOuterTimeouts = 0
        }
    }

    return runs
}


func logRuns(_ runs: [CheckRun], logger: HardenLogger) {
    for run in runs {
        let r = run.result

        let statusTag: String
        switch r.status {
        case .pass:     statusTag = "[ OK ]"
        case .fail:     statusTag = "[FAIL]"
        case .skipped:  statusTag = "[SKIP]"
        case .notConfigured: statusTag = "[N/A ]"
        case .cancelled: statusTag = "[STOP]"
        case .timedOut: statusTag = "[TIME]"
        case .unknown:  statusTag = "[ ?? ]"
        }

        let idPart = run.spec.benchmarkID ?? "-"

        let sevPart: String
        if r.status == .fail, let sev = r.severity {
            sevPart = sev == .high ? " [HIGH]" : " [LOW]"
        } else {
            sevPart = ""
        }

        let line = "\(statusTag) \(idPart) \(r.name)\(sevPart) – \(r.details)"

        logger.check(line)
    }
}


func shouldRun(_ mode: PentaMode) -> Bool {
    switch mode {
    case .ignore:
        return false
    case .check, .hardCheck, .enforce, .hardEnforce:
        return true
    }
}

func normalized(_ r: CheckResult, mode: PentaMode) -> CheckResult {

    // ignore: nichts anfassen
    if mode == .ignore { return r }

    let sev = severity(for: mode)

    switch r.status {

    case .unknown:
        // unknown wird bei check/enforce zu FAIL
        return .init(
            name: r.name,
            status: .fail,
            details: "unknown treated as fail – \(r.details)",
            severity: sev
        )

    case .fail:
        // FAIL bekommt immer Severity entsprechend Mode
        return .init(
            name: r.name,
            status: .fail,
            details: r.details,
            severity: r.severity ?? sev
        )

    case .timedOut:
        // Timeout wird bei check/enforce zu FAIL
        return .init(
            name: r.name,
            status: .fail,
            details: "timeout treated as fail – \(r.details)",
            severity: sev
        )

    case .cancelled:
        return .init(
            name: r.name,
            status: .cancelled,
            details: r.details,
            severity: nil
        )

    case .pass:
        return r

    case .skipped:
        return r

    case .notConfigured:
        // Configuration intent is already final; normalization must not turn it
        // into a fail or a technical skip.
        return r
    }
}



// Thread-safe box to store the result of runWithTimeout
// @unchecked Sendable because we provide our own synchronization (NSLock).
private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    func set(_ v: T) {
        lock.lock()
        value = v
        lock.unlock()
    }

    func get() -> T? {
        lock.lock()
        let v = value
        lock.unlock()
        return v
    }
}

func runWithTimeout(
    name: String,
    timeoutSeconds: TimeInterval,
    logger: HardenLogger,
    operation: @Sendable @escaping () -> CheckResult
) -> CheckResult {

    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<CheckResult>()
    let pollInterval: TimeInterval = 0.2

    DispatchQueue.global(qos: .userInitiated).async {
        let result = operation()
        box.set(result)
        semaphore.signal()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while Date() < deadline {
        if ShutdownCoordinator.shared.isShutdownRequested {
            logger.warn("[SHUTDOWN] aborting check \(name)")
            return CheckResult(
                name: name,
                status: .cancelled,
                details: "cancelled due to \(ShutdownCoordinator.shared.reason)"
            )
        }

        let remaining = deadline.timeIntervalSinceNow
        let waitSlice = min(pollInterval, max(remaining, 0))
        if semaphore.wait(timeout: .now() + waitSlice) == .success {
            return box.get() ?? CheckResult(
                name: name,
                status: .unknown,
                details: "UNKNOWN – check finished but result was missing"
            )
        }
    }

    logger.error("[TIMEOUT] \(name) exceeded \(timeoutSeconds)s")
    return CheckResult(name: name, status: .timedOut, details: "TIMED OUT after \(Int(timeoutSeconds))s")
}



func runWithPolicy(
    name: String,
    mode: PentaMode,
    logger: HardenLogger,
    isAdmin: Bool,
    caps: RunnerCapabilities? = nil,
    check: () -> CheckResult,
    enforce: (() -> CheckResult)? = nil
) -> CheckResult {

    guard shouldRun(mode) else {
        return .init(name: name, status: .notConfigured, details: "not configured (mode=ignore)")
    }

    let sev = severity(for: mode)

    let checkedRaw = check()
    let checked = normalized(checkedRaw, mode: mode)

    switch mode {
    case .check:
        return checked

    case .hardCheck:
        if checked.status == .unknown {
            return .init(
                name: name,
                status: .fail,
                details: "hard-check: unknown treated as fail – \(checked.details)",
                severity: sev
            )
        }
        return checked

    case .enforce, .hardEnforce:
        if checked.status == .pass {
            return checked
        }

        if checked.status == .cancelled {
            return checked
        }

        guard let enforce else {
            return .init(
                name: name,
                status: .fail,
                details: "enforce requested but not implemented",
                severity: sev
            )
        }

        if !isAdmin {
            return .init(
                name: name,
                status: .fail,
                details: "enforce requires admin/root",
                severity: sev
            )
        }

        let enforcedRaw = enforce()
        let enforced = normalized(enforcedRaw, mode: mode)

        // Only verify if enforce itself actually succeeded
        if enforced.status != .pass {
            let details: String
            switch enforced.status {
            case .skipped:
                details = "enforce skipped – \(enforced.details)"
            case .notConfigured:
                details = "enforce not configured – \(enforced.details)"
            case .cancelled:
                details = enforced.details
            case .unknown:
                details = "enforce failed – \(enforced.details)"
            case .fail:
                details = "enforce failed – \(enforced.details)"
            case .timedOut:
                details = "enforce timed out – \(enforced.details)"
            case .pass:
                details = enforced.details
            }

            return .init(
                name: name,
                status: enforced.status == .cancelled ? .cancelled : .fail,
                details: details,
                severity: sev
            )
        }

        let postRaw = check()
        let post = normalized(postRaw, mode: mode)

        if post.status == .pass {
            return .init(
                name: name,
                status: .pass,
                details: "enforced + verified – \(post.details)",
                severity: sev
            )
        }

        return .init(
            name: name,
            status: .fail,
            details: "enforced but not verified (post=\(post.status)) – \(post.details)",
            severity: sev
        )

    case .ignore:
        return checked
    }
}
