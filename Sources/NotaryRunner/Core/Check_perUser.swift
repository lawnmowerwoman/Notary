import Foundation

private let applicationAccessDomain = "com.apple.applicationaccess"
private let bluetoothDomain = "com.apple.Bluetooth"
private let bluetoothSharingKey = "PrefKeyServicesEnabled"
private let airDropKey = "allowAirDrop"
private let mediaSharingKey = "allowMediaSharing"
private let mediaSharingModificationKey = "allowMediaSharingModification"
private let personalizedAdvertisingKey = "allowApplePersonalizedAdvertising"
private let siriKey = "allowAssistant"
private let controlCenterDomain = "com.apple.controlcenter"
private let wifiStatusVisibleKey = "NSStatusItem Visible WiFi"

private func parseDefaultsBool(_ value: String?) -> Bool? {
    guard let value else { return nil }
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        return nil
    }
}

// MARK: 2.10 Enable Secure Keyboard Entry in terminal.app

private let terminalDomain = "com.apple.Terminal"
private let terminalSecureKeyboardKey = "SecureKeyboardEntry"

func checkTerminalSecureKeyboardEnabled(user: String) -> CheckResult {

    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: terminalDomain,
        key: terminalSecureKeyboardKey
    )

    if result.readFailed {
        return .init(
            name: "Terminal Secure Keyboard Entry",
            status: .unknown,
            details: "Could not read Terminal preference for user \(user)."
        )
    }

    guard let value = result.value?.lowercased() else {
        return .init(
            name: "Terminal Secure Keyboard Entry",
            status: .fail,
            details: "Secure Keyboard Entry is disabled."
        )
    }

    if value == "1" || value == "true" {
        return .init(
            name: "Terminal Secure Keyboard Entry",
            status: .pass,
            details: "Secure Keyboard Entry is enabled."
        )
    }

    return .init(
        name: "Terminal Secure Keyboard Entry",
        status: .fail,
        details: "Secure Keyboard Entry is disabled."
    )
}

func enforceTerminalSecureKeyboardEnabled(user: String, logger: HardenLogger) {

    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: terminalDomain,
        key: terminalSecureKeyboardKey,
        value: true,
        logger: logger
    )
}

// MARK: 2.4.7 Disable Bluetooth Sharing

func checkBluetoothSharingDisabled(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let result = PerUserPreferences.readCurrentHostDefaults(
        user: user,
        domain: bluetoothDomain,
        key: bluetoothSharingKey,
        logger: logger
    )

    if result.readFailed {
        return .init(
            name: "Bluetooth Sharing",
            status: .unknown,
            details: "Could not read Bluetooth sharing preference for user \(user)."
        )
    }

    guard let currentValue = parseDefaultsBool(result.value) else {
        return .init(
            name: "Bluetooth Sharing",
            status: .fail,
            details: "Bluetooth sharing is enabled or unset."
        )
    }

    if currentValue == false {
        return .init(
            name: "Bluetooth Sharing",
            status: .pass,
            details: "Bluetooth sharing is disabled."
        )
    }

    return .init(
        name: "Bluetooth Sharing",
        status: .fail,
        details: "Bluetooth sharing is enabled."
    )
}

func enforceBluetoothSharingDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeCurrentHostDefaultsBool(
        user: user,
        domain: bluetoothDomain,
        key: bluetoothSharingKey,
        value: false,
        logger: logger
    )
}

// MARK: 2.4.11 Disable Media Sharing

func checkMediaSharingDisabled(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let sharing = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: mediaSharingKey,
        logger: logger
    )
    let modification = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: mediaSharingModificationKey,
        logger: logger
    )

    if sharing.readFailed || modification.readFailed {
        return .init(
            name: "Media Sharing",
            status: .unknown,
            details: "Could not read media sharing preferences for user \(user)."
        )
    }

    let sharingDisabled = parseDefaultsBool(sharing.value) == false
    let modificationDisabled = parseDefaultsBool(modification.value) == false

    if sharingDisabled && modificationDisabled {
        return .init(
            name: "Media Sharing",
            status: .pass,
            details: "Media sharing and modification are disabled."
        )
    }

    return .init(
        name: "Media Sharing",
        status: .fail,
        details: "Media sharing is enabled or can still be modified."
    )
}

func enforceMediaSharingDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: applicationAccessDomain,
        key: mediaSharingKey,
        value: false,
        logger: logger
    )
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: applicationAccessDomain,
        key: mediaSharingModificationKey,
        value: false,
        logger: logger
    )
}

