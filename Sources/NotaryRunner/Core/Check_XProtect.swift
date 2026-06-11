import Foundation

func xprotectLocalVersion() -> String? {
  guard let r = try? Shell.run("/usr/bin/xprotect", ["version"]) else { return nil }
  // "Version: 5330 Installed: ..."
  let s = r.stdout
  let regex = try? NSRegularExpression(pattern: #"Version:\s*([0-9]+)"#)
  let range = NSRange(s.startIndex..<s.endIndex, in: s)
  guard let m = regex?.firstMatch(in: s, range: range),
        let g = Range(m.range(at: 1), in: s) else { return nil }
  return String(s[g])
}

func xprotectLatestVersion() -> String? {
  guard let r = try? Shell.run("/usr/bin/xprotect", ["check"]) else { return nil }
  // "... version: 5330"
  let s = r.stdout
  let regex = try? NSRegularExpression(pattern: #"version:\s*([0-9]+)"#)
  let range = NSRange(s.startIndex..<s.endIndex, in: s)
  guard let m = regex?.firstMatch(in: s, range: range),
        let g = Range(m.range(at: 1), in: s) else { return nil }
  return String(s[g])
}

func checkXProtectCLI() -> CheckResult {
  // Ensure tool exists
  if !FileManager.default.isExecutableFile(atPath: "/usr/bin/xprotect") {
    return .init(name: "XProtect", status: .unknown, details: "xprotect CLI not found")
  }

  let local = xprotectLocalVersion()
  let latest = xprotectLatestVersion()

  if let l = local, let p = latest {
    if l == p {
      return .init(name: "XProtect", status: .pass, details: "up to date (version=\(l))")
    } else {
      return .init(name: "XProtect", status: .fail, details: "outdated (have=\(l), want=\(p))")
    }
  }

  if let l = local {
    return .init(name: "XProtect", status: .unknown, details: "local version=\(l); latest ambiguous")
  }

  return .init(name: "XProtect", status: .unknown, details: "unable to determine local version")
}

func enforceXProtectCLI(logger: HardenLogger) -> CheckResult {
  do {
    _ = try Shell.run("/usr/bin/xprotect", ["update"])
  } catch {
    return .init(name: "XProtect", status: .unknown, details: "xprotect update error: \(error)")
  }

  // Re-check after update
  let post = checkXProtectCLI()
  if post.status == .pass {
    return .init(name: "XProtect", status: .pass, details: "updated successfully – \(post.details)")
  }
  return .init(name: "XProtect", status: .fail, details: "update attempted but still not current – \(post.details)")
}
