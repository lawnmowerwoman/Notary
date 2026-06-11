import Foundation

// MARK: - Types

package typealias JamfCredentialsProvider = @Sendable () -> (clientID: String, clientSecret: String)

struct OAuthTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

// MARK: - JamfAuth (Token Refresh Guard)

/// Actor ensures token state is concurrency-safe and that only one refresh runs at a time.
package actor JamfAuth {

    private let logger: HardenLogger
    private let http: HTTPClient
    private let baseURL: URL
    private let credentials: JamfCredentialsProvider

    // Token state
    private var bearerToken: String = ""
    private var bearerExpirationEpoch: Int = 0 // unix seconds

    // Refresh guard: while non-nil, refresh is in flight
    private var refreshTask: Task<String?, Never>?

    // Small skew to avoid edge-expiry during request
    private let expirySkewSeconds: Int = 3

    package init(
        logger: HardenLogger,
        http: HTTPClient,
        baseURL: URL,
        credentials: @escaping JamfCredentialsProvider,
        initialBearerToken: String? = nil,
        initialBearerExpirationEpoch: Int? = nil
    ) {
        self.logger = logger
        self.http = http
        self.baseURL = baseURL
        self.credentials = credentials
        self.bearerToken = initialBearerToken ?? ""
        self.bearerExpirationEpoch = initialBearerExpirationEpoch ?? 0
    }

    // MARK: - Public API

    /// Returns a valid bearer token. Performs a guarded refresh when needed.
    package func ensureValidToken() async -> String? {
        let now = Int(Date().timeIntervalSince1970)

        // Fast path
        if !bearerToken.isEmpty, bearerExpirationEpoch > now {
            return bearerToken
        }

        // If a refresh is already running, await it
        if let task = refreshTask {
            return await task.value
        }

        // Start exactly one refresh
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchBearerToken()
        }
        refreshTask = task

        let token = await task.value
        refreshTask = nil
        return token
    }

    /// Call this when a request returns 401 to force refresh on next call.
    package func markTokenInvalid() {
        bearerToken = ""
        bearerExpirationEpoch = 0
    }

    package func persistedTokenState() -> (token: String?, expirationEpoch: Int?) {
        guard !bearerToken.isEmpty, bearerExpirationEpoch > 0 else {
            return (nil, nil)
        }
        // Persist the still-valid bearer token between cycles so routine EA
        // transports do not have to hit Jamf Pro's token endpoint every time.
        // This was added after Jamf Pro database timeout storms: reducing auth
        // churn makes Notary less likely to amplify a busy or recovering server.
        return (bearerToken, bearerExpirationEpoch)
    }

    /// Optional explicit invalidate-token endpoint call.
    /// Not strictly required for client_credentials, but keeps behavior consistent.
    package func invalidateToken() async {
        guard !bearerToken.isEmpty else { return }

        let url = baseURL.appendingPathComponent("api/v1/auth/invalidate-token")
        let headers = ["Authorization": "Bearer \(bearerToken)"]

        let resp = await http.request(url: url, method: "POST", headers: headers)
        _ = http.requireSuccess(resp, context: "invalidateToken", logBodyOnError: false)

        bearerToken = ""
        bearerExpirationEpoch = 0
    }

    // MARK: - Internal

    private func fetchBearerToken() async -> String? {
        let creds = credentials()
        if creds.clientID.isEmpty || creds.clientSecret.isEmpty {
            logger.error("JamfAuth: credentials provider returned empty clientID/secret")
            return nil
        }

        let tokenURL = baseURL.appendingPathComponent("api/oauth/token")

        // NOTE: For correctness, values should be URL-encoded.
        // If your IDs/secrets might contain special chars, we can add urlEncode() later.
        let form = "grant_type=client_credentials&client_id=\(creds.clientID)&client_secret=\(creds.clientSecret)"

        let resp = await http.requestForm(url: tokenURL, method: "POST", form: form)

        guard http.requireSuccess(resp, context: "getBearerToken", logBodyOnError: true) else {
            // Keep state empty on failure
            bearerToken = ""
            bearerExpirationEpoch = 0
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: resp.body)

            bearerToken = decoded.access_token

            let now = Int(Date().timeIntervalSince1970)
            bearerExpirationEpoch = now + decoded.expires_in - expirySkewSeconds

            logger.develop("Bearer received; exp=\(bearerExpirationEpoch)")
            return bearerToken
        } catch {
            logger.error("Token parse failed: \(error)")
            logger.error("Response Body: \(resp.bodyString)")

            bearerToken = ""
            bearerExpirationEpoch = 0
            return nil
        }
    }
}
