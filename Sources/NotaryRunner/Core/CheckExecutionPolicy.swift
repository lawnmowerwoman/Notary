import Foundation

/// Scheduling metadata, independent of finding severity and remediation policy.
package enum CheckExecutionPriority: Int, CaseIterable, Sendable {
    case realtime = 0
    case configuredInterval = 1
    case everyTenMinutes = 2
    case hourly = 3
    case daily = 4
    case serviceStart = 5

    /// Nil means event-driven, configured, or process-lifetime scheduling.
    package var fixedIntervalSeconds: TimeInterval? {
        switch self {
        case .everyTenMinutes: return 10 * 60
        case .hourly: return 60 * 60
        case .daily: return 24 * 60 * 60
        case .realtime, .configuredInterval, .serviceStart: return nil
        }
    }
}

package enum CheckRetryCadence: Equatable, Sendable {
    case everySchedulerTick
    case interval(seconds: TimeInterval)
}

package struct CheckFailurePolicy: Equatable, Sendable {
    package let retryCadence: CheckRetryCadence
    package let previousResultRetentionSeconds: TimeInterval?

    package init(
        retryCadence: CheckRetryCadence = .everySchedulerTick,
        previousResultRetentionSeconds: TimeInterval? = nil
    ) {
        self.retryCadence = retryCadence
        self.previousResultRetentionSeconds = previousResultRetentionSeconds
    }
}

package struct CheckExecutionPolicy: Equatable, Sendable {
    package let priority: CheckExecutionPriority
    package let failure: CheckFailurePolicy

    package init(
        priority: CheckExecutionPriority = .configuredInterval,
        failure: CheckFailurePolicy = CheckFailurePolicy()
    ) {
        self.priority = priority
        self.failure = failure
    }

    package static let xprotect = CheckExecutionPolicy(
        priority: .hourly,
        failure: CheckFailurePolicy(
            retryCadence: .interval(seconds: 5 * 60),
            previousResultRetentionSeconds: 60 * 60
        )
    )
}

package enum CheckExecutionCatalog {
    package static func policyByKeyPath() -> [String: CheckExecutionPolicy] {
        Dictionary(uniqueKeysWithValues: CheckRegistry.all().map {
            ("\($0.section).\($0.key)", $0.executionPolicy)
        })
    }
}
