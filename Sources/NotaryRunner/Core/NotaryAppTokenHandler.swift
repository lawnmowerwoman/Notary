import AppTokenKit
import Foundation

package struct NotaryAppTokenAuthorization {
    package let diagnostics: TokenDiagnostics

    package init(diagnostics: TokenDiagnostics) {
        self.diagnostics = diagnostics
    }

    package var allowsTransporter: Bool {
        diagnostics.status == .valid && diagnostics.capabilities.contains(AppTokenDefaults.feature)
    }

    package var sourceDescription: String {
        diagnostics.source?.rawValue ?? "none"
    }

    package var statusDescription: String {
        diagnostics.status.notaryDescription
    }
}

package enum NotaryAppTokenHandler {
    package static func evaluate(now: Date = Date()) -> NotaryAppTokenAuthorization {
        let candidate = NotaryTokenSources.resolver().resolve()
        let diagnostics = validator(now: now).validate(candidate?.token, source: candidate?.source)
        return NotaryAppTokenAuthorization(diagnostics: diagnostics)
    }

    package static func log(_ authorization: NotaryAppTokenAuthorization, logger: HardenLogger) {
        let diagnostics = authorization.diagnostics
        switch diagnostics.status {
        case .valid:
            let customer = diagnostics.payload?.customerName ?? "unknown customer"
            let activationCode = diagnostics.payload?.activationCode ?? "unknown"
            let validUntil = diagnostics.payload?.validUntil ?? "unknown"
            let features = diagnostics.recognizedFeatures.isEmpty ? "none" : diagnostics.recognizedFeatures.joined(separator: ", ")
            logger.info("App Token valid: source=\(authorization.sourceDescription), customer=\(customer), activationCode=\(activationCode), validUntil=\(validUntil), features=\(features)")
            if !diagnostics.unknownFeatures.isEmpty {
                logger.warn("App Token contains unknown features: \(diagnostics.unknownFeatures.joined(separator: ", "))")
            }
        case .missing:
            logger.warn("App Token missing; optional Transporter capability is disabled.")
        default:
            logger.warn("App Token invalid: source=\(authorization.sourceDescription), status=\(authorization.statusDescription); optional Transporter capability is disabled.")
        }
    }

    private static func validator(now: Date) -> AppTokenValidator {
        AppTokenValidator(
            publicKeys: AppTokenEmbeddedPublicKeys.registry,
            productPolicy: AppTokenDefaults.notaryProductPolicy,
            featureRegistry: AppTokenDefaults.notaryFeatureRegistry,
            now: now
        )
    }
}

private extension TokenValidationStatus {
    var notaryDescription: String {
        switch self {
        case .missing:
            return "missing"
        case .malformed(let reason):
            return "malformed (\(reason))"
        case .unsupportedEnvelopeVersion:
            return "unsupported envelope version"
        case .unsupportedSchemaVersion:
            return "unsupported schema version"
        case .unknownAlgorithm:
            return "unknown algorithm"
        case .unknownKey:
            return "unknown key"
        case .invalidSignature:
            return "invalid signature"
        case .wrongIssuer:
            return "wrong issuer"
        case .wrongProduct:
            return "wrong product"
        case .expired:
            return "expired"
        case .notYetValid:
            return "not yet valid"
        case .valid:
            return "valid"
        }
    }
}
