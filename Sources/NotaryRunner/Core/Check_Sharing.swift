import Foundation

// MARK: Remote Apple Events — 2.4.1
func checkRemoteAppleEventsOff() -> CheckResult {
    checkSystemsetupOff(
        name: "Remote Apple Events",
        getArgument: "-getremoteappleevents"
    )
}

func enforceRemoteAppleEventsOff(logger: HardenLogger) -> CheckResult {
    enforceSystemsetupOff(
        name: "Remote Apple Events",
        setArguments: ["-setremoteappleevents", "off"],
        logger: logger
    )
}

// MARK: Internet Sharing — 2.4.2

func checkInternetSharingOff() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            ["read", "/Library/Preferences/SystemConfiguration/com.apple.nat", "NAT"],
            timeout: 10
        )

        let combined = [r.stdout, r.stderr].joined(separator: "\n")

        if combined.contains("Enabled = 1;") {
            return .init(name: "Internet Sharing", status: .fail, details: "Internet Sharing is enabled.")
        }

        // If the NAT dict is missing or does not show Enabled=1, treat as disabled
        return .init(name: "Internet Sharing", status: .pass, details: "Internet Sharing is disabled.")
    } catch {
        return .init(name: "Internet Sharing", status: .unknown, details: "defaults read error: \(error)")
    }
}

func enforceInternetSharingOff(logger: HardenLogger) -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/defaults",
            [
                "write",
                "/Library/Preferences/SystemConfiguration/com.apple.nat",
                "NAT",
                "-dict",
                "Enabled",
                "-int",
                "0"
            ],
            timeout: 15,
            logger: logger
        )

        if r.didTimeout {
            logger.info("[ENFORCE] Internet Sharing timed out")
            return .init(name: "Internet Sharing", status: .timedOut, details: "Internet Sharing enforce timed out")
        }

        logger.info("[ENFORCE] Internet Sharing code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code == 0 {
            return .init(name: "Internet Sharing", status: .pass, details: "Internet Sharing was enabled. Fixed.")
        }

        let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
        return .init(
            name: "Internet Sharing",
            status: .unknown,
            details: combined.isEmpty ? "Internet Sharing is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: "Internet Sharing", status: .unknown, details: "Internet Sharing enforce error: \(error)")
    }
}

// MARK: Screen Sharing — 2.4.3

func checkScreenSharingOff() -> CheckResult {
    checkLaunchctlServiceDisabled(
        name: "Screen Sharing",
        label: "com.apple.screensharing"
    )
}

func enforceScreenSharingOff(logger: HardenLogger) -> CheckResult {
    enforceLaunchctlServiceDisabled(
        name: "Screen Sharing",
        label: "com.apple.screensharing",
        logger: logger
    )
}

// MARK: Printer Sharing — 2.4.4

func checkPrinterSharingOff() -> CheckResult {
    do {
        let r = try Shell.run("/usr/sbin/cupsctl", [], timeout: 10)

        if r.stdout.contains("_share_printers=1") {
            return .init(name: "Printer Sharing", status: .fail, details: "Printer Sharing is enabled.")
        }

        return .init(name: "Printer Sharing", status: .pass, details: "Printer Sharing is disabled.")
    } catch {
        return .init(name: "Printer Sharing", status: .unknown, details: "cupsctl error: \(error)")
    }
}

func enforcePrinterSharingOff(logger: HardenLogger) -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/sbin/cupsctl",
            ["--no-share-printers"],
            timeout: 15,
            logger: logger
        )

        if r.didTimeout {
            logger.info("[ENFORCE] Printer Sharing timed out")
            return .init(name: "Printer Sharing", status: .timedOut, details: "Printer Sharing enforce timed out")
        }

        logger.info("[ENFORCE] Printer Sharing code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code == 0 {
            return .init(name: "Printer Sharing", status: .pass, details: "Printer Sharing was enabled. Fixed.")
        }

        let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")

        return .init(
            name: "Printer Sharing",
            status: .unknown,
            details: combined.isEmpty ? "Printer Sharing is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: "Printer Sharing", status: .unknown, details: "Printer Sharing enforce error: \(error)")
    }
}

// MARK: CD/DVD Sharing — 2.4.6

func checkDVDSharingOff() -> CheckResult {
    checkLaunchctlServiceDisabled(
        name: "CD/DVD Sharing",
        label: "com.apple.ODSAgent"
    )
}

func enforceDVDSharingOff(logger: HardenLogger) -> CheckResult {
    enforceLaunchctlServiceDisabled(
        name: "CD/DVD Sharing",
        label: "com.apple.ODSAgent",
        logger: logger
    )
}

// MARK: File Sharing — 2.4.8

func checkFileSharingOff() -> CheckResult {
    checkLaunchctlServiceDisabled(
        name: "File Sharing",
        label: "com.apple.smbd"
    )
}

func enforceFileSharingOff(logger: HardenLogger) -> CheckResult {
    enforceLaunchctlServiceDisabled(
        name: "File Sharing",
        label: "com.apple.smbd",
        logger: logger
    )
}

// MARK: Remote Management — 2.4.9

func checkRemoteManagementOff() -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/pgrep",
            ["-f", "/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent"],
            timeout: 10
        )

        if r.code == 0 {
            return .init(name: "Remote Management", status: .fail, details: "Remote Management is enabled.")
        }

        return .init(name: "Remote Management", status: .pass, details: "Remote Management is disabled.")
    } catch {
        return .init(name: "Remote Management", status: .unknown, details: "pgrep error: \(error)")
    }
}

