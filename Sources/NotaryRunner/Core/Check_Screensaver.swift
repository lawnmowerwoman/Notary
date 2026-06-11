import Foundation
import SystemConfiguration

// MARK: - ScreenSaver prefs

private let screensaverDomain = "com.apple.screensaver"
private let keyIdleTime = "idleTime"
private let keyAskForPassword = "askForPassword"
private let keyAskForPasswordDelay = "askForPasswordDelay"

// MARK: - Helpers

private func shellDetails(_ r: (stdout: String, stderr: String, code: Int32, didTimeout: Bool)?) -> String {
    guard let r else { return "no result" }
    if r.didTimeout { return "timeout" }
    if r.code == 0 { return "ok" }

    var parts: [String] = ["exit=\(r.code)"]
    if !r.stdout.isEmpty { parts.append("stdout=\(r.stdout)") }
    if !r.stderr.isEmpty { parts.append("stderr=\(r.stderr)") }
    return parts.joined(separator: " | ")
}

private func debugScreenSaverSources(logger: HardenLogger, key: String) {
    let userLabel: String
    if geteuid() == 0 {
        userLabel = ManagedPrefs.consoleUser() ?? "nil(consoleUser)"
    } else {
        userLabel = "currentUser"
    }

    let user = ManagedPrefs.effectiveUserScope()

    let host = ManagedPrefs.value(domain: screensaverDomain, key: key, user: user, host: kCFPreferencesCurrentHost)
    let any  = ManagedPrefs.value(domain: screensaverDomain, key: key, user: user, host: kCFPreferencesAnyHost)
    let app  = ManagedPrefs.appValue(domain: screensaverDomain, key: key)

    func fmt(_ v: Any?) -> String {
        guard let v else { return "nil" }
        return "\(v)"
    }

    logger.develop("[PREF] user=\(userLabel) key=\(key) host=\(fmt(host)) anyHost=\(fmt(any)) appValue=\(fmt(app))")
}

private enum ScreenLockSetting {
    case off
    case immediate
    case seconds(Int)
}

private func readScreenLockSetting() -> ScreenLockSetting? {
    guard let r = try? Shell.run("/usr/sbin/sysadminctl", ["-screenLock", "status"], timeout: 10) else {
        return nil
    }

    let text = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n").lowercased()

    if text.contains("screenlock delay is off") {
        return .off
    }
    if text.contains("screenlock delay is immediate") {
        return .immediate
    }

    let pattern = #"screenlock delay is (\d+)"#
    if let range = text.range(of: pattern, options: .regularExpression) {
        let match = String(text[range])
        if let n = Int(match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)) {
            return .seconds(n)
        }
    }

    return nil
}

private func consoleUserInfo() -> (user: String, uid: uid_t)? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let cfUser = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else { return nil }
    let user = cfUser as String
    if user.isEmpty || user == "loginwindow" { return nil }
    return (user, uid)
}

private func writeScreenSaverPref(
    logger: HardenLogger,
    key: String,
    valueArgs: [String],
    timeout: TimeInterval = 5
) -> CheckResult? {
    let namePrefix = "Screensaver"

    // root daemon / launchd case: write into console user's context
    if geteuid() == 0 {
        guard let info = consoleUserInfo() else {
            return .init(
                name: namePrefix,
                status: .skipped,
                details: "temporarily skipped – no console user available"
            )
        }

        let args = [
            "asuser", "\(info.uid)",
            "/usr/bin/sudo", "-u", info.user,
            "/usr/bin/defaults", "-currentHost", "write", screensaverDomain, key
        ] + valueArgs

        let r = try? Shell.run(
            "/bin/launchctl",
            args,
            timeout: timeout,
            logger: logger
        )

        if let r, r.didTimeout {
            return .init(
                name: namePrefix,
                status: .timedOut,
                details: "defaults write timed out for console user \(info.user)"
            )
        }

        if r?.code == 0 {
            syncScreenSaverPrefs()
            return nil
        }

        return .init(
            name: namePrefix,
            status: .unknown,
            details: "failed to write pref for console user \(info.user) (\(shellDetails(r)))"
        )
    }

    // non-root / interactive case
    let r = try? Shell.run(
        "/usr/bin/defaults",
        ["-currentHost", "write", screensaverDomain, key] + valueArgs,
        timeout: timeout,
        logger: logger
    )

    if let r, r.didTimeout {
        return .init(
            name: namePrefix,
            status: .timedOut,
            details: "defaults write timed out"
        )
    }

    if r?.code == 0 {
        syncScreenSaverPrefs()
        return nil
    }

    return .init(
        name: namePrefix,
        status: .unknown,
        details: "failed to write pref (\(shellDetails(r)))"
    )
}

// MARK: - Checks

func checkScreensaverIdle(saverDelay: Int) -> CheckResult {
    let limit = max(saverDelay, 1)

    guard let current = ManagedPrefs.intEffective(domain: screensaverDomain, key: keyIdleTime) else {
        // Decide: unknown vs treat as compliant. I'd prefer unknown here.
        return .init(
            name: "Screensaver inactivity timeout",
            status: .unknown,
            details: "missing pref \(screensaverDomain):\(keyIdleTime)"
        )
    }

    if current <= limit {
        return .init(
            name: "Screensaver inactivity timeout",
            status: .pass,
            details: "compliant (\(current)s ≤ \(limit)s)"
        )
    }

    return .init(
        name: "Screensaver inactivity timeout",
        status: .fail,
        details: "non-compliant (\(current)s > \(limit)s)"
    )
}

