import Foundation

package final class JamfAPI: @unchecked Sendable {

    private let logger: HardenLogger
    private let http: HTTPClient
    private let baseURL: URL
    private let auth: JamfAuth

    package init(logger: HardenLogger, http: HTTPClient, baseURL: URL, auth: JamfAuth) {
        self.logger = logger
        self.http = http
        self.baseURL = baseURL
        self.auth = auth
    }

    // MARK: - Internal bearer request helper

    private func requestWithBearer(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        oneRetryOn401: Bool = true
    ) async -> HTTPResponse {

        guard let token = await auth.ensureValidToken() else {
            logger.error("JamfAPI: failed to obtain bearer token")
            return HTTPResponse(statusCode: 0, body: Data(), errorDescription: "no bearer token")
        }

        var h = headers
        h["Authorization"] = "Bearer \(token)"

        var resp = await http.request(url: url, method: method, headers: h, body: body)

        if oneRetryOn401, resp.statusCode == 401 {
            logger.develop("JamfAPI: 401 → invalidating token and retrying once")
            await auth.markTokenInvalid()

            guard let token2 = await auth.ensureValidToken() else {
                logger.error("JamfAPI: token refresh failed after 401")
                return resp
            }

            h["Authorization"] = "Bearer \(token2)"
            resp = await http.request(url: url, method: method, headers: h, body: body)
        }

        return resp
    }

    // MARK: - Jamf Pro API v3 computers-inventory (JSON)

    /// GET /api/v3/computers-inventory?section=GENERAL&page=0&page-size=1&filter=hardware.serialNumber=="SERIAL"
    /// Returns inventory "id" (Jamf computer ID) or nil.
    package func getComputerIDBySerialV3(serial: String) async -> Int? {

        let filterRaw = #"hardware.serialNumber=="\#(serial)""#

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/v3/computers-inventory"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "section", value: "GENERAL"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "1"),
            URLQueryItem(name: "filter", value: filterRaw)
        ]

        guard let url = comps?.url else {
            logger.error("Failed to build computers-inventory URL")
            return nil
        }

        let headers: [String: String] = [
            "Accept": "application/json"
        ]

        let resp = await requestWithBearer(url: url, method: "GET", headers: headers)

        if resp.statusCode == 404 {
            logger.error("computers-inventory endpoint not found (check Jamf version / baseURL)")
            return nil
        }
        if resp.statusCode == 401 {
            // If we still got 401 after the one retry, credentials are likely wrong / not authorized
            logger.error("Unauthorized when fetching Jamf Computer ID (v3 computers-inventory)")
            return nil
        }

        guard http.requireSuccess(resp, context: "getComputerIDBySerialV3(serial=\(serial))", logBodyOnError: true) else {
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(ComputersInventoryResponse.self, from: resp.body)
            guard let id = decoded.results.first?.id.intValue else {
                logger.error("Computer not found in Jamf (serial=\(serial))")
                return nil
            }

            logger.info("Jamf Computer ID: \(id)")
            return id
        } catch {
            logger.error("Failed to decode computers-inventory response: \(error)")
            return nil
        }
    }

    package func listNotaryReportComputers(pageSize: Int = 100) async throws -> [JamfReportComputer] {
        var page = 0
        var all: [JamfReportComputer] = []
        var expectedTotal: Int? = nil
        let safePageSize = max(25, min(pageSize, 200))

        while true {
            // Reporter needs the Notary EAs in the list response for the traffic
            // light, but still loads detail on selection because some Jamf fields
            // are only reliable from computers-inventory-detail.
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("api/v3/computers-inventory"),
                resolvingAgainstBaseURL: false
            )
            comps?.queryItems = [
                URLQueryItem(name: "section", value: "GENERAL"),
                URLQueryItem(name: "section", value: "HARDWARE"),
                URLQueryItem(name: "section", value: "USER_AND_LOCATION"),
                URLQueryItem(name: "section", value: "EXTENSION_ATTRIBUTES"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page-size", value: "\(safePageSize)"),
                URLQueryItem(name: "sort", value: "general.name:asc")
            ]

            guard let url = comps?.url else {
                logger.error("Failed to build computers-inventory URL")
                throw JamfAPIReportError.invalidURL
            }

            let resp = await requestWithBearer(url: url, method: "GET", headers: ["Accept": "application/json"])
            guard resp.isSuccess else {
                _ = http.requireSuccess(resp, context: "listNotaryReportComputers(page=\(page))", logBodyOnError: true)
                throw JamfAPIReportError.requestFailed(statusCode: resp.statusCode, body: resp.bodyString)
            }

            do {
                let decoded = try JSONDecoder().decode(ComputerInventoryListResponse.self, from: resp.body)
                all.append(contentsOf: decoded.results.map(\.reportComputer))

                if expectedTotal == nil {
                    expectedTotal = decoded.totalCount
                }
                if let expectedTotal, all.count >= expectedTotal { break }
                if decoded.results.isEmpty { break }
                if decoded.results.count < safePageSize { break }
                page += 1
            } catch {
                logger.error("Failed to decode computers-inventory list: \(error)")
                logger.error("Response Body: \(resp.bodyString)")
                throw JamfAPIReportError.decodeFailed(error.localizedDescription)
            }
        }

        return all
    }

    package func getNotaryReportComputerDetail(computerID: Int) async -> JamfReportComputerDetail? {
        let url = baseURL.appendingPathComponent("api/v3/computers-inventory-detail/\(computerID)")
        let resp = await requestWithBearer(url: url, method: "GET", headers: ["Accept": "application/json"])
        guard http.requireSuccess(resp, context: "getNotaryReportComputerDetail(id=\(computerID))", logBodyOnError: true) else {
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(ComputerInventoryDetailResponse.self, from: resp.body)
            return decoded.reportDetail
        } catch {
            logger.error("Failed to decode computers-inventory detail: \(error)")
            logger.error("Response Body: \(resp.bodyString)")
            return nil
        }
    }
}

