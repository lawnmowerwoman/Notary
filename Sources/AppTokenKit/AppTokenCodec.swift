import CryptoKit
import Foundation

public enum AppTokenCodec {
    public static func signingInput(canonicalHeader: Data, canonicalPayload: Data) -> Data {
        let header = Base64URL.encode(canonicalHeader)
        let payload = Base64URL.encode(canonicalPayload)
        return Data("\(header).\(payload)".utf8)
    }

    public static func encode(header: Data, payload: Data, signature: Data) -> String {
        [
            AppTokenConstants.envelopePrefix,
            Base64URL.encode(header),
            Base64URL.encode(payload),
            Base64URL.encode(signature)
        ].joined(separator: ".")
    }

    public static func decode(_ token: String) throws -> (prefix: String, headerData: Data, payloadData: Data, signature: Data) {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard parts.count == 4 else {
            throw AppTokenError.malformed("Expected four envelope parts")
        }
        guard let header = Base64URL.decode(parts[1]) else {
            throw AppTokenError.malformed("Header is not valid base64url")
        }
        guard let payload = Base64URL.decode(parts[2]) else {
            throw AppTokenError.malformed("Payload is not valid base64url")
        }
        guard let signature = Base64URL.decode(parts[3]) else {
            throw AppTokenError.malformed("Signature is not valid base64url")
        }
        return (parts[0], header, payload, signature)
    }
}

public struct AppTokenSigner {
    private let privateKey: Curve25519.Signing.PrivateKey

    public init(rawPrivateKey: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public var rawPublicKey: Data {
        privateKey.publicKey.rawRepresentation
    }

    public func sign(header: AppTokenHeader, payload: AppTokenPayload) throws -> (token: String, canonicalHeader: Data, canonicalPayload: Data) {
        let canonicalHeader = try AppTokenCanonicalJSON.headerData(header)
        let canonicalPayload = try AppTokenCanonicalJSON.payloadData(payload)
        let input = AppTokenCodec.signingInput(canonicalHeader: canonicalHeader, canonicalPayload: canonicalPayload)
        let signature = try privateKey.signature(for: input)
        let token = AppTokenCodec.encode(header: canonicalHeader, payload: canonicalPayload, signature: signature)
        return (token, canonicalHeader, canonicalPayload)
    }
}

