import CryptoKit
import Foundation
import AppTokenKit

struct AppTokenReferenceTests {
    static let keyId = "test-key-2026-01"
    static let privateKeyData = Data((1...32).map { UInt8($0) })
    static let now = date("2026-07-31T12:00:00Z")

    static func main() throws {
        try validToken()
        try renamedCustomerSameActivationCodeNewSignature()
        try expiredToken()
        try futureToken()
        try wrongProduct()
        try unknownFeatureDoesNotInvalidateToken()
        try unknownKeyID()
        try modifiedPayloadFailsSignature()
        try modifiedSignatureFails()
        malformedBase64URL()
        try unsupportedEnvelopeVersion()
        try sourcePrecedence()
        try invalidDedicatedManagedTokenDoesNotFallBackToLocalStorage()
        try encodeDecodeRoundTrip()
        try canonicalBytesRemainStable()
        try goldenTokenFixture()
        print("AppToken reference tests passed")
    }

    static func validToken() throws {
        let diagnostics = try validate(makeToken())
        expect(diagnostics.status == .valid, "valid token")
        expect(diagnostics.recognizedFeatures == ["transporter"], "recognized transporter")
        expect(diagnostics.capabilities.contains("transporter"), "transporter capability")
    }

    static func renamedCustomerSameActivationCodeNewSignature() throws {
        let first = try makeToken(customerName: "Old Customer", activationCode: "NOTXSTABLE1234")
        let second = try makeToken(customerName: "New Customer", activationCode: "NOTXSTABLE1234")
        expect(first != second, "rename changes signature")
        expect(validate(first).payload?.activationCode == "NOTXSTABLE1234", "first activation code stable")
        expect(validate(second).payload?.activationCode == "NOTXSTABLE1234", "second activation code stable")
        expect(validate(second).payload?.customerName == "New Customer", "customer renamed")
        expect(validate(second).status == .valid, "renamed token valid")
    }

    static func expiredToken() throws {
        let token = try makeToken(validUntil: "2025-12-31")
        expect(validate(token).status == .expired, "expired token")
    }

    static func futureToken() throws {
        let token = try makeToken(validFrom: "2027-01-01")
        expect(validate(token).status == .notYetValid, "future token")
    }

    static func wrongProduct() throws {
        let token = try makeToken(productId: "EXMX")
        expect(validate(token).status == .wrongProduct, "wrong product")
    }

    static func unknownFeatureDoesNotInvalidateToken() throws {
        let diagnostics = try validate(makeToken(features: ["transporter", "centralManagement"]))
        expect(diagnostics.status == .valid, "unknown feature token still valid")
        expect(diagnostics.recognizedFeatures == ["transporter"], "recognized feature retained")
        expect(diagnostics.unknownFeatures == ["centralManagement"], "unknown feature listed")
        expect(diagnostics.capabilities.contains("transporter"), "recognized capability retained")
    }

    static func unknownKeyID() throws {
        let token = try makeToken(keyId: "unknown-key")
        expect(validate(token).status == .unknownKey, "unknown key")
    }

    static func modifiedPayloadFailsSignature() throws {
        let token = try makeToken()
        var parts = token.components(separatedBy: ".")
        let changedPayload = AppTokenPayload(
            issuer: "twocent-notary",
            productId: "NOTX",
            tokenId: "11111111-2222-3333-4444-555555555555",
            activationCode: "NOTX1234567890AB",
            customerName: "Fixture Customer",
            validUntil: "2027-12-31",
            features: ["transporter", "auditExport"],
            issuedAt: "2026-07-31T12:00:00Z"
        )
        parts[2] = b64(try AppTokenCanonicalJSON.payloadData(changedPayload))
        expect(validate(parts.joined(separator: ".")).status == .invalidSignature, "modified payload")
    }

    static func modifiedSignatureFails() throws {
        var parts = try makeToken().components(separatedBy: ".")
        parts[3] = b64(Data(repeating: 1, count: 64))
        expect(validate(parts.joined(separator: ".")).status == .invalidSignature, "modified signature")
    }

    static func malformedBase64URL() {
        expect(validate("TAT1.@@@.payload.signature").status == .malformed("Malformed token: Header is not valid base64url"), "malformed base64url")
    }

    static func unsupportedEnvelopeVersion() throws {
        let token = try makeToken().replacingOccurrences(of: "TAT1.", with: "TAT2.")
        expect(validate(token).status == .unsupportedEnvelopeVersion, "unsupported envelope")
    }