// MARK: - Models

package struct JamfReportComputer: Identifiable, Hashable, Sendable {
    package let id: Int
    package let name: String
    package let serialNumber: String
    package let username: String
    package let model: String
    package let complianceIndicator: String

    package init(id: Int, name: String, serialNumber: String, username: String, model: String, complianceIndicator: String = "") {
        self.id = id
        self.name = name
        self.serialNumber = serialNumber
        self.username = username
        self.model = model
        self.complianceIndicator = complianceIndicator
    }
}

package struct JamfReportComputerDetail: Sendable {
    package let computer: JamfReportComputer
    package let runnerStatus: String
    package let issuesValue: String
    package let complianceValue: String
    package let percentValue: String?

    package var lastTransportValue: String {
        let marker = " – "
        guard let range = runnerStatus.range(of: marker, options: .backwards) else {
            return runnerStatus.isEmpty ? "n/a" : runnerStatus
        }
        return String(runnerStatus[range.upperBound...])
    }

    package init(
        computer: JamfReportComputer,
        runnerStatus: String,
        issuesValue: String,
        complianceValue: String,
        percentValue: String?
    ) {
        self.computer = computer
        self.runnerStatus = runnerStatus
        self.issuesValue = issuesValue
        self.complianceValue = complianceValue
        self.percentValue = percentValue
    }
}

private struct ComputersInventoryResponse: Decodable {
    let results: [ComputersInventoryItem]
}

private struct ComputersInventoryItem: Decodable {
    let id: StringOrInt
}

struct StringOrInt: Decodable {
    let intValue: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let i = try? c.decode(Int.self) {
            intValue = i
            return
        }
        if let s = try? c.decode(String.self),
           let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            intValue = i
            return
        }

        throw DecodingError.typeMismatch(
            Int.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Expected Int or String convertible to Int")
        )
    }
}

private struct ComputerInventoryListResponse: Decodable {
    let totalCount: Int?
    let results: [ComputerInventoryListItem]
}

