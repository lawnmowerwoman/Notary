import Foundation

// MARK: - Models

struct EADefinition: Decodable {
    let id: IntOrString
    let name: String
}

struct EAListResponse: Decodable {
    let totalCount: Int?
    let results: [EADefinition]
}


// MARK: - JamfEAHandler

package final class JamfEAHandler: @unchecked Sendable {

    private let logger: HardenLogger
    private let http: HTTPClient
    private let baseURL: URL
    private let auth: JamfAuth

    private let pageSize = 200

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    package init(logger: HardenLogger, http: HTTPClient, baseURL: URL, auth: JamfAuth) {
        self.logger = logger
        self.http = http
        self.baseURL = baseURL
        self.auth = auth
    }

    // MARK: - Internal bearer helper

    private func requestWithBearer(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        oneRetryOn401: Bool = true
    ) async -> HTTPResponse {

        guard let token = await auth.ensureValidToken() else {
            logger.error("JamfEA: failed to obtain bearer token")
            return HTTPResponse(statusCode: 0, body: Data(), errorDescription: "no bearer token")
        }

        var h = headers
        h["Authorization"] = "Bearer \(token)"

        var resp = await http.request(url: url, method: method, headers: h, body: body)

        if oneRetryOn401, resp.statusCode == 401 {
            logger.develop("JamfEA: 401 → invalidating token and retrying once")
            await auth.markTokenInvalid()

            guard let token2 = await auth.ensureValidToken() else {
                logger.error("JamfEA: token refresh failed after 401")
                return resp
            }

            h["Authorization"] = "Bearer \(token2)"
            resp = await http.request(url: url, method: method, headers: h, body: body)
        }

        return resp
    }

    // MARK: - Public API

    /// Fetch all EA definitions. Returns (defs, ok).
    /// ok=false means the fetch failed at some point (HTTP or decode).
    func fetchAllEADefinitions() async -> (defs: [EADefinition], ok: Bool) {
        var page = 0
        var all: [EADefinition] = []
        var expectedTotal: Int? = nil

        while true {
            // Prefer URLComponents over string interpolation
            var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/computer-extension-attributes"),
                                      resolvingAgainstBaseURL: false)
            comps?.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page-size", value: "\(pageSize)"),
                URLQueryItem(name: "sort", value: "name.asc")
            ]

            guard let url = comps?.url else {
                logger.error("JamfEA: failed to build EA list URL")
                return (all, false)
            }

            let headers = ["Accept": "application/json"]

            let resp = await requestWithBearer(url: url, method: "GET", headers: headers)
            guard http.requireSuccess(resp, context: "listEAs(page=\(page))", logBodyOnError: true) else {
                return (all, false)
            }

            do {
                let decoded = try decoder.decode(EAListResponse.self, from: resp.body)
                all.append(contentsOf: decoded.results)

                if expectedTotal == nil, let total = decoded.totalCount {
                    expectedTotal = total
                }

                if let total = expectedTotal, all.count >= total { break }
                if decoded.results.isEmpty { break }
                if decoded.results.count < pageSize { break }

                page += 1
            } catch {
                logger.error("EA list parse failed: \(error)")
                logger.error("Response Body: \(resp.bodyString)")
                return (all, false)
            }
        }

        logger.develop("EA definitions loaded: \(all.count)")
        return (all, true)
    }

    func listAllEADefinitions() async -> [EADefinition] {
        let (defs, ok) = await fetchAllEADefinitions()
        return ok ? defs : defs
    }

    func findEADefinitionIDs(names: [String]) async -> [String: Int] {
        let defs = await listAllEADefinitions()

        let defsByName: [String: Int] =
            Dictionary(uniqueKeysWithValues: defs.map { ($0.name, $0.id.value) })

        var out: [String: Int] = [:]
        for n in names {
            if let id = defsByName[n] {
                out[n] = id
            } else {
                logger.warn("EA definition not found: \(n)")
            }
        }
        return out
    }

    package func updateEA(computerID: Int, definitionID: Int, value: String) async -> Bool {
        let url = baseURL.appendingPathComponent("api/v1/computers-inventory-detail/\(computerID)")

        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        struct EAPatchBody: Encodable {
            struct EAItem: Encodable {
                let definitionId: Int
                let values: [String]
            }
            let extensionAttributes: [EAItem]
        }

        let bodyObj = EAPatchBody(extensionAttributes: [
            .init(definitionId: definitionID, values: [value])
        ])

        let body = (try? encoder.encode(bodyObj)) ?? Data()

        let resp = await requestWithBearer(url: url, method: "PATCH", headers: headers, body: body)

        if (200...299).contains(resp.statusCode) {
            logger.info("EA updated (HTTP \(resp.statusCode)): defId=\(definitionID), computerID=\(computerID)")
            return true
        }

        logger.error("EA update failed (HTTP \(resp.statusCode)): defId=\(definitionID), computerID=\(computerID)")
        _ = http.requireSuccess(resp, context: "updateEA(defId=\(definitionID))", logBodyOnError: true)
        return false
    }

    /// Cache-first resolve with daily stale refresh, plus cooldown to avoid hammering Jamf when it’s unhealthy.
    package func resolveEADefinitionIDs(
        names: [String],
        cache: [String: Int],
        cacheUpdatedAt: Date?,
        refreshAttemptedAt: Date?,
        refreshFailCount: Int,
        staleAfter: TimeInterval = 24 * 60 * 60,
        cooldown: TimeInterval = 60 * 60
    ) async -> (
        ids: [String: Int],
        newCache: [String: Int],
        newCacheUpdatedAt: Date?,
        newAttemptedAt: Date?,
        newFailCount: Int,
        didAttempt: Bool,
        didUpdate: Bool
    ) {

        let now = Date()

        // 1) Resolve from cache
        var ids: [String: Int] = [:]
        var missing: [String] = []
        for n in names {
            if let cached = cache[n] { ids[n] = cached }
            else { missing.append(n) }
        }

        // 2) Decide if stale
        let isStale: Bool = {
            guard let ts = cacheUpdatedAt else { return true }
            return now.timeIntervalSince(ts) >= staleAfter
        }()

        // 3) Cooldown check
        let inCooldown: Bool = {
            guard let lastAttempt = refreshAttemptedAt else { return false }
            return now.timeIntervalSince(lastAttempt) < cooldown
        }()

        let shouldRefresh = (isStale || !missing.isEmpty) && !inCooldown
        if !shouldRefresh {
            return (ids, cache, cacheUpdatedAt, refreshAttemptedAt, refreshFailCount, false, false)
        }

        // 4) Attempt refresh
        let (defs, ok) = await fetchAllEADefinitions()

        if ok {
            var newCache = cache
            for d in defs { newCache[d.name] = d.id.value }

            var newIDs: [String: Int] = [:]
            for n in names {
                if let id = newCache[n] { newIDs[n] = id }
            }

            return (
                newIDs,
                newCache,
                now,
                now,
                0,
                true,
                true
            )
        } else {
            return (
                ids,
                cache,
                cacheUpdatedAt,
                now,
                refreshFailCount + 1,
                true,
                false
            )
        }
    }
}
