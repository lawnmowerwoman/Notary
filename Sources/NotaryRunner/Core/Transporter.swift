import Foundation

package enum TransportTriggerReason: Equatable {
    case firstTransport
    case findingsChanged
    case percentChanged
    case connectionChanged
    case heartbeatDue
    case unchangedWithinHeartbeat

    package var logMessage: String {
        switch self {
        case .firstTransport:
            return "Transport update scheduled: first proof transport."
        case .findingsChanged:
            return "Transport update scheduled: proof changed."
        case .percentChanged:
            return "Transport update scheduled: compliance percent changed."
        case .connectionChanged:
            return "Transport update scheduled: connection telemetry changed."
        case .heartbeatDue:
            return "Transport update scheduled: heartbeat interval reached."
        case .unchangedWithinHeartbeat:
            return "Transport update skipped: no proof changes and heartbeat interval not yet reached."
        }
    }
}

package struct TransportDecision {
    package let shouldUpdate: Bool
    package let reason: TransportTriggerReason
}

package enum Transporter {
    private static func complianceState(for proof: NotaryProof) -> String {
        proof.compliant ? "PASSED" : "FAILED"
    }

    package static func decide(
        proof: NotaryProof,
        state: RunnerState,
        at now: Date,
        heartbeatInterval: TimeInterval,
        reportPercent: Bool,
        connectionValue: String? = nil
    ) -> TransportDecision {
        let resultsChanged =
            state.lastReportedRunnerBaseStatus != proof.baseStatus ||
            state.lastReportedIssuesValue != proof.issuesValue ||
            state.lastReportedComplianceState != complianceState(for: proof)

        if resultsChanged {
            return TransportDecision(shouldUpdate: true, reason: .findingsChanged)
        }

        if reportPercent, state.lastReportedCompliancePercentValue != proof.compliancePercentValue {
            return TransportDecision(shouldUpdate: true, reason: .percentChanged)
        }

        if let connectionValue, state.lastReportedConnectionValue != connectionValue {
            return TransportDecision(shouldUpdate: true, reason: .connectionChanged)
        }

        guard let lastTransportUpdateAt = state.lastTransportUpdateAt else {
            return TransportDecision(shouldUpdate: true, reason: .firstTransport)
        }

        if now.timeIntervalSince(lastTransportUpdateAt) >= heartbeatInterval {
            return TransportDecision(shouldUpdate: true, reason: .heartbeatDue)
        }

        return TransportDecision(shouldUpdate: false, reason: .unchangedWithinHeartbeat)
    }

    package static func applySuccessfulTransport(
        proof: NotaryProof,
        state: inout RunnerState,
        at date: Date,
        reportPercent: Bool,
        connectionValue: String? = nil
    ) {
        state.lastTransportUpdateAt = date
        state.lastReportedRunnerBaseStatus = proof.baseStatus
        state.lastReportedIssuesValue = proof.issuesValue
        state.lastReportedComplianceState = complianceState(for: proof)
        state.lastReportedComplianceValue = proof.complianceValue
        state.lastReportedCompliancePercentValue = reportPercent ? proof.compliancePercentValue : nil
        state.lastReportedConnectionValue = connectionValue
    }
}