package enum JamfAPIReportError: LocalizedError {
    case invalidURL
    case requestFailed(statusCode: Int, body: String)
    case decodeFailed(String)

    package var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build the Jamf computers-inventory URL."
        case .requestFailed(let statusCode, let body):
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty {
                return "Jamf computers-inventory request failed with HTTP \(statusCode)."
            }
            return "Jamf computers-inventory request failed with HTTP \(statusCode): \(String(snippet.prefix(240)))"
        case .decodeFailed(let message):
            return "Jamf computers-inventory response could not be decoded: \(message)"
        }
    }
}

private struct ComputerInventoryListItem: Decodable {
    let id: StringOrInt
    let name: String?
    let serialNumber: String?
    let username: String?
    let general: ComputerGeneral?
    let hardware: ComputerHardware?
    let userAndLocation: ComputerUserAndLocation?
    let extensionAttributes: [ComputerExtensionAttribute]?

    var reportComputer: JamfReportComputer {
        let valuesByName = notaryValuesByName(
            generalAttributes: general?.extensionAttributes,
            topLevelAttributes: extensionAttributes
        )
        return JamfReportComputer(
            id: id.intValue,
            name: nonEmpty(general?.name) ?? nonEmpty(name) ?? "Computer \(id.intValue)",
            serialNumber: nonEmpty(hardware?.serialNumber) ?? nonEmpty(general?.serialNumber) ?? nonEmpty(serialNumber) ?? "n/a",
            username: nonEmpty(userAndLocation?.username) ?? nonEmpty(general?.lastLoggedInUsernameBinary) ?? nonEmpty(username) ?? "n/a",
            model: nonEmpty(hardware?.model) ?? nonEmpty(hardware?.modelIdentifier) ?? "n/a",
            complianceIndicator: complianceIndicator(
                compliance: valuesByName["Notary Compliance"],
                issues: valuesByName["Notary Issues"]
            )
        )
    }
}

private struct ComputerInventoryDetailResponse: Decodable {
    let id: StringOrInt?
    let name: String?
    let serialNumber: String?
    let username: String?
    let general: ComputerGeneral?
    let hardware: ComputerHardware?
    let userAndLocation: ComputerUserAndLocation?
    let extensionAttributes: [ComputerExtensionAttribute]?

    var reportDetail: JamfReportComputerDetail {
        let computerID = id?.intValue ?? 0
        let valuesByName = notaryValuesByName(
            generalAttributes: general?.extensionAttributes,
            topLevelAttributes: extensionAttributes
        )
        // Jamf has exposed extension attributes in both locations across list
        // and detail responses, so the mapper accepts either shape.
        let computer = JamfReportComputer(
            id: computerID,
            name: nonEmpty(general?.name) ?? nonEmpty(name) ?? "Computer \(computerID)",
            serialNumber: nonEmpty(hardware?.serialNumber) ?? nonEmpty(general?.serialNumber) ?? nonEmpty(serialNumber) ?? "n/a",
            username: nonEmpty(userAndLocation?.username) ?? nonEmpty(general?.lastLoggedInUsernameBinary) ?? nonEmpty(username) ?? "n/a",
            model: nonEmpty(hardware?.model) ?? nonEmpty(hardware?.modelIdentifier) ?? "n/a",
            complianceIndicator: complianceIndicator(
                compliance: valuesByName["Notary Compliance"],
                issues: valuesByName["Notary Issues"]
            )
        )
        return JamfReportComputerDetail(
            computer: computer,
            runnerStatus: valuesByName["Notary Runner"] ?? "n/a",
            issuesValue: valuesByName["Notary Issues"] ?? "n/a",
            complianceValue: valuesByName["Notary Compliance"] ?? "n/a",
            percentValue: valuesByName["Notary Percent"]
        )
    }
}

private struct ComputerGeneral: Decodable {
    let name: String?
    let serialNumber: String?
    let lastLoggedInUsernameBinary: String?
    let extensionAttributes: [ComputerExtensionAttribute]?
}

private struct ComputerHardware: Decodable {
    let model: String?
    let modelIdentifier: String?
    let serialNumber: String?
}

private struct ComputerUserAndLocation: Decodable {
    let username: String?
}

private struct ComputerExtensionAttribute: Decodable {
    let name: String
    let values: [String]
    let value: String?

