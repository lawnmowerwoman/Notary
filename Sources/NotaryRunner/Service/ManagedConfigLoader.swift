import Foundation
import NotaryCore

struct ManagedConfigurationSnapshot {
    let domain: String
    let rawSnapshot: [String: Any]
    let config: ManagedConfig

    var hasManagedContent: Bool {
        rawSnapshot.values.contains { Self.containsManagedContent($0) }
    }

    private static func containsManagedContent(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return false }
            return dict.values.contains { containsManagedContent($0) }
        }
        if let array = value as? [Any] {
            return !array.isEmpty
        }
        return true
    }
}

enum ManagedConfigLoader {
    static func load(domain: String, logger: HardenLogger) -> ManagedConfigurationSnapshot {
        let rawSnapshot = ManagedPrefs.snapshot(domain: domain, topLevelKeys: GeneratedKeys.topKeys)
        let config = ManagedConfig.from(rawSnapshot: rawSnapshot, logger: logger)
        return ManagedConfigurationSnapshot(domain: domain, rawSnapshot: rawSnapshot, config: config)
    }
}
