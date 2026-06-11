import Foundation

package struct ManagedConfig {
    package var orgName: String
    package var orgContact: String

    package var forceTimeServer: Bool
    package var timeServer: String?
    package var defaultTimeZone: String?

    package var systemUptimeWarnDays: Int
    package var systemUptimeMaxDays: Int
    package var sshClientAliveInterval: Int
    package var sshClientAliveCountMax: Int
    package var securityBannerText: String?
    package var expectedSecurityProducts: [String]

    package var sudoTimeout: Int
    package var screenSaverDelay: Int
    package var screenSaverPasswordDelay: Int

    package var perUser: ManagedPerUserConfig

    package static func from(rawSnapshot: [String: Any], logger: HardenLogger) -> ManagedConfig {
        func section(_ name: String) -> [String: Any] {
            rawSnapshot[name] as? [String: Any] ?? [:]
        }

        let org = section("Org")
        let time = section("TimeNTP")
        let system = section("System")
        let ssh = section("SSH")
        let login = section("LoginWindow")
        let environment = section("Environment")
        let ss = section("ScreenSaver")

        // Read raw
        let rawOrgName = (org["OrgName"] as? String)
        let rawOrgContact = (org["OrgContact"] as? String)

        let rawForceTS = time["ForceTimeServer"] as? Bool ?? false
        let rawTimeServer = time["TimeServer"] as? String
        let rawTZ = time["DefaultTimeZone"] as? String

        let rawSystemUptimeWarnDays = (system["SystemUptimeWarnDays"] as? Int) ?? 5
        let rawSystemUptimeMaxDays = (system["SystemUptimeMaxDays"] as? Int) ?? 0
        let rawSSHClientAliveInterval = (ssh["SSHClientAliveInterval"] as? Int) ?? 900
        let rawSSHClientAliveCountMax = (ssh["SSHClientAliveCountMax"] as? Int) ?? 0
        let rawSecurityBannerText = login["SecurityBannerText"] as? String
        let rawExpectedSecurityProducts = environment["ExpectedSecurityProducts"] as? String

        let rawSudoTimeout = (login["SudoTimeout"] as? Int) ?? 3
        let rawSSDelay = (ss["ScreenSaverDelay"] as? Int) ?? 1200
        let rawSSPasswordDelay = (ss["ScreenSaverPasswordDelay"] as? Int) ?? 5

        let pu = section("PerUser")

        // Normalize
        var cfg = ManagedConfig(
            orgName: (rawOrgName?.trimmedEmptyToNil) ?? "AnyOrg",
            orgContact: (rawOrgContact?.trimmedEmptyToNil) ?? "itsupport@any.org",
            forceTimeServer: rawForceTS,
            timeServer: rawTimeServer?.trimmedEmptyToNil,
            defaultTimeZone: rawTZ?.trimmedEmptyToNil,
            systemUptimeWarnDays: rawSystemUptimeWarnDays,
            systemUptimeMaxDays: rawSystemUptimeMaxDays,
            sshClientAliveInterval: rawSSHClientAliveInterval,
            sshClientAliveCountMax: rawSSHClientAliveCountMax,
            securityBannerText: rawSecurityBannerText?.trimmedEmptyToNil,
            expectedSecurityProducts: parseDelimitedList(rawExpectedSecurityProducts),
            sudoTimeout: rawSudoTimeout,
            screenSaverDelay: rawSSDelay,
            screenSaverPasswordDelay: rawSSPasswordDelay,
            perUser: ManagedPerUserConfig(
                disableBluetoothSharing: toPentabool(pu["DisableBluetoothSharing"]),
                disableMediaSharing: toPentabool(pu["DisableMediaSharing"]),
                disableAirDrop: toPentabool(pu["DisableAirDrop"]),
                airDropAutoDisableMinutes: (pu["AirDropAutoDisableMinutes"] as? Int) ?? 0,
                disableAdTracking: toPentabool(pu["DisableAdTracking"]),
                enableTerminalSecureKeyboard: toPentabool(pu["EnableTerminalSecureKeyboard"]),
                disableSiri: toPentabool(pu["DisableSiri"]),
                forceShowWifiStatus: toPentabool(pu["ForceShowWifiStatus"]),
                secureHomeFolders: toPentabool(pu["SecureHomeFolders"]),
                lockLoginKeychain: toPentabool(pu["LockLoginKeychain"]),
                removeUserPasswordHints: toPentabool(pu["RemoveUserPasswordHints"]),
                forceShowFileNameExtensions: toPentabool(pu["ForceShowFileNameExtensions"]),
                disableSafariDownloadAutoRun: toPentabool(pu["DisableSafariDownloadAutoRun"]),
                lockKeychainInactivity: (pu["LockKeychainInactivity"] as? Int) ?? 21600
            )
        )

        // Soft validate + clamp
        if cfg.sudoTimeout < 1 || cfg.sudoTimeout > 20 {
            logger.warn("SudoTimeout out of bounds (\(cfg.sudoTimeout)) – set to 3")
            cfg.sudoTimeout = 3
        }

        // Lower bounds
        if cfg.screenSaverDelay < 1 {
            logger.warn("ScreenSaverDelay below minimum (\(cfg.screenSaverDelay)s) – reset to 1200s for 2.3.1")
            cfg.screenSaverDelay = 1200
        }
        if cfg.screenSaverPasswordDelay < 0 {
            logger.warn("ScreenSaverPasswordDelay below minimum (\(cfg.screenSaverPasswordDelay)s) – reset to 5s for 5.9")
            cfg.screenSaverPasswordDelay = 5
        }

        // Upper bounds
        if cfg.screenSaverDelay > 1200 {
            logger.warn("ScreenSaverDelay above 20 minutes (\(cfg.screenSaverDelay)s) – clamped to 20 minutes for 2.3.1")
            cfg.screenSaverDelay = 1200
        }
        if cfg.screenSaverPasswordDelay > 300 {
            logger.warn("ScreenSaverPasswordDelay above 5 minutes (\(cfg.screenSaverPasswordDelay)s) – clamped to 5 minutes for 5.9")
            cfg.screenSaverPasswordDelay = 300
        }

        if cfg.forceTimeServer && (cfg.timeServer == nil) {
            logger.warn("TimeNTP.ForceTimeServer enabled but TimeNTP.TimeServer is missing")
        }
        if let tz = cfg.defaultTimeZone, TimeZone(identifier: tz) == nil {
            logger.warn("TimeNTP.DefaultTimeZone invalid: \(tz)")
        }

        if cfg.systemUptimeWarnDays < 3 {
            logger.warn("System.SystemUptimeWarnDays below minimum (\(cfg.systemUptimeWarnDays)) – set to 5")
            cfg.systemUptimeWarnDays = 5
        }
        if cfg.systemUptimeMaxDays < 0 {
            logger.warn("System.SystemUptimeMaxDays below minimum (\(cfg.systemUptimeMaxDays)) – disabled")
            cfg.systemUptimeMaxDays = 0
        }
        if cfg.systemUptimeMaxDays != 0 && cfg.systemUptimeMaxDays <= cfg.systemUptimeWarnDays {
            logger.warn("System.SystemUptimeMaxDays (\(cfg.systemUptimeMaxDays)) must be greater than warn threshold (\(cfg.systemUptimeWarnDays)) – disabled")
            cfg.systemUptimeMaxDays = 0
        }
        if cfg.sshClientAliveInterval < 60 {
            logger.warn("SSH.SSHClientAliveInterval below minimum (\(cfg.sshClientAliveInterval)) – set to 900")
            cfg.sshClientAliveInterval = 900
        }
        if cfg.sshClientAliveCountMax < 0 {
            logger.warn("SSH.SSHClientAliveCountMax below minimum (\(cfg.sshClientAliveCountMax)) – set to 0")
            cfg.sshClientAliveCountMax = 0
        }
        if cfg.perUser.airDropAutoDisableMinutes < 0 {
            logger.warn("PerUser.AirDropAutoDisableMinutes below minimum (\(cfg.perUser.airDropAutoDisableMinutes)) – disabled")
            cfg.perUser.airDropAutoDisableMinutes = 0
        }
        if cfg.perUser.airDropAutoDisableMinutes > 1440 {
            logger.warn("PerUser.AirDropAutoDisableMinutes above 24 hours (\(cfg.perUser.airDropAutoDisableMinutes)) – clamped to 1440")
            cfg.perUser.airDropAutoDisableMinutes = 1440
        }

        // Required (soft) markers
        if rawOrgName?.trimmedEmptyToNil == nil { logger.warn("Org.OrgName missing (using default AnyOrg)") }
        if rawOrgContact?.trimmedEmptyToNil == nil { logger.warn("Org.OrgContact missing (using default itsupport@any.org)") }

        return cfg
    }
}

private extension String {
    var trimmedEmptyToNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private func parseDelimitedList(_ raw: String?) -> [String] {
    guard let raw = raw?.trimmedEmptyToNil else { return [] }
    return raw
        .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

package extension ManagedConfig {
    var resolvedSecurityBannerText: String {
        if let securityBannerText, !securityBannerText.isEmpty {
            return securityBannerText
        }
        return """
        Authorized use only.
        Managed by \(orgName)
        Contact: \(orgContact)
        """
    }
}

// MARK: perUserConfig

package struct ManagedPerUserConfig {
    package var disableBluetoothSharing: PentaMode
    package var disableMediaSharing: PentaMode
    package var disableAirDrop: PentaMode
    package var airDropAutoDisableMinutes: Int
    package var disableAdTracking: PentaMode
    package var enableTerminalSecureKeyboard: PentaMode
    package var disableSiri: PentaMode
    package var forceShowWifiStatus: PentaMode
    package var secureHomeFolders: PentaMode
    package var lockLoginKeychain: PentaMode
    package var removeUserPasswordHints: PentaMode
    package var forceShowFileNameExtensions: PentaMode
    package var disableSafariDownloadAutoRun: PentaMode

    package var lockKeychainInactivity: Int
}
