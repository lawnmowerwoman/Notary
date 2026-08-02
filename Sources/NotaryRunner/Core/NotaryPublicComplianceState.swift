import Foundation

package enum NotaryPublicComplianceState: Sendable {
    case compliant
    case attention
    case nonCompliant
    case unavailable

    package init(report: NotaryPublicReport?) {
        guard let report else {
            self = .unavailable
            return
        }

        self = Self(complianceValue: report.complianceValue)
    }

    package init(complianceValue: String) {
        let normalized = complianceValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if normalized.hasPrefix("PASSED") || normalized == "COMPLIANT" {
            self = .compliant
        } else if normalized.hasPrefix("FAILED") || normalized == "NON-COMPLIANT" || normalized == "NONCOMPLIANT" {
            self = .nonCompliant
        } else if normalized.hasPrefix("ATTENTION") || normalized.hasPrefix("WARNING") || normalized.hasPrefix("WARN") {
            self = .attention
        } else {
            self = .unavailable
        }
    }

    package var displayTitle: String {
        switch self {
        case .compliant:
            return "Compliant"
        case .attention:
            return "Attention"
        case .nonCompliant:
            return "Non-Compliant"
        case .unavailable:
            return "Status Unavailable"
        }
    }
}

package extension NotaryPublicReport {
    var publicComplianceState: NotaryPublicComplianceState {
        NotaryPublicComplianceState(report: self)
    }
}
