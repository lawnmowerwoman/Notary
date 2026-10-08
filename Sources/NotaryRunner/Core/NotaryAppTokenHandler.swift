import AppTokenKit
import Foundation

package struct NotaryAppTokenAuthorization {
    package let diagnostics: TokenDiagnostics
    package let licenseRestriction: String?
    package let serverManaged: Bool

    package init(diagnostics: TokenDiagnostics, licenseRestriction: String? = nil, serverManaged: Bool = false) {
        self.diagnostics = diagnostics
        self.licenseRestriction = licenseRestriction
        self.serverManaged = serverManaged
    }

    package var isAuthorized: Bool { diagnostics.status == .valid && licenseRestriction == nil }

    package var allowsTransporter: Bool {
        isAuthorized && diagnostics.capabilities.contains(NotaryTokenFeature.transport)
    }

    package var allowsReporter: Bool {
        isAuthorized && diagnostics.capabilities.contains(NotaryTokenFeature.reporter)
    }

    package var allowsConfigurator: Bool {
        isAuthorized && diagnostics.capabilities.contains(NotaryTokenFeature.configurator)
    }

    package var sourceDescription: String {
        diagnostics.source?.rawValue ?? "none"
    }

    package var statusDescription: String {
        licenseRestriction ?? diagnostics.status.notaryDescription
    }
}

package enum NotaryAppTokenHandler {
    package static func evaluate(
        now: Date = Date(),
        activationCode: String? = NotaryActivationCode.currentConfiguredValue(),
        candidate: TokenCandidate? = NotaryTokenSources.resolver().resolve(),
        cache: NotaryLicenseCache = NotaryLicenseCache(),
        publicKeys: PublicKeyRegistry = AppTokenEmbeddedPublicKeys.registry
    ) -> NotaryAppTokenAuthorization {
        let validator = AppTokenValidator(publicKeys: publicKeys, productPolicy: AppTokenDefaults.notaryProductPolicy,
                                          featureRegistry: AppTokenDefaults.notaryFeatureRegistry, now: now)
        let snapshot: NotaryLicenseCacheSnapshot
        do { snapshot = try cache.load() }
        catch {
            return NotaryAppTokenAuthorization(diagnostics: validator.validate(nil), licenseRestriction: "license_cache_unreadable",
                                              serverManaged: activationCode != nil)
        }
        if let state = snapshot.state, state.serverManaged, state.activationCode == activationCode {
            let diagnostics = validator.validate(snapshot.token, source: .localSecureStorage)
            return authorization(diagnostics, activationCode: activationCode,
                                 restriction: state.rejectionReason, serverManaged: true)
        }
        let selected = candidate ?? snapshot.token.map { TokenCandidate(source: .localSecureStorage, token: $0) }
        let diagnostics = validator.validate(selected?.token, source: selected?.source)
        return authorization(diagnostics, activationCode: activationCode)
    }

    private static func authorization(_ diagnostics: TokenDiagnostics, activationCode: String?,
                                      restriction: String? = nil, serverManaged: Bool = false) -> NotaryAppTokenAuthorization {
        let mismatch = diagnostics.status == .valid && activationCode != nil && diagnostics.payload?.activationCode != activationCode
        return NotaryAppTokenAuthorization(diagnostics: diagnostics,
                                          licenseRestriction: restriction ?? (mismatch ? "activation_code_mismatch" : nil),
                                          serverManaged: serverManaged)
    }

    package static func allowsFeatureForUI(_ feature: String, now: Date = Date()) -> Bool {
        if let report = try? NotaryPublicReportStore().loadTrustedForAuthorization(),
           report.appTokenServerManaged,
           report.activationCode == NotaryActivationCode.currentConfiguredValue() {
            return reportAllowsFeature(report, feature: feature, now: now)
        }
        let authorization = evaluate(now: now)
        return authorization.isAuthorized && authorization.diagnostics.capabilities.contains(feature)
    }

    package static func reportAllowsFeature(_ report: NotaryPublicReport, feature: String, now: Date) -> Bool {
        guard report.appTokenServerManaged, report.appTokenFeatures.contains(feature),
              let until = report.appTokenValidUntil else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(until.prefix(10))) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let end = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
        return now < end
    }

    package static func log(_ authorization: NotaryAppTokenAuthorization, logger: HardenLogger) {
        let diagnostics = authorization.diagnostics
        if let restriction = authorization.licenseRestriction {
            logger.warn("App Token authorization restricted: \(restriction); optional module capabilities are disabled.")
            return
        }
        switch diagnostics.status {
        case .valid:
            let customer = diagnostics.payload?.customerName ?? "unknown customer"
            let activationCode = diagnostics.payload.map { "\($0.activationCode.prefix(4))...\($0.activationCode.suffix(4))" } ?? "unknown"
            let validUntil = diagnostics.payload?.validUntil ?? "unknown"
            let features = diagnostics.recognizedFeatures.isEmpty ? "none" : diagnostics.recognizedFeatures.joined(separator: ", ")
            logger.info("App Token valid: source=\(authorization.sourceDescription), customer=\(customer), activationCode=\(activationCode), validUntil=\(validUntil), features=\(features)")
            if !diagnostics.unknownFeatures.isEmpty {
                logger.warn("App Token contains unknown features: \(diagnostics.unknownFeatures.joined(separator: ", "))")
            }
        case .missing:
            logger.warn("App Token missing; optional module capabilities are disabled.")
        default:
            logger.warn("App Token invalid: source=\(authorization.sourceDescription), status=\(authorization.statusDescription); optional module capabilities are disabled.")
        }
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
