import Foundation

private enum RemoteLoginState {
  case on
  case off
  case unknown
}

private struct RemoteLoginDiagnostics {
  let setting: String   // systemsetup output
  let service: String   // launchctl heuristic output
}

private func remoteLoginSettingRaw() -> String {
  let r = try? Shell.run("/usr/sbin/systemsetup", ["-getremotelogin"], timeout: 10)
  return [r?.stdout ?? "", r?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
}

private func remoteLoginServiceRaw() -> String {
  // sshd label is stable
  let r = try? Shell.run("/bin/launchctl", ["print", "system/com.openssh.sshd"], timeout: 10)
  let text = [r?.stdout ?? "", r?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
  if text.lowercased().contains("could not find service") || text.lowercased().contains("could not find") {
    return "sshd not loaded"
  }
  return text.isEmpty ? "sshd status ambiguous (empty output)" : "sshd present"
}

private func diagnoseRemoteLogin() -> RemoteLoginDiagnostics {
  .init(setting: remoteLoginSettingRaw(), service: remoteLoginServiceRaw())
}


private func parseRemoteLoginState(fromSystemsetupOutput text: String) -> RemoteLoginState {
  // systemsetup typically prints: "Remote Login: On" / "Remote Login: Off"
  // We match the specific label to avoid false positives.
  let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

  for lineSub in lines {
    let line = lineSub.lowercased()
    if line.hasPrefix("remote login:") {
      if line.contains("on") { return .on }
      if line.contains("off") { return .off }
    }
  }
  return .unknown
}

private func looksLikeAdminRequired(_ text: String) -> Bool {
  let s = text.lowercased()
  return s.contains("administrator access") ||
         s.contains("need administrator") ||
         s.contains("requires administrator") ||
         s.contains("must be run as root")
}

/// SSH (Remote Login): should be Off
func checkRemoteLoginBestEffort(logger: HardenLogger) -> CheckResult {
  // 1) Try systemsetup first (even as user)
  if FileManager.default.isExecutableFile(atPath: "/usr/sbin/systemsetup"),
     let r = try? Shell.run("/usr/sbin/systemsetup", ["-getremotelogin"]) {

    let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")

    // 🔧 IMPORTANT: detect "admin required" FIRST (exit code is not reliable here)
    if looksLikeAdminRequired(combined) {
      return checkRemoteLoginViaLaunchctl(logger:logger)
    }

    // If systemsetup gave a clear answer
    switch parseRemoteLoginState(fromSystemsetupOutput: combined) {
    case .on:
      return .init(name: "SSH", status: .fail, details: combined.isEmpty ? r.stdout : combined)
    case .off:
      return .init(name: "SSH", status: .pass, details: combined.isEmpty ? r.stdout : combined)
    case .unknown:
      // If it ran but we can't parse it, keep unknown
      if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .init(name: "SSH", status: .unknown, details: combined)
      }
      // If it produced nothing useful, try launchctl
        return checkRemoteLoginViaLaunchctl(logger:logger)
    }
  }

  // 2) Fallback
  return checkRemoteLoginViaLaunchctl(logger:logger)
}


private func checkRemoteLoginViaLaunchctl(logger:HardenLogger) -> CheckResult {
  guard FileManager.default.isExecutableFile(atPath: "/bin/launchctl") else {
    return .init(name: "SSH", status: .unknown, details: "launchctl not found")
  }

  guard let r = try? Shell.run("/bin/launchctl", ["print", "system/com.openssh.sshd"]) else {
    return .init(name: "SSH", status: .unknown, details: "launchctl execution failed")
  }

  let text = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  let low = text.lowercased()

  // Typical when service isn't loaded:
  if low.contains("could not find service") || low.contains("could not find") {
    return .init(name: "SSH", status: .pass, details: "sshd not loaded (launchctl)")
  }

  // If we got any structured output, it's very likely loaded/present.
  if !low.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return .init(name: "SSH", status: .fail, details: "sshd present (launchctl)")
  }

  return .init(name: "SSH", status: .unknown, details: "launchctl output empty/ambiguous")
}


func enforceRemoteLoginOff(logger: HardenLogger) -> CheckResult {
  if geteuid() != 0 {
    return .init(name: "SSH", status: .fail, details: "enforce requires admin/root")
  }

  // 1) Try systemsetup (persistent setting)
  guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/systemsetup") else {
    return .init(name: "SSH", status: .fail, details: "systemsetup not found")
  }

    let before = diagnoseRemoteLogin()
    logger.develop("[DIAG] SSH before: setting=\(before.setting) | service=\(before.service)")

  guard let r = try? Shell.run("/usr/sbin/systemsetup", ["-f", "-setremotelogin", "off"], timeout: 60) else {
    return .init(name: "SSH", status: .fail, details: "systemsetup enforce failed/timeout")
  }

  let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  logger.info("[ENFORCE] SSH systemsetup code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

  if r.code != 0 {
    // TCC / Full Disk Access
    if isTCCBlockedMessage(combined) {
      // 2) Fallback: stop the service (non-persistent) if PPPC is missing/broken
      let fb = enforceRemoteLoginOffServiceOnly(logger: logger)
      return .init(
        name: "SSH",
        status: fb.status,
        details: "systemsetup blocked by TCC (Full Disk Access required); fallback applied – \(fb.details)"
      )
    }

    return .init(
      name: "SSH",
      status: .fail,
      details: combined.isEmpty ? "systemsetup failed (code \(r.code))" : combined
    )
  }

    let after = diagnoseRemoteLogin()
    logger.develop("[DIAG] SSH after: setting=\(after.setting) | service=\(after.service)")


  // verify (as root, should be definitive if systemsetup works)
  let post = checkRemoteLoginBestEffort(logger: logger)
  if post.status == .pass {
    return .init(name: "SSH", status: .pass, details: combined.isEmpty ? "disabled (verified)" : combined)
  }

  return .init(
    name: "SSH",
    status: .fail,
    details: "systemsetup ran but not verified – \(combined) | post: \(post.details)"
  )
}

private func enforceRemoteLoginOffServiceOnly(logger: HardenLogger) -> CheckResult {
  // This does NOT persist "Remote Login" setting; it stops/unloads sshd now.
  // Intended as a safety fallback when systemsetup is blocked by TCC/PPPC.

  guard FileManager.default.isExecutableFile(atPath: "/bin/launchctl") else {
    return .init(name: "SSH", status: .fail, details: "launchctl not found for fallback")
  }

  // Try bootout (stop+unload)
  let plist = "/System/Library/LaunchDaemons/ssh.plist"
  let r1 = try? Shell.run("/bin/launchctl", ["bootout", "system", plist], timeout: 20)
  let out1 = [r1?.stdout ?? "", r1?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
  let code1 = r1?.code ?? -999
  logger.info("[ENFORCE] SSH fallback bootout code=\(code1) out=\(r1?.stdout ?? "") err=\(r1?.stderr ?? "")")

  // Verify via launchctl heuristic (works as user too, but we're root anyway)
  let post = checkRemoteLoginViaLaunchctl(logger: logger)
  if post.status == .pass {
    return .init(name: "SSH", status: .pass, details: out1.isEmpty ? "sshd booted out (verified via launchctl)" : out1)
  }

  return .init(name: "SSH", status: .fail, details: "fallback bootout not verified – \(out1) | post: \(post.details)")
}
