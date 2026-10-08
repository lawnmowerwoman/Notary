import AppTokenKit
import Foundation

package enum NotaryActivationCode {
    package static let key = "activationCode"

    package static func currentDisplayValue() -> String? {
        let rawSnapshot = ManagedPrefs.snapshot(
            domain: "de.twocent.notary",
            topLevelKeys: [key]
        )
        if let managedValue = firstManagedValue(rawSnapshot: rawSnapshot) {
            return managedValue
        }
        if let state = try? SecurePlistStore<RunnerState>().load(),
           let stateValue = normalized(state.activationCode) {
            return stateValue
        }
        if let report = try? NotaryPublicReportStore().load(),
           let reportValue = normalized(report.activationCode ?? report.appTokenActivationCode) {
            return reportValue
        }
        return nil
    }

    package static func currentConfiguredValue() -> String? {
        let snapshot = ManagedPrefs.snapshot(domain: "de.twocent.notary", topLevelKeys: [key])
        if let value = firstManagedValue(rawSnapshot: snapshot) { return value }
        if let state = try? SecurePlistStore<RunnerState>().load(), let value = normalized(state.activationCode) { return value }
        return (try? NotaryPublicReportStore().load()).flatMap { normalized($0.activationCode) }
    }

    package static func resolved(
        rawSnapshot: [String: Any],
        state: RunnerState
    ) -> String? {
        if let managedValue = firstManagedValue(rawSnapshot: rawSnapshot) {
            return managedValue
        }
        if let stateValue = normalized(state.activationCode) {
            return stateValue
        }
        return nil
    }

    private static func firstManagedValue(rawSnapshot: [String: Any]) -> String? {
        if let dedicatedValue = readString(
            url: URL(fileURLWithPath: "/Library/Managed Preferences/de.twocent.notary.apptoken.plist"),
            key: key
        ) {
            return dedicatedValue
        }
        if let mainValue = normalized(rawSnapshot[key] as? String) {
            return mainValue
        }
        return nil
    }

    private static func readString(url: URL, key: String) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return normalized(dict[key] as? String)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
