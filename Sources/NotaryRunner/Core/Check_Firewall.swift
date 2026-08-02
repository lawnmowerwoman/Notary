import Foundation

private enum OnOffState { case on, off, unknown }


private func firewallSettingRaw() -> String {
  let r = try? Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], timeout: 10)
  return [r?.stdout ?? "", r?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
}

private func firstLaunchctlMatchRaw(_ candidates: [String]) -> String {
  for label in candidates {
    let r = try? Shell.run("/bin/launchctl", ["print", "system/\(label)"], timeout: 10)
    let text = [r?.stdout ?? "", r?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
    let low = text.lowercased()
    if low.contains("could not find service") || low.contains("could not find") || text.isEmpty {
      continue
    }
    return "\(label): present"
  }
  return "no known firewall-related launchd label found (best effort)"
}

private func firewallServiceRaw() -> String {
  // candidates are best-effort; labels vary. This is purely diagnostic.
  let candidates = [
    "com.apple.alf",          // common
    "com.apple.alf.agent",
    "com.apple.socketfilterfw"
  ]
  return firstLaunchctlMatchRaw(candidates)
}

private struct FirewallDiagnostics {
  let setting: String
  let service: String
}

private func diagnoseFirewall() -> FirewallDiagnostics {
  .init(setting: firewallSettingRaw(), service: firewallServiceRaw())
}

// On-Off-State for Firewall Logging and Stealth Mode
private func parseOnOff(from text: String, labelPrefix: String) -> OnOffState {
  let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  for l in lines {
    let low = l.lowercased()
    if low.hasPrefix(labelPrefix.lowercased()) {
      if low.contains("on") { return .on }
      if low.contains("off") { return .off }
    }
  }
  return .unknown
}

func preferredFirewallOutput(
    _ r: (stdout: String, stderr: String, code: Int32, didTimeout: Bool)
) -> String {
    let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

    if !out.isEmpty { return out }
    if r.code == 0, !err.isEmpty { return err }   // benign status text on stderr
    if !err.isEmpty { return "error: \(err)" }
    return ""
}

private func singleLineFirewallOutput(_ text: String) -> String {
    text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " | ")
}

private func summarizeAllowSigned(_ text: String) -> String {
    let low = text.lowercased()

    let builtIn = low.contains("built-in") && low.contains("enabled") ? "ENABLED" :
                  low.contains("built-in") && low.contains("disabled") ? "DISABLED" : "UNKNOWN"

    let downloaded = low.contains("downloaded") && low.contains("enabled") ? "ENABLED" :
                     low.contains("downloaded") && low.contains("disabled") ? "DISABLED" : "UNKNOWN"

    return "built-in=\(builtIn) | downloaded=\(downloaded)"
}

// MARK: Firewall

/// Firewall: should be enabled
func checkFirewall() -> CheckResult {
  let raw = firewallSettingRaw().lowercased()
  if raw.contains("enabled") {
    return .init(name: "Firewall", status: .pass, details: firewallSettingRaw())
  }
  if raw.contains("disabled") {
    return .init(name: "Firewall", status: .fail, details: firewallSettingRaw())
  }
  return .init(name: "Firewall", status: .unknown, details: firewallSettingRaw())
}

func enforceFirewallOn(logger: HardenLogger) -> CheckResult {
  if geteuid() != 0 {
    return .init(name: "Firewall", status: .fail, details: "enforce requires admin/root")
  }

  let before = diagnoseFirewall()
  logger.develop("[DIAG] FW before: setting=\(before.setting) | service=\(before.service)")

  let r = try? Shell.run(
    "/usr/libexec/ApplicationFirewall/socketfilterfw",
    ["--setglobalstate", "on"],
    timeout: 30
  )
  let combined = [r?.stdout ?? "", r?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
  logger.develop("[ENFORCE] FW socketfilterfw code=\(r?.code ?? -999) out=\(r?.stdout ?? "") err=\(r?.stderr ?? "")")

  // If command failed, return fail with details (TCC-like messages would show here, if any)
  if let r, r.code != 0 {
    return .init(name: "Firewall", status: .fail, details: combined.isEmpty ? "socketfilterfw failed (code \(r.code))" : combined)
  } else if r == nil {
    return .init(name: "Firewall", status: .fail, details: "socketfilterfw enforce failed/timeout")
  }

  let post = checkFirewall()
  let after = diagnoseFirewall()
  logger.develop("[DIAG] FW after: setting=\(after.setting) | service=\(after.service)")

  if post.status == .pass {
    return .init(name: "Firewall", status: .pass, details: "enforced + verified – \(post.details)")
  }
  return .init(name: "Firewall", status: .fail, details: "enforced but not verified (post=\(post.status)) – \(post.details) | \(combined)")
}

// MARK: Stealth Mode

func checkFirewallStealthMode() -> CheckResult {
  guard FileManager.default.isExecutableFile(atPath: "/usr/libexec/ApplicationFirewall/socketfilterfw") else {
    return .init(name: "Firewall Stealth", status: .unknown, details: "socketfilterfw not found")
  }

  guard let r = try? Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getstealthmode"], timeout: 10) else {
    return .init(name: "Firewall Stealth", status: .unknown, details: "socketfilterfw --getstealthmode failed")
  }

  let text = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  let low = text.lowercased()

  if low.contains("firewall stealth mode is on") {
    return .init(name: "Firewall Stealth", status: .pass, details: text)
  }
  if low.contains("firewall stealth mode is off") {
    return .init(name: "Firewall Stealth", status: .fail, details: text)
  }

  // If socketfilterfw changes its wording, still treat unparseable as unknown (wrapper => fail in check/enforce)
  return .init(name: "Firewall Stealth", status: .unknown, details: text.isEmpty ? "unparseable stealth mode" : text)
}