func checkScreensaverRequirePassword() -> CheckResult {
    guard let setting = readScreenLockSetting() else {
        return .init(name: "Screensaver password required", status: .unknown, details: "Could not read screen lock status")
    }

    switch setting {
    case .off:
        return .init(name: "Screensaver password required", status: .fail, details: "screen lock is off")
    case .immediate:
        return .init(name: "Screensaver password required", status: .pass, details: "screen lock is immediate")
    case .seconds(let s):
        return .init(name: "Screensaver password required", status: .pass, details: "screen lock delay is \(s)s")
    }
}

func checkScreensaverPasswordDelay(passwordDelay: Int) -> CheckResult {
    let target = max(passwordDelay, 0)

    guard let setting = readScreenLockSetting() else {
        return .init(name: "Screensaver password delay", status: .unknown, details: "Could not read screen lock status")
    }

    switch setting {
    case .off:
        return .init(name: "Screensaver password delay", status: .fail, details: "screen lock is off")
    case .immediate:
        return target == 0
            ? .init(name: "Screensaver password delay", status: .pass, details: "compliant (immediate)")
            : .init(name: "Screensaver password delay", status: .pass, details: "compliant (immediate ≤ \(target)s)")
    case .seconds(let current):
        return current <= target
            ? .init(name: "Screensaver password delay", status: .pass, details: "compliant (\(current)s ≤ \(target)s)")
            : .init(name: "Screensaver password delay", status: .fail, details: "non-compliant (\(current)s > \(target)s)")
    }
}

// TODO: unattended enforcement requires secure user-auth strategy or MDM profile
func checkScreensaverAskForPassword() -> CheckResult {
    guard let current = ManagedPrefs.boolEffective(domain: screensaverDomain, key: keyAskForPassword) else {
        return .init(
            name: "Screensaver password required",
            status: .unknown,
            details: "missing pref \(screensaverDomain):\(keyAskForPassword)"
        )
    }

    return .init(
        name: "Screensaver password required",
        status: current ? .pass : .fail,
        details: current ? "enabled" : "disabled"
    )
}

func checkScreensaverAskForPasswordDelay(passwordDelay: Int) -> CheckResult {
    let limit = max(passwordDelay, 0)

    // If password isn’t required, delay is not meaningful
    if let pw = ManagedPrefs.boolEffective(domain: screensaverDomain, key: keyAskForPassword),
       pw == false {
        return .init(
            name: "Screensaver password delay",
            status: .skipped,
            details: "not applicable (askForPassword=false)"
        )
    }

    guard let current = ManagedPrefs.intEffective(domain: screensaverDomain, key: keyAskForPasswordDelay) else {
        return .init(
            name: "Screensaver password delay",
            status: .unknown,
            details: "missing pref \(screensaverDomain):\(keyAskForPasswordDelay)"
        )
    }

    if current <= limit {
        return .init(
            name: "Screensaver password delay",
            status: .pass,
            details: "compliant (\(current)s ≤ \(limit)s)"
        )
    }

    return .init(
        name: "Screensaver password delay",
        status: .fail,
        details: "non-compliant (\(current)s > \(limit)s)"
    )
}

// MARK: - Enforces

func enforceScreensaverIdle(logger: HardenLogger, saverDelay: Int) -> CheckResult {
    let target = max(saverDelay, 1)

    if let result = writeScreenSaverPref(
        logger: logger,
        key: keyIdleTime,
        valueArgs: ["-int", "\(target)"]
    ) {
        debugScreenSaverSources(logger: logger, key: keyIdleTime)

        return .init(
            name: "Screensaver inactivity timeout",
            status: result.status,
            details: result.details
        )
    }

    return .init(
        name: "Screensaver inactivity timeout",
        status: .pass,
        details: "set \(keyIdleTime)=\(target)s"
    )
}

func enforceScreensaverAskForPassword(logger: HardenLogger, enabled: Bool = true) -> CheckResult {
    if let result = writeScreenSaverPref(
        logger: logger,
        key: keyAskForPassword,
        valueArgs: ["-bool", enabled ? "true" : "false"]
    ) {
        return .init(
            name: "Screensaver password required",
            status: result.status,
            details: result.details
        )
    }

    return .init(
        name: "Screensaver password required",
        status: .pass,
        details: "set \(keyAskForPassword)=\(enabled ? "1" : "0")"
    )
}

func enforceScreensaverAskForPasswordDelay(logger: HardenLogger, passwordDelay: Int) -> CheckResult {
    let target = max(passwordDelay, 0)

    let pre = enforceScreensaverAskForPassword(logger: logger, enabled: true)
    if pre.status != .pass {
        return .init(
            name: "Screensaver password delay",
            status: pre.status,
            details: "precondition failed: could not enable askForPassword (\(pre.details))"
        )
    }

    if let result = writeScreenSaverPref(
        logger: logger,
        key: keyAskForPasswordDelay,
        valueArgs: ["-int", "\(target)"]
    ) {
        return .init(
            name: "Screensaver password delay",
            status: result.status,
            details: result.details
        )
    }

    return .init(
        name: "Screensaver password delay",
        status: .pass,
        details: "enabled askForPassword + set \(keyAskForPasswordDelay)=\(target)s"
    )
}

// MARK: Helper Sync CFPrefs
private func syncScreenSaverPrefs() {
    CFPreferencesSynchronize(screensaverDomain as CFString,
                             ManagedPrefs.effectiveUserScope(),
                             kCFPreferencesCurrentHost)
}
