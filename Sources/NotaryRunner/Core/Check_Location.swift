import Foundation

// MARK: 2.5.3 Location Services

func checkLocationServicesEnabled() -> CheckResult {

    do {
        let r = try Shell.run(
            "/bin/launchctl",
            ["print", "system/com.apple.locationd"],
            timeout: 10
        )

        let text = (r.stdout + r.stderr).lowercased()

        if !text.contains("state = running") {
            return .init(
                name: "Location Services",
                status: .fail,
                details: "locationd daemon not running."
            )
        }

        let r2 = try Shell.run(
            "/usr/bin/defaults",
            ["read",
             "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.plist",
             "LocationServicesEnabled"],
            timeout: 5
        )

        if r2.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
            return .init(
                name: "Location Services",
                status: .pass,
                details: "Location services are enabled."
            )
        }

        return .init(
            name: "Location Services",
            status: .fail,
            details: "Location services disabled."
        )

    } catch {
        return .init(
            name: "Location Services",
            status: .unknown,
            details: "Location services check error: \(error)"
        )
    }
}

func enforceLocationServicesEnabled(logger: HardenLogger) -> CheckResult {

    _ = try? Shell.run(
        "/bin/launchctl",
        ["enable", "system/com.apple.locationd"],
        timeout: 10,
        logger: logger
    )

    _ = try? Shell.run(
        "/bin/launchctl",
        ["bootstrap",
         "system",
         "/System/Library/LaunchDaemons/com.apple.locationd.plist"],
        timeout: 10,
        logger: logger
    )

    _ = try? Shell.run(
        "/usr/bin/defaults",
        ["write",
         "/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.plist",
         "LocationServicesEnabled",
         "-bool",
         "true"],
        timeout: 5,
        logger: logger
    )

    _ = try? Shell.run(
        "/bin/launchctl",
        ["kickstart", "-k", "system/com.apple.locationd"],
        timeout: 10,
        logger: logger
    )
    // Alternative:
     //_ = try? Shell.run("/usr/bin/killall", ["locationd"], timeout: 5)

    return checkLocationServicesEnabled()
}
