import Foundation

// MARK: FileVault: `fdesetup status` should contain "FileVault is On."
func checkFileVault(logger: HardenLogger? = nil) -> CheckResult {
    let name = "FileVault"
    let path = "/usr/bin/fdesetup"
    let args = ["status"]
    let timeout: TimeInterval = 8   // Vorschlag: schnell genug, aber realistisch

    do {
        let r = try Shell.run(path, args, timeout: timeout, logger: logger)

        if r.didTimeout {
            return .init(
                name: name,
                status: .timedOut,
                details: Shell.detailsForReport(command: path, args: args, result: r, timeout: timeout)
            )
        }

        // Optional: wenn Exitcode != 0 => unknown (oder fail), je nachdem wie du es bewerten willst
        if r.code != 0 {
            return .init(
                name: name,
                status: .unknown,
                details: Shell.failureDetailsForReport(command: path, args: args, result: r, timeout: timeout)
            )
        }

        let outLower = r.stdout.lowercased()
        let ok = outLower.contains("filevault is on")

        return .init(
            name: name,
            status: ok ? .pass : .fail,
            details: Shell.detailsForReport(command: path, args: args, result: r, timeout: timeout)
        )
    } catch {
        return .init(
            name: name,
            status: .unknown,
            details: "error – \(Shell.describeCommand(path, args)) – \(error)"
        )
    }
}


// MARK: Gatekeeper: `spctl --status` should be "assessments enabled"
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


// MARK: SIP: `csrutil status` should contain "System Integrity Protection status: enabled."
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

// MARK: SSV: `csrutil authenticated-root status` should be enabled (Signed System Volume intact)
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






// MARK: MRT: Malware Removal Tool present + version readable (non-admin safe).
func checkMRT() -> CheckResult {
  let candidates = [
    "/System/Library/CoreServices/MRT.app/Contents/Info.plist",
    "/System/Library/CoreServices/MRTAgent.app/Contents/Info.plist",
    "/System/Library/PrivateFrameworks/MRT.framework/Versions/A/Resources/Info.plist"
  ]

  let fm = FileManager.default
  guard let found = candidates.first(where: { fm.fileExists(atPath: $0) }) else {
    return .init(name: "MRT", status: .unknown, details: "MRT not found at expected paths")
  }

  do {
    let info = try readPlistDict(at: found)
    let version =
      (info["CFBundleShortVersionString"] as? String)
      ?? (info["CFBundleVersion"] as? String)
      ?? ""

    if version.isEmpty {
      return .init(name: "MRT", status: .unknown, details: "MRT present but version not readable (\(found))")
    }

    return .init(name: "MRT", status: .pass, details: "version=\(version) (\(found))")
  } catch {
    return .init(name: "MRT", status: .unknown, details: "read error (\(found)): \(error)")
  }
}
