import AppTokenKit
import Foundation

package struct NotaryLicenseCacheState: Codable {
    package var activationCode: String
    package var tokenId: String?
    package var tokenVersion: Int?
    package var serverManaged: Bool
    package var rejectionReason: String?
}

package struct NotaryLicenseCacheSnapshot {
    package let token: String?
    package let state: NotaryLicenseCacheState?
}

package struct NotaryLicenseCache {
    package static let stateKey = "appTokenCache"
    package static let preservedKeys: Set<String> = ["apptoken", NotaryActivationCode.key, stateKey]
    private let store: SecurePlistStore<RunnerState>

    package init(store: SecurePlistStore<RunnerState> = SecurePlistStore<RunnerState>(preservedExternalKeys: Self.preservedKeys)) {
        self.store = store
    }

    package func load() throws -> NotaryLicenseCacheSnapshot {
        let values = try store.readValues(keys: ["apptoken", Self.stateKey])
        var state: NotaryLicenseCacheState?
        if let dictionary = values[Self.stateKey] {
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
            state = try PropertyListDecoder().decode(NotaryLicenseCacheState.self, from: data)
        }
        return NotaryLicenseCacheSnapshot(token: values["apptoken"] as? String, state: state)
    }

    package func storeToken(_ token: String, activationCode: String, tokenId: String, tokenVersion: Int) throws {
        let state = NotaryLicenseCacheState(activationCode: activationCode, tokenId: tokenId,
                                           tokenVersion: tokenVersion, serverManaged: true, rejectionReason: nil)
        try store.merge(values: ["apptoken": token, Self.stateKey: try encoded(state)])
    }

    package func recordRejection(activationCode: String, reason: String) throws {
        let snapshot = try load()
        var state = snapshot.state?.activationCode == activationCode ? snapshot.state! :
            NotaryLicenseCacheState(activationCode: activationCode, tokenId: nil, tokenVersion: nil,
                                    serverManaged: true, rejectionReason: nil)
        state.serverManaged = true
        state.rejectionReason = reason
        try store.merge(values: [Self.stateKey: try encoded(state)])
    }

    package func seedManagedToken(candidate: TokenCandidate?, authorization: NotaryAppTokenAuthorization,
                                  activationCode: String?) throws {
        guard let candidate, candidate.source != .localSecureStorage, authorization.isAuthorized else { return }
        let snapshot = try load()
        if snapshot.state?.serverManaged == true { return }
        if snapshot.token == candidate.token { return }
        // Bootstrap the cache without extracting or persisting an activation code.
        try store.merge(values: ["apptoken": candidate.token])
    }

    private func encoded(_ state: NotaryLicenseCacheState) throws -> Any {
        let data = try PropertyListEncoder().encode(state)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}
