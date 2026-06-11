import Foundation

package struct LastKnownPassingCheck: Codable {
    package let details: String
    package let recordedAt: Date

    package init(details: String, recordedAt: Date) {
        self.details = details
        self.recordedAt = recordedAt
    }
}

package struct RunnerState: Codable {
    package var schemaVersion: Int = 1

    package var lastRunAt: Date?
    package var lastRunOK: Bool?
    package var computerID: Int?

    // NEW: API credentials (TEMP for beta; later: Keychain)
    package var jamfClientID: String?
    package var jamfClientSecret: String?
    package var jamfBearerToken: String?
    package var jamfBearerExpirationEpoch: Int?

    package var apiupdate: Bool?
    package var reportpercent: Bool?

    // EA caching
    package var eaDefinitionIDs: [String: Int] = [:]
    package var eaCacheUpdatedAt: Date?

    // Refresh control / resilience
    package var eaCacheRefreshAttemptedAt: Date?
    package var eaCacheRefreshFailCount: Int = 0

    // Transport state
    package var lastTransportUpdateAt: Date?
    package var lastReportedRunnerBaseStatus: String?
    package var lastReportedIssuesValue: String?
    package var lastReportedComplianceState: String?
    package var lastReportedComplianceValue: String?
    package var lastReportedCompliancePercentValue: String?
    package var lastUptimePromptAt: Date?
    package var lastKnownPassingChecks: [String: LastKnownPassingCheck] = [:]
    package var lastManagedConfigSeenAt: Date?
    package var managedConfigMissingSince: Date?
    package var airDropEnabledSinceByUser: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, lastRunAt, lastRunOK, computerID
        case jamfClientID, jamfClientSecret, jamfBearerToken, jamfBearerExpirationEpoch, apiupdate, reportpercent
        case eaDefinitionIDs, eaCacheUpdatedAt
        case eaCacheRefreshAttemptedAt, eaCacheRefreshFailCount
        case lastTransportUpdateAt, lastReportedRunnerBaseStatus, lastReportedIssuesValue, lastReportedComplianceState, lastReportedComplianceValue, lastReportedCompliancePercentValue
        case lastUptimePromptAt
        case lastKnownPassingChecks
        case lastManagedConfigSeenAt, managedConfigMissingSince
        case airDropEnabledSinceByUser
    }

    package init() {}

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastRunOK = try c.decodeIfPresent(Bool.self, forKey: .lastRunOK)
        computerID = try c.decodeIfPresent(Int.self, forKey: .computerID)

        jamfClientID = try c.decodeIfPresent(String.self, forKey: .jamfClientID)
        jamfClientSecret = try c.decodeIfPresent(String.self, forKey: .jamfClientSecret)
        jamfBearerToken = try c.decodeIfPresent(String.self, forKey: .jamfBearerToken)
        jamfBearerExpirationEpoch = try c.decodeIfPresent(Int.self, forKey: .jamfBearerExpirationEpoch)

        apiupdate = try c.decodeIfPresent(Bool.self, forKey: .apiupdate)
        reportpercent = try c.decodeIfPresent(Bool.self, forKey: .reportpercent)

        eaDefinitionIDs = try c.decodeIfPresent([String: Int].self, forKey: .eaDefinitionIDs) ?? [:]
        eaCacheUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .eaCacheUpdatedAt)

        eaCacheRefreshAttemptedAt = try c.decodeIfPresent(Date.self, forKey: .eaCacheRefreshAttemptedAt)
        eaCacheRefreshFailCount = try c.decodeIfPresent(Int.self, forKey: .eaCacheRefreshFailCount) ?? 0

        lastTransportUpdateAt = try c.decodeIfPresent(Date.self, forKey: .lastTransportUpdateAt)
        lastReportedRunnerBaseStatus = try c.decodeIfPresent(String.self, forKey: .lastReportedRunnerBaseStatus)
        lastReportedIssuesValue = try c.decodeIfPresent(String.self, forKey: .lastReportedIssuesValue)
        lastReportedComplianceState = try c.decodeIfPresent(String.self, forKey: .lastReportedComplianceState)
        lastReportedComplianceValue = try c.decodeIfPresent(String.self, forKey: .lastReportedComplianceValue)
        lastReportedCompliancePercentValue = try c.decodeIfPresent(String.self, forKey: .lastReportedCompliancePercentValue)
        lastUptimePromptAt = try c.decodeIfPresent(Date.self, forKey: .lastUptimePromptAt)
        lastKnownPassingChecks = try c.decodeIfPresent([String: LastKnownPassingCheck].self, forKey: .lastKnownPassingChecks) ?? [:]
        lastManagedConfigSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastManagedConfigSeenAt)
        managedConfigMissingSince = try c.decodeIfPresent(Date.self, forKey: .managedConfigMissingSince)
        airDropEnabledSinceByUser = try c.decodeIfPresent([String: Date].self, forKey: .airDropEnabledSinceByUser) ?? [:]
    }
}
