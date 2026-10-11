import AppTokenKit
import Foundation
import NotaryCore
import NotaryTransportImplementation

@main
enum TransportRegressionTests {
    static func main() async {
        CheckExecutionPolicyTests.run()
        HardwareInfoTests.run()
        SecurePlistProtectionTests.run()
        await publicDummyReportsUnavailableWithoutNetwork()
        await transportAvailabilityMatchesBuildMode()
        capabilityGateBlocksMissingTransporterFeature()
        capabilityGateAllowsTransporterFeature()
        reporterAndConfiguratorCapabilitiesAreIndependent()
        securePlistStorePreservesAppToken()
        securePlistStoreMergesAppToken()
        activationCodeResolutionIgnoresTokenPayloadForBeta()
        do { try await LicensingRegressionTests.run() }
        catch { fatalError("Licensing regression tests failed: \(error)") }
        machineIdentifierIsStableSaltedHash()
        xprotectCheckSkipsOnAffectedMacOS27Builds()
        xprotectCheckDoesNotAutoSkipBeforeMacOS27()
        xprotectCheckDoesNotAutoSkipOnMacOS272()
        lastContactTimestampUsesUTCISO8601Format()
        successfulTransportRecordsLastContactTimestamp()
        failedTransportDoesNotAdvanceLastContactTimestamp()
        laterSuccessfulTransportAdvancesLastContactTimestamp()
        localEvaluationDoesNotModifyLastContactTimestamp()
        lastContactTimestampSurvivesStateReload()
        transportProofValuesPreserveExistingComplianceFields()
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

    static func reporterAndConfiguratorCapabilitiesAreIndependent() {
        let diagnostics = TokenDiagnostics(
            status: .valid,
            capabilities: [
                AppTokenDefaults.reporterFeature,
                AppTokenDefaults.configuratorFeature,
            ]
        )
        let authorization = NotaryAppTokenAuthorization(diagnostics: diagnostics)
        expect(authorization.allowsTransporter == false, "reporter/configurator do not imply transport")
        expect(authorization.allowsReporter == true, "reporter capability allows reporter")
        expect(authorization.allowsConfigurator == true, "configurator capability allows configurator")
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
                "activationCode": "NOTXTEST123",
                "lastRunOK": true
            ]
            let existingData = try PropertyListSerialization.data(fromPropertyList: existing, format: .binary, options: 0)
            try existingData.write(to: plist)

            let store = SecurePlistStore<RunnerState>(
                preservedExternalKeys: ["apptoken", NotaryActivationCode.key],
                rootURL: plist,
                tmpURL: plist
            )
            var state = RunnerState()
            state.lastRunOK = false
            try store.save(state)

            let savedData = try Data(contentsOf: plist)
            let saved = try PropertyListSerialization.propertyList(from: savedData, options: [], format: nil) as? [String: Any]
            expect(saved?["apptoken"] as? String == "TAT1.test-token", "secure store preserves external app token")
            expect(saved?["activationCode"] as? String == "NOTXTEST123", "secure store preserves external activation code")
            expect(saved?["lastRunOK"] as? Bool == false, "secure store still updates runner state")
        } catch {
            fputs("Test failed: secure store preservation threw \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func securePlistStoreMergesAppToken() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("notary-store-merge-\(UUID().uuidString)", isDirectory: true)
        let plist = root.appendingPathComponent("notary.plist", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = SecurePlistStore<RunnerState>(
                preservedExternalKeys: ["apptoken", NotaryActivationCode.key],
                rootURL: plist,
                tmpURL: plist
            )
            var state = RunnerState()
            state.activationCode = "NOTXCONFIGURED"
            try store.save(state)
            try store.merge(values: ["apptoken": "TAT1.server-token"])

            let savedData = try Data(contentsOf: plist)
            let saved = try PropertyListSerialization.propertyList(from: savedData, options: [], format: nil) as? [String: Any]
            expect(saved?["apptoken"] as? String == "TAT1.server-token", "secure store merges fetched app token")
            expect(saved?["activationCode"] as? String == "NOTXCONFIGURED", "secure store merge preserves activation code")
        } catch {
            fputs("Test failed: secure store merge threw \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func activationCodeResolutionIgnoresTokenPayloadForBeta() {
        let diagnostics = TokenDiagnostics(
            status: .valid,
            payload: AppTokenPayload(
                issuer: AppTokenDefaults.issuer,
                productId: AppTokenDefaults.productId,
                tokenId: "token",
                activationCode: "NOTXTOKENONLY",
                customerName: "Token Only",
                validUntil: "2027-01-01",
                features: AppTokenDefaults.notaryFeatures
            )
        )
        let authorization = NotaryAppTokenAuthorization(diagnostics: diagnostics)
        let resolved = NotaryActivationCode.resolved(
            rawSnapshot: [:],
            state: RunnerState()
        )

        expect(authorization.diagnostics.payload?.activationCode == "NOTXTOKENONLY", "fixture token carries activation code")
        expect(resolved == nil, "beta activation code resolution does not persist token-derived code")
    }

    static func machineIdentifierIsStableSaltedHash() {
        let rawUUID = "A1B2C3D4-E5F6-47A8-9B0C-D1E2F3A4B5C6"
        let first = NotaryMachineIdentity.identifier(forIOPlatformUUID: rawUUID)
        let second = NotaryMachineIdentity.identifier(forIOPlatformUUID: rawUUID.lowercased())

        expect(first == second, "machine identifier normalizes IOPlatformUUID case")
        expect(first?.count == 64, "machine identifier is a SHA-256 hex digest")
        expect(first != rawUUID, "machine identifier never exposes raw IOPlatformUUID")
        expect(first != HardwareInfo.serialNumber(), "machine identifier is not derived from the serial number")
    }

    static func xprotectCheckSkipsOnAffectedMacOS27Builds() {
        let result = checkXProtectCLI(osVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        expect(result.status == .skipped, "xprotect check is skipped on affected macOS 27 builds")
        expect(result.details.localizedCaseInsensitiveContains("27.0/27.1"), "xprotect skip explains affected macOS 27 builds")
    }

    static func xprotectCheckDoesNotAutoSkipBeforeMacOS27() {
        expect(
            shouldSkipXProtectCLI(osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)) == false,
            "xprotect check is not force-skipped before macOS 27"
        )
    }

    static func xprotectCheckDoesNotAutoSkipOnMacOS272() {
        expect(
            shouldSkipXProtectCLI(osVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)) == false,
            "xprotect check is restored on macOS 27.2"
        )
    }

    static func lastContactTimestampUsesUTCISO8601Format() {
        let date = Date(timeIntervalSince1970: 1_789_978_671)
        let value = TransportTimestampFormat.extensionAttributeValue(for: date)
        expect(value == "2026-09-21T08:17:51Z", "last contact timestamp is deterministic UTC ISO 8601")
    }

    static func successfulTransportRecordsLastContactTimestamp() {
        let date = Date(timeIntervalSince1970: 1_789_978_671)
        let proof = makeProof(generatedAt: date)
        var state = RunnerState()

        Transporter.applyTransportOutcome(
            didCompleteTransport: true,
            proof: proof,
            state: &state,
            at: date,
            reportPercent: false
        )

        expect(state.lastTransportUpdateAt == date, "successful transport records last contact date")
        expect(
            TransportTimestampFormat.extensionAttributeValue(for: state.lastTransportUpdateAt ?? .distantPast) == "2026-09-21T08:17:51Z",
            "successful transport date formats as the Jamf last contact value"
        )
    }

    static func failedTransportDoesNotAdvanceLastContactTimestamp() {
        let previous = Date(timeIntervalSince1970: 1_789_900_000)
        let attempted = Date(timeIntervalSince1970: 1_789_978_671)
        let proof = makeProof(generatedAt: attempted)
        var state = RunnerState()
        state.lastTransportUpdateAt = previous

        Transporter.applyTransportOutcome(
            didCompleteTransport: false,
            proof: proof,
            state: &state,
            at: attempted,
            reportPercent: false
        )

        expect(state.lastTransportUpdateAt == previous, "failed transport keeps previous last contact date")
    }

    static func laterSuccessfulTransportAdvancesLastContactTimestamp() {
        let first = Date(timeIntervalSince1970: 1_789_900_000)
        let later = Date(timeIntervalSince1970: 1_789_978_671)
        let proof = makeProof(generatedAt: later)
        var state = RunnerState()
        state.lastTransportUpdateAt = first

        Transporter.applyTransportOutcome(
            didCompleteTransport: true,
            proof: proof,
            state: &state,
            at: later,
            reportPercent: false
        )

        expect(state.lastTransportUpdateAt == later, "later successful transport advances last contact date")
    }

    static func localEvaluationDoesNotModifyLastContactTimestamp() {
        let previous = Date(timeIntervalSince1970: 1_789_900_000)
        let evaluatedAt = Date(timeIntervalSince1970: 1_789_978_671)
        let proof = makeProof(generatedAt: evaluatedAt)
        var state = RunnerState()
        state.lastTransportUpdateAt = previous

        _ = Transporter.decide(
            proof: proof,
            state: state,
            at: evaluatedAt,
            heartbeatInterval: 60 * 60,
            reportPercent: false
        )

        expect(state.lastTransportUpdateAt == previous, "local evaluation and transport decision do not update last contact")
    }

    static func lastContactTimestampSurvivesStateReload() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("notary-last-contact-\(UUID().uuidString)", isDirectory: true)
        let plist = root.appendingPathComponent("notary.plist", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = SecurePlistStore<RunnerState>(
                preservedExternalKeys: ["apptoken", NotaryActivationCode.key],
                rootURL: plist,
                tmpURL: plist
            )
            var state = RunnerState()
            state.lastTransportUpdateAt = Date(timeIntervalSince1970: 1_789_978_671)
            try store.save(state)

            let reloaded = try store.load()
            expect(reloaded?.lastTransportUpdateAt == state.lastTransportUpdateAt, "last contact survives persisted state reload")
        } catch {
            fputs("Test failed: last contact persistence threw \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func transportProofValuesPreserveExistingComplianceFields() {
        let request = makeRequest(shouldTransport: true)

        expect(request.proofValues.runner == "OK", "runner proof value remains unchanged")
        expect(request.proofValues.issues == "EMPTY", "issues proof value remains unchanged")
        expect(request.proofValues.compliance == "PASSED", "compliance proof value remains unchanged")
        expect(request.proofValues.lastContact == "2026-09-21T08:17:51Z", "last contact proof value is additive")
    }

    static func makeProof(generatedAt: Date) -> NotaryProof {
        NotaryProof(
            generatedAt: generatedAt,
            passedCount: 1,
            failedCount: 0,
            unknownCount: 0,
            timedOutCount: 0,
            skippedCount: 0,
            hardFailCount: 0,
            compliancePercent: 100,
            issueNames: []
        )
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
                connection: nil,
                lastContact: "2026-09-21T08:17:51Z"
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
