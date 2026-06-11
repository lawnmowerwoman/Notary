import Foundation

struct PerUserPreferences {

    static func localUsers() -> [String] {
        guard let r = try? Shell.run(
            "/usr/bin/dscl",
            [".", "-list", "/Users", "UniqueID"],
            timeout: 10
        ) else { return [] }

        var users: [String] = []

        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ")

            if parts.count == 2,
               let uid = Int(parts[1]),
               uid >= 500,
               parts[0] != "nobody" {
                users.append(String(parts[0]))
            }
        }

        return users.sorted()
    }

    static func uid(for user: String) -> Int? {
        guard let r = try? Shell.run(
            "/usr/bin/id",
            ["-u", user],
            timeout: 5
        ) else { return nil }

        return Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readDefaults(
        user: String,
        domain: String,
        key: String,
        logger: HardenLogger? = nil
    ) -> (value: String?, readFailed: Bool) {
        guard let uid = uid(for: user) else {
            logger?.develop("[PERUSER] readDefaults: no uid for user \(user)")
            return (nil, true)
        }

        let args = [
            "asuser", "\(uid)",
            "/usr/bin/sudo", "-u", user,
            "/usr/bin/defaults",
            "read",
            domain,
            key
        ]

        guard let r = try? Shell.run(
            "/bin/launchctl",
            args,
            timeout: 10,
            logger: logger
        ) else {
            logger?.develop("[PERUSER] readDefaults: launchctl/defaults failed for user=\(user) domain=\(domain) key=\(key)")
            return (nil, true)
        }

        logger?.develop("[PERUSER] readDefaults user=\(user) domain=\(domain) key=\(key) code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code != 0 {
            return (nil, false) // missing key or unreadable pref in normal defaults semantics
        }

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty ? nil : value, false)
    }

    static func writeDefaultsBool(
        user: String,
        domain: String,
        key: String,
        value: Bool,
        logger: HardenLogger? = nil
    ) -> Bool {
        guard let uid = uid(for: user) else {
            logger?.develop("[PERUSER] writeDefaultsBool: no uid for user \(user)")
            return false
        }

        let args = [
            "asuser", "\(uid)",
            "/usr/bin/sudo", "-u", user,
            "/usr/bin/defaults",
            "write",
            domain,
            key,
            "-bool",
            value ? "true" : "false"
        ]

        guard let r = try? Shell.run(
            "/bin/launchctl",
            args,
            timeout: 10,
            logger: logger
        ) else {
            logger?.develop("[PERUSER] writeDefaultsBool: launchctl/defaults failed for user=\(user) domain=\(domain) key=\(key)")
            return false
        }

        logger?.develop("[PERUSER] writeDefaultsBool user=\(user) domain=\(domain) key=\(key) value=\(value) code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        return r.code == 0 && !r.didTimeout
    }

    static func readCurrentHostDefaults(
        user: String,
        domain: String,
        key: String,
        logger: HardenLogger? = nil
    ) -> (value: String?, readFailed: Bool) {
        guard let uid = uid(for: user) else {
            logger?.develop("[PERUSER] readCurrentHostDefaults: no uid for user \(user)")
            return (nil, true)
        }

        let args = [
            "asuser", "\(uid)",
            "/usr/bin/sudo", "-u", user,
            "/usr/bin/defaults",
            "-currentHost",
            "read",
            domain,
            key
        ]

        guard let r = try? Shell.run(
            "/bin/launchctl",
            args,
            timeout: 10,
            logger: logger
        ) else {
            logger?.develop("[PERUSER] readCurrentHostDefaults: launchctl/defaults failed for user=\(user) domain=\(domain) key=\(key)")
            return (nil, true)
        }

        logger?.develop("[PERUSER] readCurrentHostDefaults user=\(user) domain=\(domain) key=\(key) code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code != 0 {
            return (nil, false)
        }

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty ? nil : value, false)
    }

    static func writeCurrentHostDefaultsBool(
        user: String,
        domain: String,
        key: String,
        value: Bool,
        logger: HardenLogger? = nil
    ) -> Bool {
        guard let uid = uid(for: user) else {
            logger?.develop("[PERUSER] writeCurrentHostDefaultsBool: no uid for user \(user)")
            return false
        }

        let args = [
            "asuser", "\(uid)",
            "/usr/bin/sudo", "-u", user,
            "/usr/bin/defaults",
            "-currentHost",
            "write",
            domain,
            key,
            "-bool",
            value ? "true" : "false"
        ]

        guard let r = try? Shell.run(
            "/bin/launchctl",
            args,
            timeout: 10,
            logger: logger
        ) else {
            logger?.develop("[PERUSER] writeCurrentHostDefaultsBool: launchctl/defaults failed for user=\(user) domain=\(domain) key=\(key)")
            return false
        }

        logger?.develop("[PERUSER] writeCurrentHostDefaultsBool user=\(user) domain=\(domain) key=\(key) value=\(value) code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        return r.code == 0 && !r.didTimeout
    }

    // WARN: This method may report unexpected values
    static func read(
        user: String,
        domain: String,
        key: String
    ) -> Any? {
        let userName = user as CFString
        let domainName = domain as CFString
        let keyName = key as CFString

        return CFPreferencesCopyValue(
            keyName,
            domainName,
            userName,
            kCFPreferencesAnyHost
        )
    }

    static func boolValue(
        user: String,
        domain: String,
        key: String
    ) -> Bool? {
        guard let value = read(user: user, domain: domain, key: key) else {
            return nil
        }

        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }

        return nil
    }
}

func loginKeychainPath(for user: String) -> String? {
    let home = "/Users/\(user)"
    let dbPath = "\(home)/Library/Keychains/login.keychain-db"
    let legacyPath = "\(home)/Library/Keychains/login.keychain"

    let fm = FileManager.default

    if fm.fileExists(atPath: dbPath) { return dbPath }
    if fm.fileExists(atPath: legacyPath) { return legacyPath }

    return nil
}
