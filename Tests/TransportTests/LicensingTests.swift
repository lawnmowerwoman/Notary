import AppTokenKit
import Foundation
import NotaryCore

private final class LicensingMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

enum LicensingRegressionTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-08T19:00:00Z")!
    static let code = "NOTX-LOCAL-TEST"
    static var signer: AppTokenSigner { try! AppTokenSigner(rawPrivateKey: Data((1...32).map(UInt8.init))) }
    static var keys: PublicKeyRegistry { PublicKeyRegistry(rawKeys: ["licensing-test": signer.rawPublicKey]) }

    static func run() async throws {
        defer { LicensingMockProtocol.handler = nil }
        try await successfulFetchAndRestart()
        try await failuresKeepValidCache()
        try await rejectsInvalidAndMismatchedTokens()
        try await actualVersionAnd304()
        try await denialSurvivesRestartAndRecovery()
        try await unknownLicenseIsDifferentFromUnknownEndpoint()
        try cachePrecedenceAndExpiration()
        try activationCodeChangeDoesNotReuseOldToken()
        try profileBootstrapDoesNotExtractActivationCode()
        try stateSavePreservesMetadataAndPermissions()
        trustedProjectionGatesGUIFeatures()
        try await integrationIfConfigured()
        print("Licensing regression tests passed (11 scenarios)")
    }

    private struct Fixture {
        let root: URL
        let plist: URL
        let store: SecurePlistStore<RunnerState>
        let cache: NotaryLicenseCache
        let session: URLSession
        let client: NotaryLicenseClient

        init(serverURL: URL = URL(string: "https://licensing.invalid")!, useNetwork: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("notary-license-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            plist = root.appendingPathComponent("notary.plist")
            store = SecurePlistStore<RunnerState>(preservedExternalKeys: NotaryLicenseCache.preservedKeys, rootURL: plist, tmpURL: plist)
            cache = NotaryLicenseCache(store: store)
            let config = URLSessionConfiguration.ephemeral
            if !useNetwork { config.protocolClasses = [LicensingMockProtocol.self] }
            session = URLSession(configuration: config)
            client = NotaryLicenseClient(serverURL: serverURL, session: session,
                                        cache: cache, publicKeys: keys, now: { now })
        }

        func authorization(candidate: TokenCandidate? = nil, activationCode: String? = code, at: Date = now) -> NotaryAppTokenAuthorization {
            NotaryAppTokenHandler.evaluate(now: at, activationCode: activationCode, candidate: candidate, cache: cache, publicKeys: keys)
        }

        func checkIn() async -> NotaryLicenseClientResult {
            await client.checkIn(activationCode: code, machineIdentifier: "test-machine", currentAuthorization: authorization(), notaryVersion: "1C-test")
        }

        func cleanup() {
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func token(id: String = "token-7", activationCode: String = code,
                              product: String = "NOTX", until: String = "2026-11-07", features: [String] = ["transporter"],
                              from: String? = nil, keyId: String = "licensing-test") throws -> String {
        try signer.sign(header: AppTokenHeader(keyId: keyId), payload: AppTokenPayload(
            issuer: AppTokenDefaults.issuer, productId: product, tokenId: id,
            activationCode: activationCode, customerName: "Fixture Customer", validFrom: from, validUntil: until,
            features: features, issuedAt: "2026-10-08T18:00:00Z"
        )).token
    }

    private static func response(_ token: String, id: String = "token-7", version: Any = 7,
                                 until: String = "2026-11-07", product: String = "NOTX") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["appToken": token, "productId": product, "tokenId": id,
                                                   "tokenVersion": version, "validUntil": until])
    }

    private static func successfulFetchAndRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let raw = try token(features: AppTokenDefaults.notaryFeatures)
        let body = try response(raw)
        LicensingMockProtocol.handler = { request in
            expect(request.url?.path == "/api/v1/devices/check-in", "v1 check-in path")
            let payload = try requestBody(request)
            expect(payload["activationCode"] as? String == code, "configured code sent")
            expect(payload["machineIdentifier"] as? String == "test-machine", "machine sent")
            expect(payload["currentTokenVersion"] == nil, "fresh client has no version")
            return (200, body)
        }
        let result = await fixture.checkIn()
        expect(result == .tokenUpdated(tokenId: "token-7", tokenVersion: 7, validUntil: "2026-11-07"), "new token accepted")
        let snapshot = try fixture.cache.load()
        expect(snapshot.token == raw && snapshot.state?.tokenVersion == 7, "token and revision persisted together")
        expect(try fixture.store.load()?.activationCode == nil, "fetch does not extract activation code into RunnerState")
        let reopenedStore = SecurePlistStore<RunnerState>(preservedExternalKeys: NotaryLicenseCache.preservedKeys, rootURL: fixture.plist, tmpURL: fixture.plist)
        let reopened = NotaryLicenseCache(store: reopenedStore)
        let auth = NotaryAppTokenHandler.evaluate(now: now, activationCode: code, candidate: nil, cache: reopened, publicKeys: keys)
        expect(auth.allowsTransporter && auth.allowsReporter && auth.allowsConfigurator, "features survive restart")
    }

    private static func failuresKeepValidCache() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let raw = try token()
        try fixture.cache.storeToken(raw, activationCode: code, tokenId: "token-7", tokenVersion: 7)
        for status in [429, 500, 502, 503, 403, 404, 302] {
            LicensingMockProtocol.handler = { _ in (status, Data("{\"error\":\"not_found\"}".utf8)) }
            let result = await fixture.checkIn()
            if case .failed = result {} else { expect(false, "infrastructure failure classification") }
            expect(try fixture.cache.load().token == raw, "failure does not replace cache")
            expect(fixture.authorization().allowsTransporter, "valid cache works offline")
        }
        for errorCode in [URLError.timedOut, .notConnectedToInternet, .cannotFindHost, .serverCertificateUntrusted] {
            LicensingMockProtocol.handler = { _ in throw URLError(errorCode) }
            _ = await fixture.checkIn()
            expect(fixture.authorization().allowsTransporter, "network or TLS failure keeps valid cache")
        }
    }

    private static func rejectsInvalidAndMismatchedTokens() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let raw = try token()
        try fixture.cache.storeToken(raw, activationCode: code, tokenId: "token-7", tokenVersion: 7)
        var corrupt = raw.components(separatedBy: ".")
        corrupt[3] = Data(repeating: 0, count: 64).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let invalidResponses = try [
            response("TAT1.invalid"),
            response(corrupt.joined(separator: ".")),
            response(token(keyId: "untrusted-key")),
            response(token(from: "2027-01-01")),
            response(token(activationCode: "NOTX-OTHER")),
            response(token(product: "EXMX"), product: "EXMX"),
            response(token(until: "2025-01-01"), until: "2025-01-01"),
            response(raw, id: "metadata-id-mismatch"),
            response(raw, until: "2099-12-31"),
            response(raw, version: true),
            response(raw, version: 0),
            response(raw, version: 6),
            Data("{}".utf8)
        ]
        for body in invalidResponses {
            LicensingMockProtocol.handler = { _ in (200, body) }
            let result = await fixture.checkIn()
            if case .failed = result {} else { expect(false, "bad response rejected") }
            expect(try fixture.cache.load().token == raw, "invalid response leaves trusted cache unchanged")
        }
    }

    private static func actualVersionAnd304() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let raw = try token()
        try fixture.cache.storeToken(raw, activationCode: code, tokenId: "token-7", tokenVersion: 7)
        LicensingMockProtocol.handler = { request in
            let payload = try requestBody(request)
            expect(payload["currentTokenId"] as? String == "token-7", "actual cached ID sent")
            expect(payload["currentTokenVersion"] as? Int == 7, "actual cached version sent")
            return (304, Data())
        }
        let result = await fixture.checkIn()
        expect(result == .tokenCurrent, "304 confirms cache")
        let fresh = try Fixture()
        defer { fresh.cleanup() }
        LicensingMockProtocol.handler = { _ in (304, Data()) }
        let unexpected = await fresh.checkIn()
        expect(unexpected == .failed("unexpected_not_modified"), "304 without a cached revision rejected")
    }

    private static func denialSurvivesRestartAndRecovery() async throws {
        for reason in ["license_disabled", "license_not_valid"] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let raw = try token()
            try fixture.cache.storeToken(raw, activationCode: code, tokenId: "token-7", tokenVersion: 7)
            LicensingMockProtocol.handler = { _ in (403, Data("{\"error\":\"\(reason)\"}".utf8)) }
            let result = await fixture.checkIn()
            expect(result == .licenseRejected(reason), "known denial reported")
            expect(!fixture.authorization().allowsTransporter, "denial prevents cached feature")
            let reopened = NotaryLicenseCache(store: SecurePlistStore<RunnerState>(rootURL: fixture.plist, tmpURL: fixture.plist))
            let auth = NotaryAppTokenHandler.evaluate(now: now, activationCode: code, candidate: nil, cache: reopened, publicKeys: keys)
            expect(!auth.isAuthorized, "denial survives restart")
            LicensingMockProtocol.handler = { _ in throw URLError(.timedOut) }
            _ = await fixture.checkIn()
            expect(!fixture.authorization().isAuthorized, "offline failure cannot undo denial")
            let replacement = try token(id: "token-8", features: ["reporter"])
            let body = try response(replacement, id: "token-8", version: 8)
            LicensingMockProtocol.handler = { request in
                expect(try requestBody(request)["currentTokenVersion"] == nil, "denied cache forces token refetch")
                return (200, body)
            }
            _ = await fixture.checkIn()
            expect(fixture.authorization().allowsReporter && !fixture.authorization().allowsTransporter, "new validated token restores its own features")
        }
    }

    private static func unknownLicenseIsDifferentFromUnknownEndpoint() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.cache.storeToken(token(), activationCode: code, tokenId: "token-7", tokenVersion: 7)
        LicensingMockProtocol.handler = { _ in (404, Data("{\"error\":\"activation_code_unknown\"}".utf8)) }
        let result = await fixture.checkIn()
        expect(result == .activationCodeUnknown, "known API unknown-license response")
        expect(!fixture.authorization().isAuthorized, "unknown license does not fall back to token")
    }

    private static func cachePrecedenceAndExpiration() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.cache.storeToken(token(features: ["reporter"]), activationCode: code, tokenId: "token-7", tokenVersion: 7)
        let managed = TokenCandidate(source: .dedicatedManagedProfile, token: try token(id: "old-profile", until: "2027-12-31", features: AppTokenDefaults.notaryFeatures))
        expect(!fixture.authorization(candidate: managed).allowsTransporter, "old profile cannot regrant a removed feature")
        expect(fixture.authorization(candidate: managed).allowsReporter, "server cache grants reporter")
        let future = ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z")!
        expect(!fixture.authorization(candidate: managed, at: future).isAuthorized, "expired cache cannot fall back to old profile")
    }

    private static func activationCodeChangeDoesNotReuseOldToken() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let raw = try token()
        try fixture.cache.storeToken(raw, activationCode: code, tokenId: "token-7", tokenVersion: 7)
        let local = TokenCandidate(source: .localSecureStorage, token: raw)
        expect(!fixture.authorization(candidate: local, activationCode: "NOTX-NEW").isAuthorized, "changed code cannot reuse another license")
    }

    private static func profileBootstrapDoesNotExtractActivationCode() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let candidate = TokenCandidate(source: .dedicatedManagedProfile, token: try token())
        let auth = fixture.authorization(candidate: candidate, activationCode: nil)
        try fixture.cache.seedManagedToken(candidate: candidate, authorization: auth, activationCode: nil)
        expect(try fixture.cache.load().token == candidate.token, "validated profile token bootstraps local cache")
        expect(try fixture.store.load()?.activationCode == nil, "bootstrap does not infer activation code")
        expect(fixture.authorization(activationCode: nil).allowsTransporter, "profile bootstrap remains usable after the profile disappears")
    }

    private static func stateSavePreservesMetadataAndPermissions() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.cache.storeToken(token(), activationCode: code, tokenId: "token-7", tokenVersion: 7)
        try fixture.cache.recordRejection(activationCode: code, reason: "license_disabled")
        var state = RunnerState()
        state.lastRunOK = true
        state.activationCode = code
        try fixture.store.save(state)
        let snapshot = try fixture.cache.load()
        expect(snapshot.state?.tokenVersion == 7 && snapshot.state?.rejectionReason == "license_disabled", "runner save preserves all licensing metadata")
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.plist.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "cache remains private 0600")
    }

    private static func trustedProjectionGatesGUIFeatures() {
        var report = NotaryPublicReport(generatedAt: now, lastRunAt: nil, lastTransportUpdateAt: now,
            runnerStatus: "OK", issuesValue: "EMPTY", complianceValue: "PASSED", marketingVersion: "2.2", versionLabel: "1C-test",
            serialNumber: nil, hardwareModel: nil, managementHost: nil, managementComputerID: nil,
            activationCode: code, appTokenValidUntil: "2026-11-07", appTokenFeatures: ["reporter"], appTokenServerManaged: true)
        expect(NotaryAppTokenHandler.reportAllowsFeature(report, feature: "reporter", now: now), "GUI uses daemon-validated server features")
        expect(!NotaryAppTokenHandler.reportAllowsFeature(report, feature: "transporter", now: now), "GUI cannot regrant old profile features")
        let expired = ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z")!
        expect(!NotaryAppTokenHandler.reportAllowsFeature(report, feature: "reporter", now: expired), "GUI projection expires locally")
        report.applyLicenseAuthorization(NotaryAppTokenAuthorization(diagnostics: TokenDiagnostics(status: .valid),
                                         licenseRestriction: "license_disabled", serverManaged: true), activationCode: code)
        expect(!NotaryAppTokenHandler.reportAllowsFeature(report, feature: "reporter", now: now), "denial immediately removes GUI features")
        expect(report.generatedAt == now && report.complianceValue == "PASSED" && report.lastTransportUpdateAt == now,
               "licensing projection leaves compliance and Jamf contact unchanged")
    }

    private static func integrationIfConfigured() async throws {
        guard let server = ProcessInfo.processInfo.environment["NOTARY_LICENSING_TEST_SERVER"],
              let adminToken = ProcessInfo.processInfo.environment["NOTARY_LICENSING_TEST_ADMIN_TOKEN"] else { return }
        guard let url = URL(string: server), url.host == "127.0.0.1", url.scheme == "http" else {
            fatalError("Licensing integration tests require an isolated loopback server")
        }
        let fixture = try Fixture(serverURL: url, useNetwork: true)
        defer { fixture.cleanup() }
        func admin(_ path: String, method: String, body: [String: Any]) async throws {
            var request = URLRequest(url: url.appendingPathComponent("api/v1/admin/licenses" + path))
            request.httpMethod = method
            request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            expect((response as? HTTPURLResponse)?.statusCode == 200, "isolated admin fixture operation")
        }
        try await admin("", method: "POST", body: [
            "activationCode": code, "productId": "NOTX", "customerName": "Notary Integration Test",
            "validUntil": "2027-10-08", "allowedDevices": 3,
            "features": ["transporter": true, "reporter": true, "configurator": true]
        ])
        let first = await fixture.checkIn()
        if case .tokenUpdated = first {} else { expect(false, "real server signed token accepted by Notary") }
        expect(fixture.authorization().allowsTransporter, "real token enables transporter")
        let current = await fixture.checkIn()
        expect(current == .tokenCurrent, "real server confirms actual persisted revision with 304")
        try await admin("/\(code)", method: "PUT", body: ["features": ["transporter": false, "reporter": true, "configurator": false]])
        _ = await fixture.checkIn()
        expect(!fixture.authorization().allowsTransporter && fixture.authorization().allowsReporter, "server feature change takes effect")
        try await admin("/\(code)", method: "PUT", body: ["disabled": true])
        let rejected = await fixture.checkIn()
        expect(rejected == .licenseRejected("license_disabled"), "real server rejection persisted")
        expect(!fixture.authorization().isAuthorized, "real server denial blocks cached capabilities")
        try await admin("/\(code)", method: "PUT", body: ["disabled": false])
        _ = await fixture.checkIn()
        expect(fixture.authorization().allowsReporter, "server reactivation restores validated token features")
        print("Notary licensing Docker integration passed")
    }

    private static func requestBody(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        do {
            if try !condition() { fatalError("Licensing test failed: \(message)") }
        } catch { fatalError("Licensing test failed: \(message): \(error)") }
    }
}