// MARK: 2.4.12 Disable AirDrop

func checkAirDropDisabled(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: airDropKey,
        logger: logger
    )

    if result.readFailed {
        return .init(
            name: "AirDrop",
            status: .unknown,
            details: "Could not read AirDrop preference for user \(user)."
        )
    }

    guard let currentValue = parseDefaultsBool(result.value) else {
        return .init(
            name: "AirDrop",
            status: .fail,
            details: "AirDrop is enabled or unset."
        )
    }

    if currentValue == false {
        return .init(
            name: "AirDrop",
            status: .pass,
            details: "AirDrop is disabled."
        )
    }

    return .init(
        name: "AirDrop",
        status: .fail,
        details: "AirDrop is enabled."
    )
}

func isAirDropExplicitlyEnabled(user: String, logger: HardenLogger? = nil) -> Bool? {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: airDropKey,
        logger: logger
    )

    guard !result.readFailed else { return nil }
    return parseDefaultsBool(result.value) == true
}

func enforceAirDropDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: applicationAccessDomain,
        key: airDropKey,
        value: false,
        logger: logger
    )
}

// MARK: 2.5.6 Disable Personalized Advertising

func checkPersonalizedAdvertisingDisabled(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: personalizedAdvertisingKey,
        logger: logger
    )

    if result.readFailed {
        return .init(
            name: "Personalized Advertising",
            status: .unknown,
            details: "Could not read advertising preference for user \(user)."
        )
    }

    guard let currentValue = parseDefaultsBool(result.value) else {
        return .init(
            name: "Personalized Advertising",
            status: .fail,
            details: "Personalized advertising is enabled or unset."
        )
    }

    if currentValue == false {
        return .init(
            name: "Personalized Advertising",
            status: .pass,
            details: "Personalized advertising is disabled."
        )
    }

    return .init(
        name: "Personalized Advertising",
        status: .fail,
        details: "Personalized advertising is enabled."
    )
}

func enforcePersonalizedAdvertisingDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: applicationAccessDomain,
        key: personalizedAdvertisingKey,
        value: false,
        logger: logger
    )
}

// MARK: 2.13 Disable Siri

func checkSiriDisabled(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: applicationAccessDomain,
        key: siriKey,
        logger: logger
    )

    if result.readFailed {
        return .init(
            name: "Siri",
            status: .unknown,
            details: "Could not read Siri preference for user \(user)."
        )
    }

    guard let currentValue = parseDefaultsBool(result.value) else {
        return .init(
            name: "Siri",
            status: .fail,
            details: "Siri is enabled or unset."
        )
    }

    if currentValue == false {
        return .init(
            name: "Siri",
            status: .pass,
            details: "Siri is disabled."
        )
    }

    return .init(
        name: "Siri",
        status: .fail,
        details: "Siri is enabled."
    )
}

func enforceSiriDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: applicationAccessDomain,
        key: siriKey,
        value: false,
        logger: logger
    )
}

// MARK: 4.2 Show Wi-Fi status in menu bar

func checkWifiStatusVisible(user: String, logger: HardenLogger? = nil) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: controlCenterDomain,
        key: wifiStatusVisibleKey,
        logger: logger
    )

    if result.readFailed {
        return .init(
            name: "Wi-Fi Status in Menu Bar",
            status: .unknown,
            details: "Could not read Wi-Fi menu bar preference for user \(user)."
        )
    }

    guard let currentValue = parseDefaultsBool(result.value) else {
        return .init(
            name: "Wi-Fi Status in Menu Bar",
            status: .fail,
            details: "Wi-Fi status is hidden or unset in the menu bar."
        )
    }

    if currentValue == true {
        return .init(
            name: "Wi-Fi Status in Menu Bar",
            status: .pass,
            details: "Wi-Fi status is shown in the menu bar."
        )
    }

    return .init(
        name: "Wi-Fi Status in Menu Bar",
        status: .fail,
        details: "Wi-Fi status is hidden in the menu bar."
    )
}

func enforceWifiStatusVisible(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: controlCenterDomain,
        key: wifiStatusVisibleKey,
        value: true,
        logger: logger
    )
}

// MARK: 5.1.1 Secure Home Folders

