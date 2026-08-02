import Foundation

public enum AppTokenConstants {
    public static let envelopePrefix = "TAT1"
    public static let tokenType = "twocent-app-token"
    public static let formatVersion = 1
    public static let schemaVersion = 1
    public static let algorithm = "Ed25519"
}

public struct AppTokenHeader: Equatable {
    public var type: String
    public var formatVersion: Int
    public var algorithm: String
    public var keyId: String

    public init(
        type: String = AppTokenConstants.tokenType,
        formatVersion: Int = AppTokenConstants.formatVersion,
        algorithm: String = AppTokenConstants.algorithm,
        keyId: String
    ) {
        self.type = type
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.keyId = keyId
    }
}

public struct AppTokenPayload: Equatable {
    public var schemaVersion: Int
    public var issuer: String
    public var productId: String
    public var tokenId: String
    public var activationCode: String
    public var customerName: String
    public var validFrom: String?
    public var validUntil: String
    public var features: [String]
    public var issuedAt: String?

    public init(
        schemaVersion: Int = AppTokenConstants.schemaVersion,
        issuer: String,
        productId: String,
        tokenId: String,
        activationCode: String,
        customerName: String,
        validFrom: String? = nil,
        validUntil: String,
        features: [String],
        issuedAt: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.issuer = issuer
        self.productId = productId
        self.tokenId = tokenId
        self.activationCode = activationCode
        self.customerName = customerName
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.features = features
        self.issuedAt = issuedAt
    }
}

public struct AppTokenEnvelope: Equatable {
    public var header: AppTokenHeader
    public var payload: AppTokenPayload
    public var signature: Data
    public var canonicalHeader: Data
    public var canonicalPayload: Data

    public init(
        header: AppTokenHeader,
        payload: AppTokenPayload,
        signature: Data,
        canonicalHeader: Data,
        canonicalPayload: Data
    ) {
        self.header = header
        self.payload = payload
        self.signature = signature
        self.canonicalHeader = canonicalHeader
        self.canonicalPayload = canonicalPayload
    }
}

public struct ProductPolicy: Equatable {
    public var acceptedProductIds: Set<String>
    public var acceptedIssuers: Set<String>

    public init(acceptedProductIds: Set<String>, acceptedIssuers: Set<String>) {
        self.acceptedProductIds = acceptedProductIds
        self.acceptedIssuers = acceptedIssuers
    }
}

public struct FeatureRegistry: Equatable {
    public var recognizedFeatures: Set<String>

    public init(recognizedFeatures: Set<String>) {
        self.recognizedFeatures = recognizedFeatures
    }
}

public enum TokenValidationStatus: Equatable {
    case missing
    case malformed(String)
    case unsupportedEnvelopeVersion
    case unsupportedSchemaVersion
    case unknownAlgorithm
    case unknownKey
    case invalidSignature
    case wrongIssuer
    case wrongProduct
    case expired
    case notYetValid
    case valid
}

public struct TokenDiagnostics: Equatable {
    public var source: TokenSourceKind?
    public var status: TokenValidationStatus
    public var recognizedFeatures: [String]
    public var unknownFeatures: [String]
    public var capabilities: Set<String>
    public var header: AppTokenHeader?
    public var payload: AppTokenPayload?

    public init(
        source: TokenSourceKind? = nil,
        status: TokenValidationStatus,
        recognizedFeatures: [String] = [],
        unknownFeatures: [String] = [],
        capabilities: Set<String> = [],
        header: AppTokenHeader? = nil,
        payload: AppTokenPayload? = nil
    ) {
        self.source = source
        self.status = status
        self.recognizedFeatures = recognizedFeatures
        self.unknownFeatures = unknownFeatures
        self.capabilities = capabilities
        self.header = header
        self.payload = payload
    }
}

public struct CapabilityProvider: Equatable {
    public var diagnostics: TokenDiagnostics

    public init(diagnostics: TokenDiagnostics) {
        self.diagnostics = diagnostics
    }

    public func isEnabled(_ feature: String) -> Bool {
        diagnostics.capabilities.contains(feature)
    }
}

