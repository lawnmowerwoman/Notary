import Foundation

//func env(_ name: String) -> String? {
//  let v = ProcessInfo.processInfo.environment[name]
//  return (v?.isEmpty == false) ? v : nil
//}
// let clientID = env("JAMF_CLIENT_ID") ?? "TEST_CLIENT_ID"
// let clientSecret = env("JAMF_CLIENT_SECRET") ?? "TEST_CLIENT_SECRET"

struct OAuthTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

final class JamfAuth {

    private let logger: HardenLogger
    private let http: HTTPClient
    private let baseURL: URL

    private(set) var bearerToken: String = ""
    private var bearerExpirationEpoch: Int = 0  // unix seconds

    init(logger: HardenLogger, http: HTTPClient, baseURL: URL) {
        self.logger = logger
        self.http = http
        self.baseURL = baseURL
    }

    func getBearerToken(clientID: String, clientSecret: String) async -> String? {
        let tokenURL = baseURL.appendingPathComponent("api/oauth/token")
        let form = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"

        let resp = await http.requestForm(url: tokenURL, method: "POST", form: form)
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

    func ensureValidToken(clientID: String, clientSecret: String) async -> String? {
        let now = Int(Date().timeIntervalSince1970)
        if bearerToken.isEmpty || bearerExpirationEpoch <= now {
            return await getBearerToken(clientID: clientID, clientSecret: clientSecret)
        }
        return bearerToken
    }

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