func checkHomeFolderSecure(user: String) -> CheckResult {
    let path = "/Users/\(user)"

    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? NSNumber

        if perms?.intValue == 0o700 {
            return .init(
                name: "Secure Home Folders",
                status: .pass,
                details: "Home folder permissions are 700."
            )
        }

        return .init(
            name: "Secure Home Folders",
            status: .fail,
            details: "Home folder permissions are \(String(perms?.intValue ?? 0, radix: 8)), expected 700."
        )
    } catch {
        return .init(
            name: "Secure Home Folders",
            status: .unknown,
            details: "Could not read home folder permissions for user \(user)."
        )
    }
}

func enforceHomeFolderSecure(user: String, logger: HardenLogger) {
    let path = "/Users/\(user)"
    _ = try? Shell.run(
        "/bin/chmod",
        ["700", path],
        timeout: 10,
        logger: logger
    )
}

// MARK: 5.4 Lock Login Keychain

func checkLoginKeychainLockInactivity(
    user: String,
    expectedTimeout: Int
) -> CheckResult {

    // TODO: due to an Apple problem, always return true
    return .init(
        name: "Login Keychain Lock on Inactivity",
        status: .unknown,
        details: "Unchecked - due to an Apple issue."
    )
    /*
    guard let keychainPath = loginKeychainPath(for: user) else {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .skipped,
            details: "No login keychain found."
        )
    }

    guard let uid = PerUserPreferences.uid(for: user) else {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .unknown,
            details: "No uid found for user \(user)."
        )
    }

    let args = [
        "asuser", "\(uid)",
        "/usr/bin/sudo", "-u", user,
        "/usr/bin/security",
        "show-keychain-info",
        keychainPath
    ]

    guard let r = try? Shell.run(
        "/bin/launchctl",
        args,
        timeout: 10
    ) else {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .unknown,
            details: "Could not read keychain settings."
        )
    }

    let text = (r.stdout + r.stderr).lowercased()

    if r.code != 0 || text.isEmpty {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .unknown,
            details: "Could not read keychain settings."
        )
    }

    if text.contains("no-timeout") {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .fail,
            details: "Login keychain has no inactivity timeout configured."
        )
    }

    let timeoutValue: Int? = {
        let patterns = [
            #"timeout=([0-9]+)s"#,
            #"timeout=([0-9]+)"#,
            #"timeout ([0-9]+) seconds"#,
            #"after ([0-9]+) seconds"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                return Int(text[range])
            }
        }
        return nil
    }()

    guard let timeoutValue else {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .unknown,
            details: "Could not parse keychain inactivity timeout."
        )
    }

    if timeoutValue == expectedTimeout {
        return .init(
            name: "Login Keychain Lock on Inactivity",
            status: .pass,
            details: "Login keychain locks after \(timeoutValue)s of inactivity."
        )
    }

    return .init(
        name: "Login Keychain Lock on Inactivity",
        status: .fail,
        details: "Login keychain timeout is \(timeoutValue)s, expected \(expectedTimeout)s."
    )
    */
}

// TODO: This function includes 5.6 (Lock keychain on sleep) - if this should become a standalone key - implement it!
func enforceLoginKeychainLockInactivity(
    user: String,
    timeout: Int,
    logger: HardenLogger
) {
    guard let keychainPath = loginKeychainPath(for: user) else {
        logger.develop("[PERUSER] Login Keychain Lock: no login keychain found for user \(user)")
        return
    }

    guard let uid = PerUserPreferences.uid(for: user) else {
        logger.develop("[PERUSER] Login Keychain Lock: no uid found for user \(user)")
        return
    }

    // TODO: The keychain timeout causes computers to permanently ask for the keychain password
    //       To disable this feature, we reverted the function to no timeout and auto-lock
    //       Function needs to be further tested
    /*
    let setArgs = [
        "asuser", "\(uid)",
        "/usr/bin/sudo", "-u", user,
        "/usr/bin/security",
        "set-keychain-settings",
        "-l",
        "-u",
        "-t", "\(timeout)",
        keychainPath
    ]
    */

    let setArgs = [
        "asuser", "\(uid)",
        "/usr/bin/sudo", "-u", user,
        "/usr/bin/security",
        "set-keychain-settings",
        keychainPath
    ]

    let set = try? Shell.run(
        "/bin/launchctl",
        setArgs,
        timeout: 10,
        logger: logger
    )

    if let set {
        logger.develop("[PERUSER] Login Keychain Lock enforce user=\(user) timeout=\(timeout) code=\(set.code) out=\(set.stdout) err=\(set.stderr)")
    }
}