    enum CodingKeys: String, CodingKey {
        case name, values, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)

        if var array = try? c.nestedUnkeyedContainer(forKey: .values) {
            var parsed: [String] = []
            while !array.isAtEnd {
                if let s = try? array.decode(String.self) {
                    parsed.append(s)
                } else if let i = try? array.decode(Int.self) {
                    parsed.append("\(i)")
                } else if let d = try? array.decode(Double.self) {
                    parsed.append("\(d)")
                } else if (try? array.decodeNil()) == true {
                    continue
                } else {
                    _ = try? array.decode(DiscardedJSON.self)
                }
            }
            values = parsed
        } else {
            values = []
        }

        if let s = try? c.decode(String.self, forKey: .value) {
            value = s
        } else if let i = try? c.decode(Int.self, forKey: .value) {
            value = "\(i)"
        } else if let d = try? c.decode(Double.self, forKey: .value) {
            value = "\(d)"
        } else {
            value = nil
        }
    }

    var displayValue: String {
        if let first = values.first, !first.isEmpty {
            return first
        }
        return nonEmpty(value) ?? ""
    }
}

private struct DiscardedJSON: Decodable {
    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd {
                _ = try? array.decode(DiscardedJSON.self)
            }
            return
        }

        if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            for key in object.allKeys {
                _ = try? object.decode(DiscardedJSON.self, forKey: key)
            }
            return
        }

        let single = try decoder.singleValueContainer()
        _ = try? single.decode(Bool.self)
        _ = try? single.decode(String.self)
        _ = try? single.decode(Double.self)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func notaryValuesByName(
    generalAttributes: [ComputerExtensionAttribute]?,
    topLevelAttributes: [ComputerExtensionAttribute]?
) -> [String: String] {
    Dictionary(
        (generalAttributes ?? [] + (topLevelAttributes ?? [])).map { ($0.name, $0.displayValue) },
        uniquingKeysWith: { current, _ in current }
    )
}

private func complianceIndicator(compliance: String?, issues: String?) -> String {
    guard let compliance = nonEmpty(compliance) else { return "" }
    if compliance.localizedCaseInsensitiveContains("FAILED") {
        return "❌"
    }
    guard compliance.localizedCaseInsensitiveContains("PASSED") else { return "" }
    if hasCurrentIssues(issues) {
        return "⚠️"
    }
    return "✅"
}

private func hasCurrentIssues(_ issues: String?) -> Bool {
    guard let value = nonEmpty(issues) else { return false }
    let lower = value.lowercased()
    return lower != "n/a" && lower != "none" && lower != "no current findings."
}


/*
 /// Classic API: GET /JSSResource/computers/serialnumber/{serial}
 /// Returns Jamf computer ID (general/id) or nil on failure.
 func getComputerID(serial: String, bearerToken: String) async -> Int? {

     let serialEnc = JamfAPI.urlEncodePathComponent(serial)
     let url = baseURL
         .appendingPathComponent("JSSResource/computers/serialnumber")
         .appendingPathComponent(serialEnc)

     let headers: [String: String] = [
         "Accept": "text/xml",
         "Authorization": "Bearer \(bearerToken)"
     ]

     let resp = await http.request(url: url, method: "GET", headers: headers)

     // Mirror old behavior: special-case 404 and 401 in logs
     if resp.statusCode == 404 {
         logger.error("Computer not found in Jamf (serial=\(serial))")
         return nil
     }
     if resp.statusCode == 401 {
         logger.error("Unauthorized when fetching Jamf Computer ID")
         return nil
     }

     guard http.requireSuccess(resp, context: "getComputerID(serial=\(serial))", logBodyOnError: true) else {
         return nil
     }

     // Parse <id>...</id> from XML
     guard let id = JamfAPI.extractFirstXMLTag(resp.bodyString, tag: "id"),
           let intID = Int(id.trimmingCharacters(in: .whitespacesAndNewlines)) else {
         logger.error("Jamf Computer ID parse failed (no <id> in response)")
         return nil
     }

     logger.info("Jamf Computer ID: \(intID)")
     return intID
 }
 */
