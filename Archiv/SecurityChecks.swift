import Foundation

enum CheckStatus {
    case pass
    case fail
    case unknown
}

struct CheckResult {
    let name: String
    let status: CheckStatus
    let details: String
}

private func readPlistDict(at path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return obj as? [String: Any] ?? [:]
}


/// FileVault: `fdesetup status` should contain "FileVault is On."
func checkFileVault() -> CheckResult {
    do {
        let r = try Shell.run("/usr/bin/fdesetup", ["status"])
        let out = r.stdout.lowercased()
        let ok = out.contains("filevault is on")
        return .init(
            name: "FileVault",
            status: ok ? .pass : .fail,
            details: r.stdout.isEmpty ? r.stderr : r.stdout
        )
    } catch {
        return .init(name: "FileVault", status: .unknown, details: "error: \(error)")
    }
}


/// Gatekeeper: `spctl --status` should be "assessments enabled"
func checkGatekeeper() -> CheckResult {
    do {
        let r = try Shell.run("/usr/sbin/spctl", ["--status"])
        let out = r.stdout.lowercased()
        let ok = out.contains("assessments enabled")
        return .init(
            name: "Gatekeeper",
            status: ok ? .pass : .fail,
            details: r.stdout.isEmpty ? r.stderr : r.stdout
        )
    } catch {
        return .init(name: "Gatekeeper", status: .unknown, details: "error: \(error)")
    }
}


/// SIP: `csrutil status` should contain "System Integrity Protection status: enabled."
func checkSIP() -> CheckResult {
    do {
        let r = try Shell.run("/usr/bin/csrutil", ["status"])
        let out = r.stdout.lowercased()
        let ok = out.contains("enabled")
        return .init(
            name: "SIP",
            status: ok ? .pass : .fail,
            details: r.stdout.isEmpty ? r.stderr : r.stdout
        )
    } catch {
        return .init(name: "SIP", status: .unknown, details: "error: \(error)")
    }
}

/// SSV: `csrutil authenticated-root status` should be enabled (Signed System Volume intact)
func checkSSV() -> CheckResult {
    do {
        let r = try Shell.run("/usr/bin/csrutil", ["authenticated-root", "status"])
        let out = r.stdout.lowercased()
        let ok = out.contains("enabled")
        return .init(
            name: "SSV",
            status: ok ? .pass : .fail,
            details: r.stdout.isEmpty ? r.stderr : r.stdout
        )
    } catch {
        return .init(name: "SSV", status: .unknown, details: "error: \(error)")
    }
}


/// Firewall: should be enabled
func checkFirewall() -> CheckResult {
    do {
        let r = try Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        let out = r.stdout.lowercased()
        if out.contains("enabled") {
            return .init(name: "Firewall", status: .pass, details: r.stdout)
        }
        if out.contains("disabled") {
            return .init(name: "Firewall", status: .fail, details: r.stdout)
        }
        return .init(name: "Firewall", status: .unknown, details: r.stdout.isEmpty ? r.stderr : r.stdout)
    } catch {
        return .init(name: "Firewall", status: .unknown, details: "error: \(error)")
    }
}

/// SSH (Remote Login): should be Off
func checkSSH() -> CheckResult {
    // Try systemsetup first
    do {
        let r = try Shell.run("/usr/sbin/systemsetup", ["-getremotelogin"])
        let out = r.stdout.lowercased()
        if out.contains("on") {
            return .init(name: "SSH", status: .fail, details: r.stdout)
        }
        if out.contains("off") {
            return .init(name: "SSH", status: .pass, details: r.stdout)
        }
        // Unexpected output
        return .init(name: "SSH", status: .unknown, details: r.stdout.isEmpty ? r.stderr : r.stdout)
    } catch {
        // Fallback: launchctl (works without admin in most cases)
        do {
            let r2 = try Shell.run("/bin/launchctl", ["print", "system/com.openssh.sshd"])
            let text = (r2.stdout + "\n" + r2.stderr).lowercased()

            // Heuristic: if launchd knows the service, it prints a lot.
            // If it's not present, you'll get "Could not find service" or similar.
            if text.contains("could not find service") || text.contains("could not find") {
                return .init(name: "SSH", status: .pass, details: "sshd not loaded (launchctl)")
            } else {
                return .init(name: "SSH", status: .fail, details: "sshd present (launchctl)")
            }
        } catch {
            return .init(name: "SSH", status: .unknown, details: "error: \(error)")
        }
    }
}