func enforceFirewallStealthModeOn(logger: HardenLogger) -> CheckResult {
  if geteuid() != 0 {
    return .init(name: "Firewall Stealth", status: .fail, details: "enforce requires admin/root")
  }

  let r = try? Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--setstealthmode", "on"], timeout: 30)
  logger.develop("[ENFORCE] FW stealth code=\(r?.code ?? -999) out=\(r?.stdout ?? "") err=\(r?.stderr ?? "")")

  let post = checkFirewallStealthMode()
  if post.status == .pass {
    return .init(name: "Firewall Stealth", status: .pass, details: "enforced + verified – \(post.details)")
  }
  return .init(name: "Firewall Stealth", status: .fail, details: "enforced but not verified (post=\(post.status)) – \(post.details)")
}

// MARK: Block All Incoming

func checkFirewallBlockAllIncoming() -> CheckResult {
  let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
  guard FileManager.default.isExecutableFile(atPath: tool) else {
    return .init(name: "Firewall BlockAll", status: .unknown, details: "socketfilterfw not found")
  }

  guard let r = try? Shell.run(tool, ["--getblockall"], timeout: 10) else {
    return .init(name: "Firewall BlockAll", status: .unknown, details: "socketfilterfw --getblockall failed")
  }

  let text = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  let low = text.lowercased()

    if low.contains("blocking all") && low.contains("non-essential incoming connections") {
      // If it contains "not", treat as off
      if low.contains("not blocking") {
        return .init(name: "Firewall BlockAll", status: .fail, details: text)
      }
      return .init(name: "Firewall BlockAll", status: .pass, details: text)
    }

  return .init(name: "Firewall BlockAll", status: .unknown, details: text.isEmpty ? "unparseable blockall output" : text)
}


func enforceFirewallBlockAllIncomingOn(logger: HardenLogger) -> CheckResult {
  let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
  if geteuid() != 0 {
    return .init(name: "Firewall BlockAll", status: .fail, details: "enforce requires admin/root")
  }
  guard FileManager.default.isExecutableFile(atPath: tool) else {
    return .init(name: "Firewall BlockAll", status: .fail, details: "socketfilterfw not found")
  }

  let r = try? Shell.run(tool, ["--setblockall", "on"], timeout: 30)
  logger.develop("[ENFORCE] FW blockall code=\(r?.code ?? -999) out=\(r?.stdout ?? "") err=\(r?.stderr ?? "")")

  let post = checkFirewallBlockAllIncoming()
  if post.status == .pass {
    return .init(name: "Firewall BlockAll", status: .pass, details: "enforced + verified – \(post.details)")
  }
  return .init(name: "Firewall BlockAll", status: .fail, details: "enforced but not verified (post=\(post.status)) – \(post.details)")
}

// MARK: Allow Signed Apps

func checkFirewallAllowSigned() -> CheckResult {
    let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
    guard FileManager.default.isExecutableFile(atPath: tool) else {
        return .init(name: "Firewall AllowSigned", status: .unknown, details: "socketfilterfw not found")
    }

    guard let r = try? Shell.run(tool, ["--getallowsigned"], timeout: 10) else {
        return .init(name: "Firewall AllowSigned", status: .unknown, details: "socketfilterfw --getallowsigned failed")
    }

    let raw = preferredFirewallOutput(r)
    let summary = summarizeAllowSigned(raw)
    let low = summary.lowercased()

    if low.contains("built-in=enabled") && low.contains("downloaded=enabled") {
        return .init(name: "Firewall AllowSigned", status: .pass, details: summary)
    }

    if low.contains("built-in=disabled") || low.contains("downloaded=disabled") {
        return .init(name: "Firewall AllowSigned", status: .fail, details: summary)
    }

    return .init(
        name: "Firewall AllowSigned",
        status: .unknown,
        details: summary.isEmpty ? "unparseable allowsigned output" : summary
    )
}

func enforceFirewallAllowSignedOn(logger: HardenLogger) -> CheckResult {
  let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
  if geteuid() != 0 {
    return .init(name: "Firewall AllowSigned", status: .fail, details: "enforce requires admin/root")
  }
  guard FileManager.default.isExecutableFile(atPath: tool) else {
    return .init(name: "Firewall AllowSigned", status: .fail, details: "socketfilterfw not found")
  }

  let r = try? Shell.run(tool, ["--setallowsigned", "on"], timeout: 30)
  logger.develop("[ENFORCE] FW allowsigned code=\(r?.code ?? -999) out=\(r?.stdout ?? "") err=\(r?.stderr ?? "")")

  let post = checkFirewallAllowSigned()
  if post.status == .pass {
    return .init(name: "Firewall AllowSigned", status: .pass, details: "enforced + verified – \(post.details)")
  }
  return .init(name: "Firewall AllowSigned", status: .fail, details: "enforced but not verified (post=\(post.status)) – \(post.details)")
}
