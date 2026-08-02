import AppTokenKit
import Foundation
import NotaryCore
import NotaryTransportImplementation

@main
enum TransportRegressionTests {
    static func main() async {
        await publicDummyReportsUnavailableWithoutNetwork()
        await transportAvailabilityMatchesBuildMode()
        capabilityGateBlocksMissingTransporterFeature()
        capabilityGateAllowsTransporterFeature()
        securePlistStorePreservesAppToken()
        print("Transport regression tests passed")
    }

    static func publicDummyReportsUnavailableWithoutNetwork() async {
        guard NotaryTransport.availability == .publicDummy else {
            return
        }
        let result = await NotaryTransport.makeService().perform(makeRequest(shouldTransport: true))
        expect(result.status == .implementationUnavailable, "public dummy status")
        expect(result.availability == .publicDummy, "public dummy availability")
        expect(result.didAttemptNetwork == false, "public dummy does not attempt network")
        expect(result.didRemoteUpdate == false, "public dummy does not report success")
        expect(result.logMessages.contains { $0.localizedCaseInsensitiveContains("public build") }, "public dummy explains unavailable implementation")
    }

    static func transportAvailabilityMatchesBuildMode() async {
        switch NotaryTransport.availability {
        case .publicDummy:
            let result = await NotaryTransport.makeService().perform(makeRequest(shouldTransport: true))
            expect(result.status == .implementationUnavailable, "public build uses unavailable dummy")
        case .confidential:
            let result = await NotaryTransport.makeService().perform(makeRequest(shouldTransport: false))
            expect(result.status == .skipped, "confidential build can be invoked through shared contract")
            expect(result.didAttemptNetwork == false, "confidential skipped request does not attempt network")
        }
    }

    static func capabilityGateBlocksMissingTransporterFeature() {
        let diagnostics = TokenDiagnostics(status: .valid, capabilities: [])
        let authorization = NotaryAppTokenAuthorization(diagnostics: diagnostics)
        expect(authorization.allowsTransporter == false, "missing capability blocks transport")
    }

    static func capabilityGateAllowsTransporterFeature() {
        let diagnostics = TokenDiagnostics(status: .valid, capabilities: [AppTokenDefaults.feature])
        let authorization = NotaryAppTokenAuthorization(diagnostics: diagnostics)
        expect(authorization.allowsTransporter == true, "transporter capability allows transport")
    }

    static func securePlistStorePreservesAppToken() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("notary-store-\(UUID().uuidString)", isDirectory: true)
        let plist = root.appendingPathComponent("notary.plist", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let existing: [String: Any] = [
                "apptoken": "TAT1.test-token",
                "lastRunOK": true
            ]
            let existingData = try PropertyListSerialization.data(fromPropertyList: existing, format: .binary, options: 0)
            try existingData.write(to: plist)

            let store = SecurePlistStore<RunnerState>(
                preservedExternalKeys: ["apptoken"],
                rootURL: plist,
                tmpURL: plist
            )
            var state = RunnerState()
            state.lastRunOK = false
            try store.save(state)

            let savedData = try Data(contentsOf: plist)
            let saved = try PropertyListSerialization.propertyList(from: savedData, options: [], format: nil) as? [String: Any]
            expect(saved?["apptoken"] as? String == "TAT1.test-token", "secure store preserves external app token")
            expect(saved?["lastRunOK"] as? Bool == false, "secure store still updates runner state")
        } catch {
            fputs("Test failed: secure store preservation threw \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func makeRequest(shouldTransport: Bool) -> TransportRequest {
        TransportRequest(
            shouldTransport: shouldTransport,
            serialNumber: "TESTSERIAL",
            baseURL: URL(string: "https://127.0.0.1.invalid"),
            credentials: TransportCredentials(clientID: "client", clientSecret: "secret"),
            cachedComputerID: nil,
            bearerToken: nil,
            bearerExpirationEpoch: nil,
            eaState: TransportEAState(
                definitionIDs: [:],
                cacheUpdatedAt: nil,
                refreshAttemptedAt: nil,
                refreshFailCount: 0
            ),
            proofValues: TransportProofValues(
                runner: "OK",
                issues: "EMPTY",
                compliance: "PASSED",
                percent: nil,
                connection: nil
            )
        )
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Test failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}
