import AppTokenKit
import Foundation

package enum NotaryLicenseClientResult: Equatable {
    case tokenUpdated(tokenId: String, tokenVersion: Int, validUntil: String)
    case tokenCurrent
    case activationCodeUnknown
    case licenseRejected(String)
    case skipped(String)
    case failed(String)
}

package struct NotaryLicenseClient {
    package static let defaultServerURL = URL(string: "https://license.ministryofcode.de")!

    private let serverURL: URL
    private let session: URLSession
    private let cache: NotaryLicenseCache
    private let publicKeys: PublicKeyRegistry
    private let now: () -> Date

    package init(
        serverURL: URL = Self.defaultServerURL,
        session: URLSession = Self.defaultSession,
        cache: NotaryLicenseCache = NotaryLicenseCache(),
        publicKeys: PublicKeyRegistry = AppTokenEmbeddedPublicKeys.registry,
        now: @escaping () -> Date = Date.init
    ) {
        self.serverURL = serverURL
        self.session = session
        self.cache = cache
        self.publicKeys = publicKeys
        self.now = now
    }

    package static let defaultSession = URLSession(configuration: .ephemeral, delegate: LicensingNoRedirects(), delegateQueue: nil)

    package func checkIn(
        activationCode: String,
        machineIdentifier: String,
        currentAuthorization: NotaryAppTokenAuthorization,
        notaryVersion: String
    ) async -> NotaryLicenseClientResult {
        guard let endpoint = endpointURL(path: "/api/v1/devices/check-in") else {
            return .failed("invalid licensing server URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var payload: [String: Any] = [
            "activationCode": activationCode,
            "machineIdentifier": machineIdentifier,
            "notaryVersion": notaryVersion
        ]
        if currentAuthorization.isAuthorized,
           currentAuthorization.diagnostics.payload?.activationCode == activationCode,
           let payloadTokenId = currentAuthorization.diagnostics.payload?.tokenId,
           let snapshot = try? cache.load(),
           let state = snapshot.state, state.activationCode == activationCode,
           state.tokenId == payloadTokenId, state.rejectionReason == nil,
           let version = state.tokenVersion, version > 0 {
            payload["currentTokenId"] = payloadTokenId
            payload["currentTokenVersion"] = version
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("non-http response")
            }

            switch http.statusCode {
            case 200:
                return try handleTokenResponse(data, activationCode: activationCode)
            case 304:
                guard payload["currentTokenVersion"] != nil else { return .failed("unexpected_not_modified") }
                return .tokenCurrent
            case 404:
                guard errorCode(from: data) == "activation_code_unknown" else { return .failed("http_404") }
                try? cache.recordRejection(activationCode: activationCode, reason: "activation_code_unknown")
                return .activationCodeUnknown
            case 403:
                guard let reason = errorCode(from: data), ["license_disabled", "license_not_valid"].contains(reason) else {
                    return .failed("http_403")
                }
                do { try cache.recordRejection(activationCode: activationCode, reason: reason) }
                catch { return .licenseRejected("\(reason); local rejection persistence failed") }
                return .licenseRejected(reason)
            default:
                return .failed("http_\(http.statusCode)")
            }
        } catch let error as URLError {
            return .failed("network_error_\(error.code.rawValue)")
        } catch {
            return .failed("invalid_or_unpersisted_token_response")
        }
    }

    private func handleTokenResponse(_ data: Data, activationCode: String) throws -> NotaryLicenseClientResult {
        let response = try JSONDecoder().decode(LicensingTokenResponse.self, from: data)
        guard response.tokenVersion > 0 else {
            return .failed("invalid token response")
        }

        let diagnostics = AppTokenValidator(
            publicKeys: publicKeys,
            productPolicy: AppTokenDefaults.notaryProductPolicy,
            featureRegistry: AppTokenDefaults.notaryFeatureRegistry,
            now: now()
        ).validate(response.appToken, source: .localSecureStorage)
        guard diagnostics.status == .valid else {
            return .failed("invalid_app_token")
        }
        guard let signed = diagnostics.payload,
              signed.activationCode == activationCode,
              signed.tokenId == response.tokenId,
              signed.productId == response.productId,
              signed.validUntil == response.validUntil else { return .failed("token_response_mismatch") }
        if let old = try cache.load().state, old.activationCode == activationCode,
           let version = old.tokenVersion, response.tokenVersion < version {
            return .failed("token_version_rollback")
        }

        try cache.storeToken(response.appToken, activationCode: activationCode,
                             tokenId: response.tokenId, tokenVersion: response.tokenVersion)

        return .tokenUpdated(
            tokenId: response.tokenId,
            tokenVersion: response.tokenVersion,
            validUntil: response.validUntil
        )
    }

    private func errorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }

    private func endpointURL(path: String) -> URL? {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}

private struct LicensingTokenResponse: Decodable {
    let appToken: String
    let productId: String
    let tokenId: String
    let tokenVersion: Int
    let validUntil: String
}

private final class LicensingNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
