import Foundation

package struct NotaryProof {
    package let generatedAt: Date
    package let passedCount: Int
    package let failedCount: Int
    package let unknownCount: Int
    package let timedOutCount: Int
    package let skippedCount: Int
    package let hardFailCount: Int
    package let compliancePercent: Int
    package let issueNames: [String]

    package var countsBlock: String {
        "pass=\(passedCount) fail=\(failedCount)" +
        formattedCount("unknown", unknownCount) +
        formattedCount("timeout", timedOutCount) +
        formattedCount("skipped", skippedCount) +
        " (\(compliancePercent)%)"
    }

    package var compliant: Bool {
        hardFailCount == 0
    }

    package var baseStatus: String {
        failedCount == 0 ? "OK" : "ISSUES"
    }

    package var complianceValue: String {
        "\(compliant ? "PASSED" : "FAILED") – \(countsBlock)"
    }

    package var compliancePercentValue: String {
        "\(compliancePercent)"
    }

    package var issuesValue: String {
        issueNames.isEmpty ? "EMPTY" : issueNames.joined(separator: " • ")
    }

    package func statusValue(versionLabel: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let timestamp = formatter.string(from: generatedAt)
        return "\(baseStatus) (\(versionLabel)) – \(timestamp)"
    }

    private func formattedCount(_ label: String, _ value: Int) -> String {
        value == 0 ? "" : " \(label)=\(value)"
    }
}

enum ProofBuilder {
    static func build(from runs: [CheckRun], at date: Date = Date()) -> NotaryProof {
        let results = runs.map(\.result)
        let passed = results.filter { $0.status == .pass }
        let failed = results.filter { $0.status == .fail }
        let unknown = results.filter { $0.status == .unknown }
        let timedOut = results.filter { $0.status == .timedOut }
        let skipped = results.filter { $0.status == .skipped }

        let denominator = max(1, passed.count + failed.count)
        let compliancePercent = Int((Double(passed.count) / Double(denominator)) * 100.0)

        let hardFails = runs.filter { $0.result.status == .fail && $0.result.severity == .high }

        let failedIssueNames = runs
            .filter { $0.result.status == .fail }
            .map { $0.spec.issueValue }

        let unknownIssueNames = runs
            .filter { $0.result.status == .unknown }
            .map { run in
                "UNKNOWN: \(run.spec.issueValue)"
            }

        return NotaryProof(
            generatedAt: date,
            passedCount: passed.count,
            failedCount: failed.count,
            unknownCount: unknown.count,
            timedOutCount: timedOut.count,
            skippedCount: skipped.count,
            hardFailCount: hardFails.count,
            compliancePercent: compliancePercent,
            issueNames: failedIssueNames + unknownIssueNames
        )
    }
}
