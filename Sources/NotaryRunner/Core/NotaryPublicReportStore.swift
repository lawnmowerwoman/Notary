import Foundation
import Darwin

package struct NotaryPublicReport: Codable {
    package let generatedAt: Date
    package let lastRunAt: Date?
    package let lastTransportUpdateAt: Date?
    package let runnerStatus: String
    package let issuesValue: String
    package let complianceValue: String
    package let passedCount: Int?
    package let failedCount: Int?
    package let unknownCount: Int?
    package let timedOutCount: Int?
    package let skippedCount: Int?
    package let compliancePercent: Int?
    package let marketingVersion: String
    package let versionLabel: String
    package let serialNumber: String?
    package let hardwareModel: String?
    package let managementHost: String?
    package let managementComputerID: Int?

    package init(
        generatedAt: Date,
        lastRunAt: Date?,
        lastTransportUpdateAt: Date?,
        runnerStatus: String,
        issuesValue: String,
        complianceValue: String,
        passedCount: Int? = nil,
        failedCount: Int? = nil,
        unknownCount: Int? = nil,
        timedOutCount: Int? = nil,
        skippedCount: Int? = nil,
        compliancePercent: Int? = nil,
        marketingVersion: String,
        versionLabel: String,
        serialNumber: String?,
        hardwareModel: String?,
        managementHost: String?,
        managementComputerID: Int?
    ) {
        self.generatedAt = generatedAt
        self.lastRunAt = lastRunAt
        self.lastTransportUpdateAt = lastTransportUpdateAt
        self.runnerStatus = runnerStatus
        self.issuesValue = issuesValue
        self.complianceValue = complianceValue
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.unknownCount = unknownCount
        self.timedOutCount = timedOutCount
        self.skippedCount = skippedCount
        self.compliancePercent = compliancePercent
        self.marketingVersion = marketingVersion
        self.versionLabel = versionLabel
        self.serialNumber = serialNumber
        self.hardwareModel = hardwareModel
        self.managementHost = managementHost
        self.managementComputerID = managementComputerID
    }
}

package final class NotaryPublicReportStore {
    private let fm = FileManager.default

    package init() {}

    private var isRoot: Bool { geteuid() == 0 }

    package var rootURL: URL {
        URL(fileURLWithPath: "/Library/Application Support/Notary/report.plist", isDirectory: false)
    }

    package var tmpURL: URL {
        let uid = Int(geteuid())
        return URL(fileURLWithPath: "/tmp/notary.report.\(uid).plist", isDirectory: false)
    }

    private var writeURL: URL {
        isRoot ? rootURL : tmpURL
    }

    package var preferredReadURL: URL {
        if fm.fileExists(atPath: rootURL.path) { return rootURL }
        return tmpURL
    }

    package func load() throws -> NotaryPublicReport? {
        let url = preferredReadURL
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try PropertyListDecoder().decode(NotaryPublicReport.self, from: data)
    }

    package func save(_ report: NotaryPublicReport) throws {
        let url = writeURL
        let dir = url.deletingLastPathComponent()
        try ensureDirectoryExists(dir)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(report)
        try atomicWrite(data: data, to: url)
        try applyReadableAttributes(to: url)
    }

    private func ensureDirectoryExists(_ dir: URL) throws {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
            return
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp.\(UUID().uuidString)")
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try fm.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    private func applyReadableAttributes(to url: URL) throws {
        var attrs: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: 0o644)
        ]
        if isRoot {
            attrs[.ownerAccountID] = NSNumber(value: 0)
            attrs[.groupOwnerAccountID] = NSNumber(value: 0)
        }
        try fm.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
