import CryptoKit
import Foundation

public struct PublicKeyRegistry {
    private var keys: [String: Curve25519.Signing.PublicKey]

    public init(rawKeys: [String: Data]) {
        var parsed: [String: Curve25519.Signing.PublicKey] = [:]
        for (keyId, data) in rawKeys {
            if let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) {
                parsed[keyId] = key
            }
        }
        self.keys = parsed
    }

    public func publicKey(for keyId: String) -> Curve25519.Signing.PublicKey? {
        keys[keyId]
    }
}

public struct AppTokenValidator {
    public var publicKeys: PublicKeyRegistry
    public var productPolicy: ProductPolicy
    public var featureRegistry: FeatureRegistry
    public var now: Date

    public init(
        publicKeys: PublicKeyRegistry,
        productPolicy: ProductPolicy,
        featureRegistry: FeatureRegistry,
        now: Date = Date()
    ) {
        self.publicKeys = publicKeys
        self.productPolicy = productPolicy
        self.featureRegistry = featureRegistry
        self.now = now
    }

    public func validate(_ token: String?, source: TokenSourceKind? = nil) -> TokenDiagnostics {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TokenDiagnostics(source: source, status: .missing)
        }

        let decoded: (prefix: String, headerData: Data, payloadData: Data, signature: Data)
        do {
            decoded = try AppTokenCodec.decode(token)
        } catch let error as AppTokenError {
            return TokenDiagnostics(source: source, status: .malformed(error.description))
        } catch {
            return TokenDiagnostics(source: source, status: .malformed(String(describing: error)))
        }

        guard decoded.prefix == AppTokenConstants.envelopePrefix else {
            return TokenDiagnostics(source: source, status: .unsupportedEnvelopeVersion)
        }

        let header: AppTokenHeader
        do {
            header = try AppTokenCanonicalJSON.parseHeader(decoded.headerData)
        } catch {
            return TokenDiagnostics(source: source, status: .malformed(String(describing: error)))
        }

        guard header.type == AppTokenConstants.tokenType, header.formatVersion == AppTokenConstants.formatVersion else {
            return TokenDiagnostics(source: source, status: .unsupportedEnvelopeVersion, header: header)
        }
        guard header.algorithm == AppTokenConstants.algorithm else {
            return TokenDiagnostics(source: source, status: .unknownAlgorithm, header: header)
        }
        guard let publicKey = publicKeys.publicKey(for: header.keyId) else {
            return TokenDiagnostics(source: source, status: .unknownKey, header: header)
        }

        let signingInput = AppTokenCodec.signingInput(canonicalHeader: decoded.headerData, canonicalPayload: decoded.payloadData)
        guard publicKey.isValidSignature(decoded.signature, for: signingInput) else {
            return TokenDiagnostics(source: source, status: .invalidSignature, header: header)
        }

        let payload: AppTokenPayload
        do {
            payload = try AppTokenCanonicalJSON.parsePayload(decoded.payloadData)
        } catch {
            return TokenDiagnostics(source: source, status: .malformed(String(describing: error)), header: header)
        }

        guard payload.schemaVersion == AppTokenConstants.schemaVersion else {
            return TokenDiagnostics(source: source, status: .unsupportedSchemaVersion, header: header, payload: payload)
        }
        guard productPolicy.acceptedIssuers.contains(payload.issuer) else {
            return TokenDiagnostics(source: source, status: .wrongIssuer, header: header, payload: payload)
        }
        guard productPolicy.acceptedProductIds.contains(payload.productId) else {
            return TokenDiagnostics(source: source, status: .wrongProduct, header: header, payload: payload)
        }
        guard validFromSatisfied(payload.validFrom) else {
            return TokenDiagnostics(source: source, status: .notYetValid, header: header, payload: payload)
        }
        guard validUntilSatisfied(payload.validUntil) else {
            return TokenDiagnostics(source: source, status: .expired, header: header, payload: payload)
        }

        let recognized = payload.features.filter { featureRegistry.recognizedFeatures.contains($0) }
        let unknown = payload.features.filter { !featureRegistry.recognizedFeatures.contains($0) }
        return TokenDiagnostics(
            source: source,
            status: .valid,
            recognizedFeatures: recognized,
            unknownFeatures: unknown,
            capabilities: Set(recognized),
            header: header,
            payload: payload
        )
    }

    private func validFromSatisfied(_ value: String?) -> Bool {
        guard let value else { return true }
        guard let date = Self.dateOnly(value) else { return false }
        return now >= date
    }

    private func validUntilSatisfied(_ value: String) -> Bool {
        guard let date = Self.dateOnly(value),
              let end = Calendar(identifier: .gregorian).date(byAdding: DateComponents(day: 1, second: -1), to: date) else {
            return false
        }
        return now <= end
    }

    static func dateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

