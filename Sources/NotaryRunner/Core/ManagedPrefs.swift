import Foundation
import CoreFoundation
import SystemConfiguration

package enum ManagedPrefs {
    /// Reads the effective value for a key from the preferences daemon (cfprefsd).
    /// This includes managed preferences if present.
    package static func appValue(domain: String, key: String) -> Any? {
        let dom = domain as CFString
        let k = key as CFString
        return CFPreferencesCopyAppValue(k, dom)
    }

    /// Best-effort: try to obtain the "entire" domain dictionary (may be nil if nothing set).
    /// Note: Depending on how prefs are set/merged, this can return only a subset.
    package static func domainDictionary(domain: String) -> [String: Any] {
        let dom = domain as CFString

        // This reads the cached/known keys for the domain for the current user.
        // Managed settings are usually visible through appValue() by key.
        if let dict = CFPreferencesCopyMultiple(nil, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] {
            return dict
        }

        // Fallback to empty if domain not present in this scope
        return [:]
    }

    /// Convenience: read top-level keys you care about and assemble a stable JSON-able object.
    package static func snapshot(domain: String, topLevelKeys: [String]) -> [String: Any] {
        var out: [String: Any] = [:]
        for k in topLevelKeys {
            if let v = appValue(domain: domain, key: k) {
                out[k] = v
            }
        }
        return out
    }

    package static func toPrettyJSON(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj) else {
            return "{ \"error\": \"Object is not valid JSON\" }"
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"\(error)\" }"
        }
    }
}


package extension ManagedPrefs {
    static func consoleUserInfo() -> (user: String, uid: uid_t)? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let cfUser = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else { return nil }
        let user = cfUser as String
        if user.isEmpty || user == "loginwindow" { return nil }
        return (user, uid)
    }

    /// Returns the currently logged-in console user (GUI session). Nil if none.
    static func consoleUser() -> String? {
        consoleUserInfo()?.user
    }

    /// Picks the user scope: current user if not root, otherwise console user (best-effort).
    static func effectiveUserScope() -> CFString {
        if geteuid() != 0 {
            return kCFPreferencesCurrentUser
        }
        if let u = consoleUser() {
            return u as CFString
        }
        // Fallback (still better than crashing; may yield nil values if no console user)
        return kCFPreferencesCurrentUser
    }

    static func value(domain: String, key: String, user: CFString, host: CFString) -> Any? {
        let dom = domain as CFString
        let k = key as CFString

        // Try to sync first to reduce stale-cache surprises.
        CFPreferencesSynchronize(dom, user, host)

        return CFPreferencesCopyValue(k, dom, user, host)
    }

    /// Reads Int using host-first strategy for the effective user.
    static func intEffective(domain: String, key: String) -> Int? {
        let user = effectiveUserScope()

        let candidates: [Any?] = [
            value(domain: domain, key: key, user: user, host: kCFPreferencesCurrentHost),
            value(domain: domain, key: key, user: user, host: kCFPreferencesAnyHost),
            // Last resort: appValue (may miss currentHost, but sometimes helps with managed values)
            appValue(domain: domain, key: key)
        ]

        for v in candidates {
            if let n = v as? Int { return n }
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String, let n = Int(s) { return n }
        }
        return nil
    }

    static func boolEffective(domain: String, key: String) -> Bool? {
        let user = effectiveUserScope()

        let candidates: [Any?] = [
            value(domain: domain, key: key, user: user, host: kCFPreferencesCurrentHost),
            value(domain: domain, key: key, user: user, host: kCFPreferencesAnyHost),
            appValue(domain: domain, key: key)
        ]

        for v in candidates {
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.boolValue }
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["1","true","yes","on"].contains(t) { return true }
                if ["0","false","no","off"].contains(t) { return false }
            }
        }
        return nil
    }
}