func enforceRemoteManagementOff(logger: HardenLogger) -> CheckResult {
    do {
        let r = try Shell.run(
            "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart",
            ["-deactivate", "-stop"],
            timeout: 20,
            logger: logger
        )

        if r.didTimeout {
            logger.info("[ENFORCE] Remote Management timed out")
            return .init(name: "Remote Management", status: .timedOut, details: "Remote Management enforce timed out")
        }

        logger.info("[ENFORCE] Remote Management code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code == 0 {
            return .init(name: "Remote Management", status: .pass, details: "Remote Management was enabled. Fixed.")
        }

        let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")
        return .init(
            name: "Remote Management",
            status: .unknown,
            details: combined.isEmpty ? "Remote Management is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: "Remote Management", status: .unknown, details: "Remote Management enforce error: \(error)")
    }
}

// MARK: Content Caching — 2.4.10

func checkContentCachingOff() -> CheckResult {
    do {
        let r = try Shell.run("/usr/bin/AssetCacheManagerUtil", ["status"], timeout: 10)

        let lines = r.stdout.split(separator: "\n")

        if let activatedLine = lines.first(where: { $0.contains("Activated") }) {
            if activatedLine.contains("true") {
                return .init(name: "Content Caching", status: .fail, details: "Content Caching is enabled.")
            } else {
                return .init(name: "Content Caching", status: .pass, details: "Content Caching is disabled.")
            }
        }

        return .init(name: "Content Caching", status: .unknown, details: "Could not determine cache status")
    } catch {
        return .init(name: "Content Caching", status: .unknown, details: "AssetCacheManagerUtil error: \(error)")
    }
}

func enforceContentCachingOff(logger: HardenLogger) -> CheckResult {
    do {
        let r = try Shell.run(
            "/usr/bin/AssetCacheManagerUtil",
            ["deactivate"],
            timeout: 20,
            logger: logger
        )

        if r.didTimeout {
            logger.info("[ENFORCE] Content Caching timed out")
            return .init(name: "Content Caching", status: .timedOut, details: "Content Caching enforce timed out")
        }

        logger.info("[ENFORCE] Content Caching code=\(r.code) out=\(r.stdout) err=\(r.stderr)")

        if r.code == 0 {
            return .init(name: "Content Caching", status: .pass, details: "Content Caching was enabled. Fixed.")
        }

        let combined = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: " | ")

        return .init(
            name: "Content Caching",
            status: .unknown,
            details: combined.isEmpty ? "Content Caching is enabled. Could not fix." : combined
        )
    } catch {
        return .init(name: "Content Caching", status: .unknown, details: "Content Caching enforce error: \(error)")
    }
}

// MARK: 4.1 Bonjour Advertising

func checkBonjourAdvertisingDisabled() -> CheckResult {
    let tool = "/usr/sbin/systemsetup"

    guard let r = try? Shell.run(tool, ["-getbonjouradvertising"], timeout: 10) else {
        return .init(name: "Bonjour Advertising", status: .unknown, details: "systemsetup failed")
    }

    let text = preferredFirewallOutput(r).lowercased()

    if text.contains("off") {
        return .init(name: "Bonjour Advertising", status: .pass, details: "Bonjour advertising is disabled.")
    }

    if text.contains("on") {
        return .init(name: "Bonjour Advertising", status: .fail, details: "Bonjour advertising is enabled.")
    }

    return .init(name: "Bonjour Advertising", status: .unknown, details: text)
}

func enforceBonjourAdvertisingDisabled(logger: HardenLogger) -> CheckResult {
    return enforceSystemsetupOff(
        name: "Bonjour Advertising",
        setArguments: ["-setbonjouradvertising", "off"],
        logger: logger
    )
}

// MARK: 4.4 Apache HTTP Server

func checkApacheDisabled() -> CheckResult {
    do {
        let r = try Shell.run("/bin/launchctl", ["print", "system/org.apache.httpd"], timeout: 10)

        if r.code == 0 {
            return .init(name: "Apache HTTP Server", status: .fail, details: "Apache HTTP Server is enabled.")
        }

        return .init(name: "Apache HTTP Server", status: .pass, details: "Apache HTTP Server is disabled.")
    } catch {
        return .init(name: "Apache HTTP Server", status: .unknown, details: "launchctl error: \(error)")
    }
}

func enforceApacheDisabled(logger: HardenLogger) -> CheckResult {
    _ = try? Shell.run("/usr/sbin/apachectl", ["stop"], timeout: 10, logger: logger)
    return enforceLaunchctlServiceDisabled(
        name: "Apache HTTP Server",
        label: "org.apache.httpd",
        logger: logger
    )
}

// MARK: 4.5 NFS Server

func checkNFSServerDisabled() -> CheckResult {
    do {
        let r = try Shell.run("/bin/launchctl", ["print", "system/com.apple.nfsd"], timeout: 10)
        let text = (r.stdout + r.stderr).lowercased()
        if text.contains("state = running") {
            return .init(name: "NFS Server", status: .fail, details: "NFS Server is enabled.")
        }

        return .init(name: "NFS Server", status: .pass, details: "NFS Server is disabled.")
    } catch {
        return .init(name: "NFS Server", status: .unknown, details: "launchctl error: \(error)")
    }
}

func enforceNFSServerDisabled(logger: HardenLogger) -> CheckResult {

    _ = try? Shell.run("/bin/rm", ["-f", "/etc/exports"], timeout: 5, logger: logger)

    return enforceLaunchctlServiceDisabled(
        name: "NFS Server",
        label: "com.apple.nfsd",
        logger: logger
    )
}
