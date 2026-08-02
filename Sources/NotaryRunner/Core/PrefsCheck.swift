import Foundation

// MARK: - User scope for prefs reads

enum PrefsUserScope {
    case currentUser
    case consoleUserIfRoot
}

// MARK: - Read strategy

enum PrefsReadStrategy {
    /// host first, then anyHost, then appValue fallback
    case hostFirst
    /// anyHost first, then host, then appValue fallback (rare)
    case anyHostFirst
}

// MARK: - Value typing

enum PrefsValue {
    case int(Int)
    case bool(Bool)
    case string(String)

    var description: String {
        switch self {
        case .int(let v): return "\(v)"
        case .bool(let v): return v ? "true" : "false"
        case .string(let v): return v
        }
    }
}

// MARK: - Comparator

enum PrefsComparator {
    case equals
    case notEquals
    case lessOrEqual
    case greaterOrEqual

    func evaluate(lhs: PrefsValue, rhs: PrefsValue) -> Bool {
        switch (self, lhs, rhs) {
        case (.equals, .int(let a), .int(let b)): return a == b
        case (.notEquals, .int(let a), .int(let b)): return a != b
        case (.lessOrEqual, .int(let a), .int(let b)): return a <= b
        case (.greaterOrEqual, .int(let a), .int(let b)): return a >= b

        case (.equals, .bool(let a), .bool(let b)): return a == b
        case (.notEquals, .bool(let a), .bool(let b)): return a != b

        case (.equals, .string(let a), .string(let b)): return a == b
        case (.notEquals, .string(let a), .string(let b)): return a != b

        default:
            return false
        }
    }

    var symbol: String {
        switch self {
        case .equals: return "=="
        case .notEquals: return "!="
        case .lessOrEqual: return "≤"
        case .greaterOrEqual: return "≥"
        }
    }
}

// MARK: - Prefs read adapter (wrap ManagedPrefs)

struct PrefsReader {

    let userScope: PrefsUserScope
    let strategy: PrefsReadStrategy

    func read(domain: String, key: String) -> Any? {
        // decide user scope
        let user: CFString
        switch userScope {
        case .currentUser:
            user = kCFPreferencesCurrentUser
        case .consoleUserIfRoot:
            user = ManagedPrefs.effectiveUserScope() // your helper: currentUser unless root->console user
        }

        func get(_ host: CFString) -> Any? {
            ManagedPrefs.value(domain: domain, key: key, user: user, host: host)
        }

        switch strategy {
        case .hostFirst:
            return get(kCFPreferencesCurrentHost)
                ?? get(kCFPreferencesAnyHost)
                ?? ManagedPrefs.appValue(domain: domain, key: key)

        case .anyHostFirst:
            return get(kCFPreferencesAnyHost)
                ?? get(kCFPreferencesCurrentHost)
                ?? ManagedPrefs.appValue(domain: domain, key: key)
        }
    }

    func readInt(domain: String, key: String) -> Int? {
        guard let v = read(domain: domain, key: key) else { return nil }
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let n = Int(s) { return n }
        return nil
    }

    func readBool(domain: String, key: String) -> Bool? {
        guard let v = read(domain: domain, key: key) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1","true","yes","on"].contains(t) { return true }
            if ["0","false","no","off"].contains(t) { return false }
        }
        return nil
    }

    func readString(domain: String, key: String) -> String? {
        guard let v = read(domain: domain, key: key) else { return nil }
        if let s = v as? String { return s }
        return "\(v)"
    }
}

// MARK: - PrefsCheck builder

enum MissingBehavior {
    case unknown
    case treatAsTarget
    case fail
}

struct PrefsCheck {
    let name: String
    let domain: String
    let key: String

    let reader: PrefsReader
    let comparator: PrefsComparator

    let target: (ManagedConfig) -> PrefsValue
    let missing: MissingBehavior

    let enforce: ((HardenLogger, ManagedConfig) -> CheckResult)?

    func check(logger: HardenLogger, config: ManagedConfig) -> CheckResult {
        let tgt = target(config)

        let current: PrefsValue? = {
            switch tgt {
            case .int:    return reader.readInt(domain: domain, key: key).map { .int($0) }
            case .bool:   return reader.readBool(domain: domain, key: key).map { .bool($0) }
            case .string: return reader.readString(domain: domain, key: key).map { .string($0) }
            }
        }()

        let effective: PrefsValue? = {
            if let current { return current }
            switch missing {
            case .unknown: return nil
            case .treatAsTarget: return tgt
            case .fail: return nil
            }
        }()

        if effective == nil {
            let status: CheckStatus = (missing == .fail) ? .fail : .unknown
            return .init(name: name, status: status, details: "missing pref \(domain):\(key)")
        }

        if comparator.evaluate(lhs: effective!, rhs: tgt) {
            return .init(name: name, status: .pass,
                         details: "\(key) compliant (\(effective!.description) \(comparator.symbol) \(tgt.description))")
        }

        return .init(name: name, status: .fail,
                     details: "\(key) non-compliant (\(effective!.description) \(comparator.symbol) \(tgt.description))")
    }

    func enforceRun(logger: HardenLogger, config: ManagedConfig) -> CheckResult {
        guard let enforce else {
            return .init(name: name, status: .unknown, details: "enforce not implemented")
        }
        return enforce(logger, config)
    }
}
