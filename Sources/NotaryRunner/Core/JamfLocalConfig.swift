import Foundation

package enum JamfLocalConfig {

    package static func jamfProURL() -> URL? {
        let path = "/Library/Preferences/com.jamfsoftware.jamf.plist"
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }

        // Try both keys to be safe
        let raw = (dict["jss_url"] as? String) ?? (dict["iss_url"] as? String)
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }

        // Normalize: ensure https:// and no trailing slash
        if !s.lowercased().hasPrefix("http") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }

        return URL(string: s)
    }
}
