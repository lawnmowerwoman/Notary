import Foundation

public enum TransportAvailability: String, Sendable {
    case publicDummy
    case confidential
}

public enum TransportResultStatus: String, Sendable {
    case implementationUnavailable
    case skipped
    case completed
    case failed
}

public struct TransportCredentials: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum NotaryJamfExtensionAttribute {
    public static let runner = "Notary Runner"
    public static let issues = "Notary Issues"
    public static let compliance = "Notary Compliance"
    public static let percent = "Notary Percent"
    public static let connection = "Notary Connection"
    public static let lastContact = "Notary Last Contact"
}

public enum TransportTimestampFormat {
    public static func extensionAttributeValue(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public struct TransportEAState: Sendable, Equatable {
    public var definitionIDs: [String: Int]
    public var cacheUpdatedAt: Date?
    public var refreshAttemptedAt: Date?
    public var refreshFailCount: Int

    public init(
        definitionIDs: [String: Int],
        cacheUpdatedAt: Date?,
        refreshAttemptedAt: Date?,
        refreshFailCount: Int
    ) {
        self.definitionIDs = definitionIDs
        self.cacheUpdatedAt = cacheUpdatedAt
        self.refreshAttemptedAt = refreshAttemptedAt
        self.refreshFailCount = refreshFailCount
    }
}

public struct TransportProofValues: Sendable, Equatable {
    public let runner: String
    public let issues: String
    public let compliance: String
    public let percent: String?
    public let connection: String?
    public let lastContact: String?

    public init(
        runner: String,
        issues: String,
        compliance: String,
        percent: String?,
        connection: String?,
        lastContact: String? = nil
    ) {
        self.runner = runner
        self.issues = issues
        self.compliance = compliance
        self.percent = percent
        self.connection = connection
        self.lastContact = lastContact
    }
}

public struct TransportRequest: Sendable, Equatable {
    public let shouldTransport: Bool
    public let serialNumber: String
    public let baseURL: URL?
    public let credentials: TransportCredentials?
    public let cachedComputerID: Int?
    public let bearerToken: String?
    public let bearerExpirationEpoch: Int?
    public let eaState: TransportEAState
    public let proofValues: TransportProofValues

    public init(
        shouldTransport: Bool,
        serialNumber: String,
        baseURL: URL?,
        credentials: TransportCredentials?,
        cachedComputerID: Int?,
        bearerToken: String?,
        bearerExpirationEpoch: Int?,
        eaState: TransportEAState,
        proofValues: TransportProofValues
    ) {
        self.shouldTransport = shouldTransport
        self.serialNumber = serialNumber
        self.baseURL = baseURL
        self.credentials = credentials
        self.cachedComputerID = cachedComputerID
        self.bearerToken = bearerToken
        self.bearerExpirationEpoch = bearerExpirationEpoch
        self.eaState = eaState
        self.proofValues = proofValues
    }
}

public struct TransportResult: Sendable, Equatable {
    public let status: TransportResultStatus
    public let availability: TransportAvailability
    public let didAttemptNetwork: Bool
    public let didRemoteUpdate: Bool
    public let computerID: Int?
    public let bearerToken: String?
    public let bearerExpirationEpoch: Int?
    public let eaState: TransportEAState?
    public let logMessages: [String]

    public init(
        status: TransportResultStatus,
        availability: TransportAvailability,
        didAttemptNetwork: Bool,
        didRemoteUpdate: Bool,
        computerID: Int? = nil,
        bearerToken: String? = nil,
        bearerExpirationEpoch: Int? = nil,
        eaState: TransportEAState? = nil,
        logMessages: [String] = []
    ) {
        self.status = status
        self.availability = availability
        self.didAttemptNetwork = didAttemptNetwork
        self.didRemoteUpdate = didRemoteUpdate
        self.computerID = computerID
        self.bearerToken = bearerToken
        self.bearerExpirationEpoch = bearerExpirationEpoch
        self.eaState = eaState
        self.logMessages = logMessages
    }
}

public protocol TransportService: Sendable {
    var availability: TransportAvailability { get }
    func perform(_ request: TransportRequest) async -> TransportResult
}

public struct PublicDummyTransportService: TransportService {
    public let availability: TransportAvailability = .publicDummy

    public init() {}

    public func perform(_ request: TransportRequest) async -> TransportResult {
        TransportResult(
            status: .implementationUnavailable,
            availability: .publicDummy,
            didAttemptNetwork: false,
            didRemoteUpdate: false,
            logMessages: [
                "Transport implementation unavailable: this public build does not include the confidential Transporter.",
                "Remote transport skipped; local Notary results remain available."
            ]
        )
    }
}

public enum NotaryTransport {
    public static var availability: TransportAvailability {
        .publicDummy
    }

    public static func makeService() -> any TransportService {
        PublicDummyTransportService()
    }
}