/// XPR-1: XProtect present + version readable (non-admin safe).
/// PASS  -> bundle exists and version string can be read
/// UNKNOWN -> cannot read expected plists / layout changed / permission issue
func checkXProtect() -> CheckResult {
    // Common paths on modern macOS
    let infoPlist = "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
    let metaPlist = "/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist"

    let fm = FileManager.default
    guard fm.fileExists(atPath: infoPlist) else {
        // If Apple ever moves it, don’t hard-fail in XPR-1.
        return .init(name: "XProtect", status: .unknown, details: "XProtect Info.plist not found at expected path")
    }

    do {
        let info = try readPlistDict(at: infoPlist)

        let version =
            (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? ""

        // meta is optional for XPR-1; try to enrich details
        var metaDetails = ""
        if fm.fileExists(atPath: metaPlist) {
            if let meta = try? readPlistDict(at: metaPlist) {
                // These keys can vary; we keep it best-effort.
                let keysToTry = ["LastModification", "LastUpdate", "last_update", "Version", "version"]
                for k in keysToTry {
                    if let v = meta[k] {
                        metaDetails = " | \(k)=\(v)"
                        break
                    }
                }
            }
        }

        if version.isEmpty {
            return .init(name: "XProtect", status: .unknown, details: "XProtect present but version not readable\(metaDetails)")
        }

        return .init(name: "XProtect", status: .pass, details: "version=\(version)\(metaDetails)")
    } catch {
        return .init(name: "XProtect", status: .unknown, details: "read error: \(error)")
    }
}

/// XPR-Update-1: Read XProtect ConfigData package version via pkgutil.
/// PASS -> version parsed
/// UNKNOWN -> receipt missing / parsing fails
func checkXProtectConfigData() -> CheckResult {
    let pkgId = "com.apple.pkg.XProtectPlistConfigData"

    do {
        let r = try Shell.run("/usr/sbin/pkgutil", ["--pkg-info", pkgId])
        // Example lines:
        // version: 2193
        // install-time: 1700000000
        let lines = r.stdout.split(separator: "\n").map { String($0) }

        let versionLine = lines.first(where: { $0.lowercased().hasPrefix("version:") })
        let version = versionLine?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if version.isEmpty {
            return .init(name: "XProtect Update", status: .unknown, details: "pkgutil returned no version for \(pkgId)")
        }

        // best-effort install-time
        let installTimeLine = lines.first(where: { $0.lowercased().hasPrefix("install-time:") })
        let installTime = installTimeLine?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let details = installTime.isEmpty ? "configDataVersion=\(version)" : "configDataVersion=\(version) | install-time=\(installTime)"
        return .init(name: "XProtect Update", status: .pass, details: details)
    } catch {
        // If receipt isn't present (older/newer OS), don't fail hard.
        return .init(name: "XProtect Update", status: .unknown, details: "pkgutil error: \(error)")
    }
}

/// MRT: Malware Removal Tool present + version readable (non-admin safe).
func checkMRT() -> CheckResult {
    let infoPlist = "/System/Library/CoreServices/MRT.app/Contents/Info.plist"
    let fm = FileManager.default

    guard fm.fileExists(atPath: infoPlist) else {
        return .init(name: "MRT", status: .unknown, details: "MRT Info.plist not found at expected path")
    }

    do {
        let info = try readPlistDict(at: infoPlist)
        let version =
            (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? ""

        if version.isEmpty {
            return .init(name: "MRT", status: .unknown, details: "MRT present but version not readable")
        }

        return .init(name: "MRT", status: .pass, details: "version=\(version)")
    } catch {
        return .init(name: "MRT", status: .unknown, details: "read error: \(error)")
    }
}

func runBaselineChecks() -> [CheckResult] {
    [
        checkFileVault(),
        checkGatekeeper(),
        checkSIP(),
        checkSSV(),
        checkFirewall(),
        checkSSH(),
        checkMRT()
    ]
}

func runConfiguredChecks(rawSnapshot: [String: Any], logger: HardenLogger) -> [CheckResult] {
  let isAdmin = (geteuid() == 0)

  var results = runBaselineChecks()

  let mode = modeFor(rawSnapshot, section: "CoreSecurity", key: "UpdateXProtect")

  let xpr = runWithPolicy(
    name: "XProtect",
    mode: mode,
    logger: logger,
    isAdmin: isAdmin,
    check: { checkXProtectCLI() },
    enforce: { enforceXProtectCLI() }
  )

  // ersetze alten plist-Check, falls du willst
  results.removeAll { $0.name == "XProtect" }
  results.append(xpr)

  return results
}






struct ModeDecision {
  let mode: PentaMode
  let section: String
  let key: String
}

func modeFor(_ rawSnapshot: [String: Any], section: String, key: String) -> PentaMode {
  guard
    let sec = rawSnapshot[section] as? [String: Any]
  else { return .ignore }

  return toPentabool(sec[key])
}

func shouldRun(_ mode: PentaMode) -> Bool {
  switch mode {
  case .ignore:
    return false
  case .check, .hardCheck, .enforce, .hardEnforce:
    return true
  }
}

func runWithPolicy(
  name: String,
  mode: PentaMode,
  logger: HardenLogger,
  isAdmin: Bool,
  check: () -> CheckResult,
  enforce: (() -> CheckResult)? = nil
) -> CheckResult {

  guard shouldRun(mode) else {
    return .init(name: name, status: .pass, details: "skipped (mode=ignore)")
    // Alternativ: eigener Status "skipped" – aber für heute okay so.
  }

  let checked = check()

  // Wenn nur check/hardCheck → Ergebnis direkt zurück
  switch mode {
  case .check, .hardCheck:
    // optional: hardCheck könnte UNKNOWN/Fails anders behandeln – aber erstmal 1:1
    return checked

  case .enforce, .hardEnforce:
    // Wenn schon PASS, nix tun
    if checked.status == .pass { return checked }

    // Wenn enforce fehlt, ist das ein Design-Problem: hardEnforce => FAIL, enforce => UNKNOWN/FAIL? (deine Semantik)
    guard let enforce else {
      let status: CheckStatus = (mode == .hardEnforce) ? .fail : .unknown
      return .init(name: name, status: status, details: "enforce requested but not implemented")
    }

    // Wenn keine Adminrechte: hardEnforce => FAIL, enforce => UNKNOWN
    if !isAdmin {
      let status: CheckStatus = (mode == .hardEnforce) ? .fail : .unknown
      return .init(name: name, status: status, details: "enforce requires admin/root")
    }

    // enforce ausführen und danach (optional) nochmal checken
    let enforced = enforce()

    // Wenn enforce selbst PASS liefert, super. Wenn nicht, behalten wir enforced.
    return enforced

  case .ignore:
    // unreachable wegen guard
    return checked
  }
}
