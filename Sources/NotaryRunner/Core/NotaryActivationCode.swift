import AppTokenKit
import Foundation

package enum NotaryActivationCode {
    package static let key = "activationCode"

    package static func resolved(
        rawSnapshot: [String: Any],
        state: RunnerState,
        authorization: NotaryAppTokenAuthorization
    ) -> String? {
        if let managedValue = firstManagedValue(rawSnapshot: rawSnapshot) {
            return managedValue
        }
        if let stateValue = normalized(state.activationCode) {
            return stateValue
        }
        if authorization.diagnostics.status == .valid,
           let tokenValue = normalized(authorization.diagnostics.payload?.activationCode) {
            return tokenValue
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