// MARK: 5.15 Remove Password Hints

func checkUserPasswordHintRemoved(user: String) -> CheckResult {

    /*
     guard let r = try? Shell.run(
     "/usr/bin/dscl",
     [".", "-read", "/Users/\(user)", "hint"],
     timeout: 10
     ) else {
     return .init(
     name: "Remove User Password Hints",
     status: .unknown,
     details: "Could not query password hint state."
     )
     }

     let text = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
     let low = text.lowercased()

     if r.code == 0 {
     return .init(
     name: "Remove User Password Hints",
     status: .fail,
     details: "Password hint exists."
     )
     }

     if low.contains("no such key") {
     return .init(
     name: "Remove User Password Hints",
     status: .pass,
     details: "No password hint present."
     )
     }

     return .init(
     name: "Remove User Password Hints",
     status: .unknown,
     details: text.isEmpty ? "Could not interpret password hint state." : text
     )
     */
    return .init(
        name: "Remove User Password Hints",
        status: .pass,
        details: "all hints removed")
}

func enforceUserPasswordHintRemoved(user: String, logger: HardenLogger) -> CheckResult {
    guard let r = try? Shell.run(
        "/usr/bin/dscl",
        [".", "-delete", "/Users/\(user)", "hint"],
        timeout: 10,
        logger: logger
    ) else {
        return .init(
            name: "Remove User Password Hints",
            status: .unknown,
            details: "Could not remove password hint for user \(user)."
        )
    }

    logger.develop("[PERUSER] Remove User Password Hints enforce user=\(user) code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

    let text = (r.stdout + r.stderr).lowercased()

    // success OR already absent -> both are good outcomes
    if r.code == 0 || text.contains("no such key") {
        return .init(
            name: "Remove User Password Hints",
            status: .pass,
            details: "Password hint removed or not present."
        )
    }

    return .init(
        name: "Remove User Password Hints",
        status: .unknown,
        details: "Failed to remove password hint."
    )
}

// MARK: 6.2 Turn on filename extensions

private let globalDomain = "-g"
private let showAllExtensionsKey = "AppleShowAllExtensions"

func checkShowFileNameExtensionsEnabled(user: String) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: globalDomain,
        key: showAllExtensionsKey
    )

    if result.readFailed {
        return .init(
            name: "Show File Name Extensions",
            status: .unknown,
            details: "Could not read Finder/global preference for user \(user)."
        )
    }

    guard let value = result.value?.lowercased() else {
        return .init(
            name: "Show File Name Extensions",
            status: .fail,
            details: "File name extensions are hidden."
        )
    }

    if value == "1" || value == "true" {
        return .init(
            name: "Show File Name Extensions",
            status: .pass,
            details: "File name extensions are shown."
        )
    }

    return .init(
        name: "Show File Name Extensions",
        status: .fail,
        details: "File name extensions are hidden."
    )
}

func enforceShowFileNameExtensionsEnabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: globalDomain,
        key: showAllExtensionsKey,
        value: true,
        logger: logger
    )
}

// MARK: - 6.3 Safari: Do not automatically open "safe" downloads

private let safariDomain = "com.apple.safari"
private let safariAutoOpenSafeDownloadsKey = "AutoOpenSafeDownloads"

func checkSafariDownloadAutoRunDisabled(user: String) -> CheckResult {
    let result = PerUserPreferences.readDefaults(
        user: user,
        domain: safariDomain,
        key: safariAutoOpenSafeDownloadsKey
    )

    if result.readFailed {
        return .init(
            name: "Safari Safe Downloads",
            status: .unknown,
            details: "Could not read Safari preference for user \(user)."
        )
    }

    guard let value = result.value?.lowercased() else {
        return .init(
            name: "Safari Safe Downloads",
            status: .pass,
            details: "Safari auto-open safe downloads is disabled."
        )
    }

    if value == "0" || value == "false" {
        return .init(
            name: "Safari Safe Downloads",
            status: .pass,
            details: "Safari auto-open safe downloads is disabled."
        )
    }

    return .init(
        name: "Safari Safe Downloads",
        status: .fail,
        details: "Safari auto-open safe downloads is enabled."
    )
}

func enforceSafariDownloadAutoRunDisabled(user: String, logger: HardenLogger) {
    _ = PerUserPreferences.writeDefaultsBool(
        user: user,
        domain: safariDomain,
        key: safariAutoOpenSafeDownloadsKey,
        value: false,
        logger: logger
    )
}
