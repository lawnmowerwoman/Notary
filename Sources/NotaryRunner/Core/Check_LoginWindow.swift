import Foundation

private let loginWindowSecurityBannerKey = "LoginwindowText"

// MARK: 5.8 Automatic Login

func checkAutoLoginDisabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/com.apple.loginwindow", "autoLoginUser"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.isEmpty {
            return .init(
                name: "Automatic Login",
                status: .pass,
                details: "Automatic login is disabled."
            )
        }

        return .init(
            name: "Automatic Login",
            status: .fail,
            details: "Automatic login enabled for user \(value)."
        )
    } catch {
        // defaults read exits non-zero if key is missing -> this means disabled
        return .init(
            name: "Automatic Login",
            status: .pass,
            details: "Automatic login is disabled."
        )
    }
}

func enforceAutoLoginDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["delete", "/Library/Preferences/com.apple.loginwindow", "autoLoginUser"],
        timeout: 5,
        logger: logger
    )

    return checkAutoLoginDisabled()
}

// MARK: 5.16 Fast User Switching

func checkFastUserSwitchingDisabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/.GlobalPreferences", "MultipleSessionEnabled"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value == "0" || value == "false" {
            return .init(
                name: "Fast User Switching",
                status: .pass,
                details: "Fast user switching is disabled."
            )
        }

        return .init(
            name: "Fast User Switching",
            status: .fail,
            details: "Fast user switching is enabled."
        )
    } catch {
        // Missing key is usually equivalent to disabled
        return .init(
            name: "Fast User Switching",
            status: .pass,
            details: "Fast user switching is disabled."
        )
    }
}

func enforceFastUserSwitchingDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/.GlobalPreferences", "MultipleSessionEnabled", "-bool", "false"],
        timeout: 5,
        logger: logger
    )

    return checkFastUserSwitchingDisabled()
}

// MARK: 6.1.1 Show full name for login window

func checkLoginWindowFullNameEnabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/com.apple.loginwindow", "SHOWFULLNAME"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value == "1" || value == "true" {
            return .init(
                name: "Login Window Full Name",
                status: .pass,
                details: "Login window requires full name and password."
            )
        }

        return .init(
            name: "Login Window Full Name",
            status: .fail,
            details: "Login window shows user list / avatars."
        )
    } catch {
        return .init(
            name: "Login Window Full Name",
            status: .fail,
            details: "SHOWFULLNAME not configured."
        )
    }
}

func enforceLoginWindowFullNameEnabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/com.apple.loginwindow", "SHOWFULLNAME", "-bool", "true"],
        timeout: 5,
        logger: logger
    )

    return checkLoginWindowFullNameEnabled()
}

// MARK: Security banner / login window text

func checkLoginWindowSecurityBanner(expectedText: String) -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/com.apple.loginwindow", loginWindowSecurityBannerKey],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == expectedText {
            return .init(
                name: "Login Window Security Banner",
                status: .pass,
                details: "login window security text matches the configured banner."
            )
        }

        if value.isEmpty {
            return .init(
                name: "Login Window Security Banner",
                status: .fail,
                details: "login window security text is empty."
            )
        }

        return .init(
            name: "Login Window Security Banner",
            status: .fail,
            details: "login window security text differs from the configured banner."
        )
    } catch {
        return .init(
            name: "Login Window Security Banner",
            status: .fail,
            details: "login window security text is not configured."
        )
    }
}

func enforceLoginWindowSecurityBanner(expectedText: String, logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/com.apple.loginwindow", loginWindowSecurityBannerKey, "-string", expectedText],
        timeout: 5,
        logger: logger
    )

    return checkLoginWindowSecurityBanner(expectedText: expectedText)
}

// MARK: 6.1.2 Password Hints

func checkPasswordHintsDisabled() -> CheckResult {
    guard let r = try? Shell.run(
        "/usr/bin/defaults",
        ["read", "/Library/Preferences/com.apple.loginwindow", "RetriesUntilHint"],
        timeout: 5
    ) else {
        return .init(
            name: "Password Hints",
            status: .pass,
            details: "Password hints are disabled."
        )
    }

    let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    if value.isEmpty {
        return .init(
            name: "Password Hints",
            status: .pass,
            details: "Password hints are disabled."
        )
    }

    if let n = Int(value) {
        if n == 0 {
            return .init(
                name: "Password Hints",
                status: .pass,
                details: "Password hints are disabled."
            )
        }

        return .init(
            name: "Password Hints",
            status: .fail,
            details: "Password hints are enabled (RetriesUntilHint=\(n))."
        )
    }

    return .init(
        name: "Password Hints",
        status: .unknown,
        details: "Could not interpret RetriesUntilHint=\(value)"
    )
}

func enforcePasswordHintsDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/com.apple.loginwindow", "RetriesUntilHint", "-int", "0"],
        timeout: 5,
        logger: logger
    )

    return checkPasswordHintsDisabled()
}

// MARK: 6.1.3 Guest account

func checkGuestUserDisabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/com.apple.loginwindow", "GuestEnabled"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value == "0" || value == "false" {
            return .init(
                name: "Guest User",
                status: .pass,
                details: "Guest user is disabled."
            )
        }

        return .init(
            name: "Guest User",
            status: .fail,
            details: "Guest user is enabled."
        )
    } catch {
        return .init(
            name: "Guest User",
            status: .pass,
            details: "Guest user is disabled."
        )
    }
}

func enforceGuestUserDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/com.apple.loginwindow", "GuestEnabled", "-bool", "false"],
        timeout: 5,
        logger: logger
    )

    return checkGuestUserDisabled()
}

// MARK: 6.1.4 Guest access to shares

func checkGuestAccessToSharesDisabled() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/SystemConfiguration/com.apple.smb.server", "AllowGuestAccess"],
            timeout: 5
        )

        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value == "0" || value == "false" {
            return .init(
                name: "Guest Access to Shares",
                status: .pass,
                details: "Guest access to shares is disabled."
            )
        }

        return .init(
            name: "Guest Access to Shares",
            status: .fail,
            details: "Guest access to shares is enabled."
        )
    } catch {
        return .init(
            name: "Guest Access to Shares",
            status: .pass,
            details: "Guest access to shares is disabled."
        )
    }
}

func enforceGuestAccessToSharesDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write", "/Library/Preferences/SystemConfiguration/com.apple.smb.server", "AllowGuestAccess", "-bool", "false"],
        timeout: 5,
        logger: logger
    )

    return checkGuestAccessToSharesDisabled()
}

// MARK: 6.1.5 Remove Guest homefolder

func checkGuestHomeRemoved() -> CheckResult {
    let fm = FileManager.default
    let path = "/Users/Guest"

    if fm.fileExists(atPath: path) {
        return .init(
            name: "Guest Home Folder",
            status: .fail,
            details: "Guest home folder exists at \(path)."
        )
    }

    return .init(
        name: "Guest Home Folder",
        status: .pass,
        details: "Guest home folder is absent."
    )
}

func enforceGuestHomeRemoved(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run(
        "/bin/rm",
        ["-rf", "/Users/Guest"],
        timeout: 10,
        logger: logger
    )

    return checkGuestHomeRemoved()
}