    static func sourcePrecedence() throws {
        let managed = MemorySource(source: .dedicatedManagedProfile, token: "not-a-token")
        let main = MemorySource(source: .mainManagedProfile, token: nil)
        let local = try MemorySource(source: .localSecureStorage, token: makeToken())
        let candidate = AppTokenResolver(sources: [managed, main, local]).resolve()

        expect(candidate?.source == .dedicatedManagedProfile, "dedicated managed source wins")
        expect(validate(candidate?.token, source: candidate?.source).status == .malformed("Malformed token: Expected four envelope parts"), "selected invalid managed token evaluated")
    }

    static func invalidDedicatedManagedTokenDoesNotFallBackToLocalStorage() throws {
        let managed = try MemorySource(source: .dedicatedManagedProfile, token: makeToken(validUntil: "2025-12-31"))
        let local = try MemorySource(source: .localSecureStorage, token: makeToken())
        let candidate = AppTokenResolver(sources: [managed, local]).resolve()
        let diagnostics = validate(candidate?.token, source: candidate?.source)

        expect(candidate?.source == .dedicatedManagedProfile, "invalid managed token remains authoritative")
        expect(diagnostics.status == .expired, "no local fallback after managed validation failure")
    }

    static func encodeDecodeRoundTrip() throws {
        let decoded = try AppTokenCodec.decode(makeToken())
        let header = try AppTokenCanonicalJSON.parseHeader(decoded.headerData)
        let payload = try AppTokenCanonicalJSON.parsePayload(decoded.payloadData)

        expect(header.keyId == keyId, "round trip key id")
        expect(payload.customerName == "Fixture Customer", "round trip customer")
        expect(payload.features == ["transporter"], "round trip features")
    }

    static func canonicalBytesRemainStable() throws {
        let canonical = String(decoding: try AppTokenCanonicalJSON.payloadData(fixturePayload()), as: UTF8.self)
        expect(
            canonical == #"{"activationCode":"NOTX1234567890AB","customerName":"Fixture Customer","features":["transporter"],"issuedAt":"2026-07-31T12:00:00Z","issuer":"twocent-notary","productId":"NOTX","schemaVersion":1,"tokenId":"11111111-2222-3333-4444-555555555555","validUntil":"2027-12-31"}"#,
            "canonical payload stable"
        )
    }

    static func goldenTokenFixture() throws {
        let url = URL(fileURLWithPath: "Tests/AppTokenKitTests/Fixtures/golden-token.txt")
        let token = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

        expect(validate(token).status == .valid, "golden token valid")
        expect(validate(token).payload == fixturePayload(), "golden token payload")
    }

    static func makeToken(
        keyId: String? = nil,
        productId: String = "NOTX",
        customerName: String = "Fixture Customer",
        activationCode: String = "NOTX1234567890AB",
        validFrom: String? = nil,
        validUntil: String = "2027-12-31",
        features: [String] = ["transporter"]
    ) throws -> String {
        let signer = try AppTokenSigner(rawPrivateKey: privateKeyData)
        return try signer.sign(
            header: AppTokenHeader(keyId: keyId ?? self.keyId),
            payload: AppTokenPayload(
                issuer: "twocent-notary",
                productId: productId,
                tokenId: "11111111-2222-3333-4444-555555555555",
                activationCode: activationCode,
                customerName: customerName,
                validFrom: validFrom,
                validUntil: validUntil,
                features: features,
                issuedAt: "2026-07-31T12:00:00Z"
            )
        ).token
    }

    static func fixturePayload() -> AppTokenPayload {
        AppTokenPayload(
            issuer: "twocent-notary",
            productId: "NOTX",
            tokenId: "11111111-2222-3333-4444-555555555555",
            activationCode: "NOTX1234567890AB",
            customerName: "Fixture Customer",
            validUntil: "2027-12-31",
            features: ["transporter"],
            issuedAt: "2026-07-31T12:00:00Z"
        )
    }

    static func validate(_ token: String?, source: TokenSourceKind? = nil) -> TokenDiagnostics {
        let publicKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData).publicKey.rawRepresentation
        return AppTokenValidator(
            publicKeys: PublicKeyRegistry(rawKeys: [keyId: publicKey]),
            productPolicy: ProductPolicy(acceptedProductIds: ["NOTX", "NOT2"], acceptedIssuers: ["twocent-notary"]),
            featureRegistry: FeatureRegistry(recognizedFeatures: ["transporter"]),
            now: now
        ).validate(token, source: source)
    }

    static func b64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Test failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

try AppTokenReferenceTests.main()

private struct MemorySource: AppTokenSource {
    var source: TokenSourceKind
    var token: String?

    func readToken() throws -> String? {
        token
    }
}
