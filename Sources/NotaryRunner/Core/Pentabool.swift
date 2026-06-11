import Foundation

package enum PentaMode: Int, Codable {
  case hardEnforce = 2
  case enforce     = 1
  case ignore      = 0
  case check       = -1
  case hardCheck   = -2
}

package enum Severity: String, Codable {
  case low
  case high
}

func severity(for mode: PentaMode) -> Severity? {
    switch mode {
    case .ignore:
        return nil
    case .check, .enforce:
        return .low
    case .hardCheck, .hardEnforce:
        return .high
    }
}

private func normalizeString(_ raw: Any) -> String {
    // Handle String / NSString / CFString cleanly
    if let s = raw as? String { return s }
    if let s = raw as? NSString { return s as String }

    // Fallback (can produce "Optional(...)" in some cases)
    let desc = String(describing: raw)

    // Strip Optional("x") / Optional(x)
    if desc.hasPrefix("Optional("), desc.hasSuffix(")") {
        let inner = desc.dropFirst("Optional(".count).dropLast(1)
        // Strip surrounding quotes if present
        if inner.hasPrefix("\""), inner.hasSuffix("\""), inner.count >= 2 {
            return String(inner.dropFirst().dropLast())
        }
        return String(inner)
    }
    return desc
}

func looksLikePentaboolDirective(_ raw: Any) -> Bool {
    let s = normalizeString(raw)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    switch s {
    case "hard-enforce", "enforce", "check", "hard-check",
        "1", "0", "-1", "-2",
        "true", "false", "yes", "no", "on", "off":
        return true
    default:
        return false
    }
}

package func toPentabool(_ raw: Any?) -> PentaMode {
    guard let raw else { return .ignore }

    // Numbers: keep your semantics
    if let n = raw as? Int {
        if n >= 2 { return .hardEnforce }
        if n == 1 { return .enforce }
        if n == 0 { return .ignore }
        if n == -1 { return .check }
        if n <= -2 { return .hardCheck }
        return .ignore
    }
    if let n = raw as? NSNumber {
        return toPentabool(n.intValue)
    }

    // Bool
    if let b = raw as? Bool {
        return b ? .enforce : .ignore
    }

    // Stringy values
    let s = normalizeString(raw)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    switch s {
    case "hard-enforce": return .hardEnforce
    case "1", "true", "yes", "on", "enforce": return .enforce
    case "0", "false", "no", "off", "": return .ignore
    case "check": return .check
    case "hard-check": return .hardCheck
    default: return .ignore
    }
}
