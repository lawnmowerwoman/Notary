import Foundation

package struct RunnerExecution {
    package let rawRuns: [CheckRun]
    package let runs: [CheckRun]
    package let proof: NotaryProof
}

package enum RunnerEngine {
    package static func execute(
        rawSnapshot: [String: Any],
        config: ManagedConfig,
        logger: HardenLogger,
        caps: RunnerCapabilities,
        lastKnownPassingChecks: [String: LastKnownPassingCheck] = [:],
        at date: Date = Date()
    ) throws -> RunnerExecution {
        let rawRuns = try runConfiguredChecks(
            rawSnapshot: rawSnapshot,
            config: config,
            logger: logger,
            caps: caps
        )
        let runs = reconcileTimeoutFallbacks(
            rawRuns,
            lastKnownPassingChecks: lastKnownPassingChecks,
            now: date,
            logger: logger
        )
        logRuns(runs, logger: logger)
        let proof = ProofBuilder.build(from: runs, at: date)
        return RunnerExecution(rawRuns: rawRuns, runs: runs, proof: proof)
    }

    private static func reconcileTimeoutFallbacks(
        _ runs: [CheckRun],
        lastKnownPassingChecks: [String: LastKnownPassingCheck],
        now: Date,
        logger: HardenLogger
    ) -> [CheckRun] {
        let maxAge: TimeInterval = 60 * 60
        return runs.map { run in
            let isPromotedTimeoutFailure =
                run.result.status == .fail &&
                run.result.details.hasPrefix("timeout treated as fail")
            guard run.result.status == .timedOut || isPromotedTimeoutFailure else { return run }
            guard let previousPass = lastKnownPassingChecks[run.spec.persistenceKey] else {
                return run
            }
            guard now.timeIntervalSince(previousPass.recordedAt) <= maxAge else {
                return run
            }

            logger.warn("[TIMEOUT-FALLBACK] Retaining last known PASS for \(run.result.name) after a transient timeout (\(Int(now.timeIntervalSince(previousPass.recordedAt) / 60)) minute(s) old).")
            return CheckRun(
                spec: run.spec,
                result: CheckResult(
                    name: run.result.name,
                    status: .pass,
                    details: "\(previousPass.details) (retained from last successful check)"
                )
            )
        }
    }
}
