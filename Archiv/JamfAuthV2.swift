import Foundation

struct OAuthTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

actor JamfAuth {

    private let logger: HardenLogger
    private let http: HTTPClient
    private let baseURL: URL

    private var bearerToken: String = ""
    private var bearerExpirationEpoch: Int = 0  // unix seconds

    // ✅ Guard: if non-nil, a refresh is already in flight
    private var refreshTask: Task<String?, Never>?

    init(logger: HardenLogger, http: HTTPClient, baseURL: URL) {
        self.logger = logger
        self.http = http
        self.baseURL = baseURL
    }

    private func tokenExpired(now: Int) -> Bool {
        bearerToken.isEmpty || bearerExpirationEpoch <= now
    }

    private func getBearerToken(clientID: String, clientSecret: String) async -> String? {
        let tokenURL = baseURL.appendingPathComponent("api/oauth/token")
        let form = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"

        // Token endpoint: give it a bit more time than “normal” requests
        let resp = await http.requestForm(url: tokenURL, method: "POST", form: form, headers: [:])

        guard http.requireSuccess(resp, context: "getBearerToken", logBodyOnError: true) else {
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: resp.body)
            bearerToken = decoded.access_token

            let now = Int(Date().timeIntervalSince1970)
            bearerExpirationEpoch = now + decoded.expires_in - 3

            logger.develop("Bearer received; exp=\(bearerExpirationEpoch)")
            return bearerToken
        } catch {
            logger.error("Token parse failed: \(error)")
            logger.error("Response Body: \(resp.bodyString)")
            return nil
        }
    }

    /// ✅ Public: returns a valid token. Only one refresh happens at a time.
    func ensureValidToken(clientID: String, clientSecret: String) async -> String? {
        let now = Int(Date().timeIntervalSince1970)

        // Fast path
        if !tokenExpired(now: now) {
            return bearerToken
        }

        // If refresh is already happening, await it
        if let task = refreshTask {
            return await task.value
        }

        // Start exactly one refresh task
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.getBearerToken(clientID: clientID, clientSecret: clientSecret)
        }
        refreshTask = task

        let newToken = await task.value
        refreshTask = nil
        return newToken
    }

    /// ✅ Called after a 401 to force refresh on next request
    func markTokenInvalid() {
        bearerToken = ""
        bearerExpirationEpoch = 0
    }

    /// Optional: explicit invalidate endpoint (not strictly required for client_credentials flow)
    func invalidateToken() async {
        guard !bearerToken.isEmpty else { return }

        let url = baseURL.appendingPathComponent("api/v1/auth/invalidate-token")
        let headers = ["Authorization": "Bearer \(bearerToken)"]

        let resp = await http.request(url: url, method: "POST", headers: headers)
        _ = http.requireSuccess(resp, context: "invalidateToken", logBodyOnError: false)

        bearerToken = ""
        bearerExpirationEpoch = 0
    }
}
