import Foundation

func noLog(_ fn: @escaping () -> CheckResult) -> (HardenLogger, ManagedConfig) -> CheckResult {
    { _, _ in fn() }
}

enum CheckRegistry {

    static func all() -> [CheckSpec] {
        [

            // MARK: CoreSecurity
            CheckSpec(
                name: "FileVault",
                section: "CoreSecurity",
                key: "CheckFileVaultStatus",
                benchmarkID: "2.5.1.1",
                timeoutSeconds: 15, // FileVault via shell/system calls → lieber etwas Luft
                check: { logger, _ in checkFileVault(logger: logger) },
                enforce: nil
            ),

            CheckSpec(
                name: "Gatekeeper",
                section: "CoreSecurity",
                key: "CheckGateKeeperStatus",
                benchmarkID: "2.5.2.1",
                timeoutSeconds: 10,
                check: noLog { checkGatekeeper() },
                enforce: nil
            ),

            CheckSpec(
                name: "SIP",
                section: "CoreSecurity",
                key: "CheckSIPStatus",
                benchmarkID: "5.18",
                timeoutSeconds: 10,
                check: noLog { checkSIP() },
                enforce: nil
            ),

            CheckSpec(
                name: "SSV/Authenticated Root",
                section: "CoreSecurity",
                key: "CheckARStatus",
                benchmarkID: "5.19",
                timeoutSeconds: 10,
                check: noLog { checkSSV() },
                enforce: nil
            ),

            CheckSpec(
                name: "XProtect",
                section: "CoreSecurity",
                key: "UpdateXProtect",
                benchmarkID: "XPR-1",
                timeoutSeconds: 20,
                check: noLog { checkXProtectCLI() },
                enforce: { logger, _ in enforceXProtectCLI(logger: logger) }
            ),

            // Regular Benchmarks

            // MARK: Security
            CheckSpec(
                name: "Force Hibernate on Sleep",
                section: "PowerManagement",
                key: "ForceHibernateOnSleep",
                benchmarkID: "5.10",
                timeoutSeconds: 10,
                check: { _, _ in checkHibernateMode() },
                enforce: { logger, _ in enforceHibernateMode(logger: logger) }
            ),

            CheckSpec(
                name: "Destroy FileVault Key on Standby",
                section: "PowerManagement",
                key: "DestroyFileVaultKeyOnStandby",
                benchmarkID: "5.10.1",
                timeoutSeconds: 10,
                check: { _, _ in checkDestroyFVKeyOnStandby() },
                enforce: { logger, _ in enforceDestroyFVKeyOnStandby(logger: logger) }
            ),
            CheckSpec(
                name: "Admin Password for Preferences",
                section: "LoginWindow",
                key: "ForceAdminPWForPreferences",
                benchmarkID: "5.11",
                timeoutSeconds: 20,
                check: { _, _ in checkAdminPasswordForPreferencesRequired() },
                enforce: { logger, _ in enforceAdminPasswordForPreferencesRequired(logger: logger) }
            ),

            // MARK: Location
            CheckSpec(
                name: "Ortungsdienste aktivieren",
                section: "Location",
                key: "EnableLocationServices",
                benchmarkID: "2.5.3",
                timeoutSeconds: 10,
                check: noLog { checkLocationServicesEnabled() },
                enforce: { logger, _ in enforceLocationServicesEnabled(logger: logger) }
            ),

            // MARK: Screensaver
            CheckSpec(
                name: "Screensaver inactivity timeout",
                section: "ScreenSaver",
                key: "ScreenSaverDelay",
                benchmarkID: "2.3.1",
                modeOverride: { raw, _ in modeFor(raw, section: "ScreenSaver", key: "SetScreenSaverDelay") },
                timeoutSeconds: 10,
                check: { _, cfg in checkScreensaverIdle(saverDelay: cfg.screenSaverDelay) },
                enforce: { logger, cfg in enforceScreensaverIdle(logger: logger, saverDelay: cfg.screenSaverDelay) }
            ),
            CheckSpec(
                name: "Screensaver password required",
                section: "ScreenSaver",
                key: "RequirePasswordOnWake",
                benchmarkID: "5.9",
                modeOverride: { raw, _ in modeFor(raw, section: "ScreenSaver", key: "RequirePasswordOnWake") },
                timeoutSeconds: 10,
                check: { _, _ in checkScreensaverRequirePassword() },
                enforce: nil
            ),
            CheckSpec(
                name: "Screensaver password delay",
                section: "ScreenSaver",
                key: "ScreenSaverPasswordDelay",
                benchmarkID: "5.9.1",
                modeOverride: { raw, _ in modeFor(raw, section: "ScreenSaver", key: "RequirePasswordOnWake") },
                timeoutSeconds: 10,
                check: { _, cfg in checkScreensaverPasswordDelay(passwordDelay: cfg.screenSaverPasswordDelay) },
                enforce: nil
            ),

            // MARK: Firewall
            CheckSpec(
                name: "Firewall",
                section: "Firewall",
                key: "EnableFirewall",
                benchmarkID: "2.5.2.1",
                timeoutSeconds: 10,
                check: noLog { checkFirewall() },
                enforce: { logger, _ in enforceFirewallOn(logger: logger) }
            ),
            CheckSpec(
                name: "Firewall (Stealth Mode)",
                section: "Firewall",
                key: "EnableFirewallStealthMode",
                benchmarkID: "2.5.2.3",
                timeoutSeconds: 10,
                check: noLog { checkFirewallStealthMode() },
                enforce: { logger, _ in enforceFirewallStealthModeOn(logger: logger) }
            ),
            CheckSpec(
                name: "Firewall (Block All Incoming)",
                section: "Firewall",
                key: "EnableFirewallBlockAllIncoming",
                benchmarkID: "2.5.2.X",
                timeoutSeconds: 10,
                check: noLog { checkFirewallBlockAllIncoming() },
                enforce: { logger, _ in enforceFirewallBlockAllIncomingOn(logger: logger) }
            ),
            CheckSpec(
                name: "Firewall (Allow Signed Downloads)",
                section: "Firewall",
                key: "EnableFirewallAllowSigned",
                benchmarkID: "2.5.2.X",
                timeoutSeconds: 10,
                check: noLog { checkFirewallAllowSigned() },
                enforce: { logger, _ in enforceFirewallAllowSignedOn(logger: logger) }
            ),

            // MARK: Timeserver and Timezone
            CheckSpec(
                name: "Time/NTP",
                section: "TimeNTP",
                key: "ForceTimeServer",
                benchmarkID: "2.2.1",
                modeOverride: { _, cfg in cfg.forceTimeServer ? .enforce : .ignore },
                timeoutSeconds: 10,
                check: { _, cfg in
                    checkNetworkTime(usingNTPShouldBeOn: true,
                                     expectedServer: cfg.timeServer,
                                     expectedTimeZone: cfg.defaultTimeZone)
                },
                enforce: { logger, cfg in
                    enforceTimeSettings(expectedServer: cfg.timeServer,
                                        expectedTimeZone: cfg.defaultTimeZone,
                                        logger: logger)
                }
            ),

            // MARK: System
            CheckSpec(
                name: "System Uptime",
                section: "System",
                key: "CheckSystemUptime",
                benchmarkID: "UPT-1",
                timeoutSeconds: 3,
                check: { _, cfg in
                    checkSystemUptime(
                        warnDays: cfg.systemUptimeWarnDays,
                        maxDays: cfg.systemUptimeMaxDays
                    )
                },
                enforce: nil
            ),
            CheckSpec(
                name: "SSH Password Authentication",
                section: "SSH",
                key: "DisableSSHPasswordAuthentication",
                benchmarkID: "SSH-PA",
                timeoutSeconds: 12,
                check: { logger, _ in checkSSHPasswordAuthenticationDisabled(logger: logger) },
                enforce: { logger, _ in enforceSSHPasswordAuthenticationDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "SSH Client Alive Interval",
                section: "SSH",
                key: "ConfigureSSHClientAliveInterval",
                benchmarkID: "SSH-CAI",
                timeoutSeconds: 12,
                check: { logger, cfg in
                    checkSSHClientAliveInterval(
                        expectedSeconds: cfg.sshClientAliveInterval,
                        logger: logger
                    )
                },
                enforce: { logger, cfg in
                    enforceSSHClientAliveInterval(
                        expectedSeconds: cfg.sshClientAliveInterval,
                        logger: logger
                    )
                }
            ),
            CheckSpec(
                name: "SSH Client Alive Count Max",
                section: "SSH",
                key: "ConfigureSSHClientAliveCountMax",
                benchmarkID: "SSH-CAM",
                timeoutSeconds: 12,
                check: { logger, cfg in
                    checkSSHClientAliveCountMax(
                        expectedCount: cfg.sshClientAliveCountMax,
                        logger: logger
                    )
                },
                enforce: { logger, cfg in
                    enforceSSHClientAliveCountMax(
                        expectedCount: cfg.sshClientAliveCountMax,
                        logger: logger
                    )
                }
            ),

            // MARK: Diagnostics and Audit
            CheckSpec(
                name: "Diagnostic and usage reporting",
                section: "DiagnosticsAudit",
                key: "DisableDiagnosticData",
                benchmarkID: "2.5.5",
                modeOverride: { raw, _ in
                    modeForAny(raw, section: "DiagnosticsAudit", keys: ["DisableDiagnosticData", "DisableDiagnostics"])
                },
                timeoutSeconds: 10,
                check: { _, _ in checkDiagnosticsReportingDisabled() },
                enforce: { logger, _ in enforceDiagnosticsReportingDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Audit Failure Halt",
                section: "DiagnosticsAudit",
                key: "EnableAuditFailureHalt",
                benchmarkID: "AUD-1",
                timeoutSeconds: 10,
                check: { _, _ in checkAuditFailureHaltEnabled() },
                enforce: { logger, _ in enforceAuditFailureHaltEnabled(logger: logger) }
            ),
            CheckSpec(
                name: "Audit Core Flags",
                section: "DiagnosticsAudit",
                key: "ConfigureAuditFlagsCore",
                benchmarkID: "AUD-2",
                timeoutSeconds: 10,
                check: { _, _ in checkAuditFlagsCoreConfigured() },
                enforce: { logger, _ in enforceAuditFlagsCoreConfigured(logger: logger) }
            ),
            CheckSpec(
                name: "Security Auditing",
                section: "DiagnosticsAudit",
                key: "EnableSecurityAuditing",
                benchmarkID: "3.1",
                timeoutSeconds: 15,
                check: { _, _ in checkSecurityAuditingEnabled() },
                enforce: { logger, _ in enforceSecurityAuditingEnabled(logger: logger) }
            ),
            CheckSpec(
                name: "Install Log Retention",
                section: "DiagnosticsAudit",
                key: "RetainInstallLog",
                benchmarkID: "3.3",
                timeoutSeconds: 10,
                check: { _, _ in checkInstallLogRetentionConfigured() },
                enforce: { logger, _ in enforceInstallLogRetentionConfigured(logger: logger) }
            ),

            CheckSpec(
                name: "Audit Log Permissions",
                section: "DiagnosticsAudit",
                key: "LimitAuditRecordsAccess",
                benchmarkID: "3.5",
                modeOverride: { raw, _ in
                    modeForAny(raw, section: "DiagnosticsAudit", keys: ["LimitAuditRecordsAccess", "SecureAuditLogPermissions"])
                },
                timeoutSeconds: 10,
                check: { _, _ in checkAuditLogPermissions() },
                enforce: { logger, _ in enforceAuditLogPermissions(logger: logger) }
            ),

            // MARK: Sharing
            CheckSpec(
                name: "Remote Apple Events",
                section: "Sharing",
                key: "DisableRemoteAppleEvents",
                benchmarkID: "2.4.1",
                timeoutSeconds: 15,
                check: { _, _ in checkRemoteAppleEventsOff() },
                enforce: { logger, _ in enforceRemoteAppleEventsOff(logger: logger) }
            ),
            CheckSpec(
                name: "Internet Sharing",
                section: "Sharing",
                key: "DisableInternetSharing",
                benchmarkID: "2.4.2",
                timeoutSeconds: 15,
                check: { _, _ in checkInternetSharingOff() },
                enforce: { logger, _ in enforceInternetSharingOff(logger: logger) }
            ),
            CheckSpec(
                name: "Screen Sharing",
                section: "Sharing",
                key: "DisableScreenSharing",
                benchmarkID: "2.4.3",
                timeoutSeconds: 15,
                check: { _, _ in checkScreenSharingOff() },
                enforce: { logger, _ in enforceScreenSharingOff(logger: logger) }
            ),
            CheckSpec(
                name: "Printer Sharing",
                section: "Sharing",
                key: "DisablePrinterSharing",
                benchmarkID: "2.4.4",
                timeoutSeconds: 15,
                check: { _, _ in checkPrinterSharingOff() },
                enforce: { logger, _ in enforcePrinterSharingOff(logger: logger) }
            ),
            CheckSpec(
                name: "Remote Login (SSH)",
                section: "Sharing",
                key: "DisableRemoteLogin",
                benchmarkID: "2.4.5",
                timeoutSeconds: 10,
                check: { logger, _ in checkRemoteLoginBestEffort(logger: logger) },
                enforce: { logger, _ in enforceRemoteLoginOff(logger: logger) }
            ),
            CheckSpec(
                name: "CD/DVD Sharing",
                section: "Sharing",
                key: "DisableDVDSharing",
                benchmarkID: "2.4.6",
                timeoutSeconds: 15,
                check: { _, _ in checkDVDSharingOff() },
                enforce: { logger, _ in enforceDVDSharingOff(logger: logger) }
            ),
            CheckSpec(
                name: "File Sharing",
                section: "Sharing",
                key: "DisableFileSharing",
                benchmarkID: "2.4.8",
                timeoutSeconds: 15,
                check: { _, _ in checkFileSharingOff() },
                enforce: { logger, _ in enforceFileSharingOff(logger: logger) }
            ),
            CheckSpec(
                name: "Remote Management",
                section: "Sharing",
                key: "DisableRemoteManagement",
                benchmarkID: "2.4.9",
                timeoutSeconds: 20,
                check: { _, _ in checkRemoteManagementOff() },
                enforce: { logger, _ in enforceRemoteManagementOff(logger: logger) }
            ),
            CheckSpec(
                name: "Content Caching",
                section: "Sharing",
                key: "DisableContentCaching",
                benchmarkID: "2.4.10",
                timeoutSeconds: 20,
                check: { _, _ in checkContentCachingOff() },
                enforce: { logger, _ in enforceContentCachingOff(logger: logger) }
            ),

            // MARK: Power Management
            CheckSpec(
                name: "Wake for Network Access",
                section: "PowerManagement",
                key: "DisableWOMP",
                benchmarkID: "2.8",
                timeoutSeconds: 15,
                check: { _, _ in checkWakeForNetworkAccessOff() },
                enforce: { logger, _ in enforceWakeForNetworkAccessOff(logger: logger) }
            ),

            CheckSpec(
                name: "Power Nap",
                section: "PowerManagement",
                key: "DisablePowerNap",
                benchmarkID: "2.9",
                timeoutSeconds: 15,
                check: { _, _ in checkPowerNapOff() },
                enforce: { logger, _ in enforcePowerNapOff(logger: logger) }
            ),

            // MARK: Login Window
            CheckSpec(
                name: "Sudo Timeout",
                section: "LoginWindow",
                key: "SetSudoTimeout",
                benchmarkID: "5.3",
                timeoutSeconds: 10,
                check: { _, cfg in checkSudoTimeout(expectedMinutes: cfg.sudoTimeout) },
                enforce: { logger, cfg in enforceSudoTimeout(expectedMinutes: cfg.sudoTimeout, logger: logger) }
            ),
            CheckSpec(
                name: "Sudo Command Logging",
                section: "LoginWindow",
                key: "EnableSudoCommandLogging",
                benchmarkID: "SUDO-LOG",
                timeoutSeconds: 10,
                check: { logger, _ in checkSudoCommandLoggingEnabled(logger: logger) },
                enforce: { logger, _ in enforceSudoCommandLoggingEnabled(logger: logger) }
            ),
            CheckSpec(
                name: "Sudo Timestamp Type",
                section: "LoginWindow",
                key: "EnforceSudoTimestampTypeTTY",
                benchmarkID: "SUDO-TTY",
                timeoutSeconds: 10,
                check: { logger, _ in checkSudoTimestampTypeTTY(logger: logger) },
                enforce: { logger, _ in enforceSudoTimestampTypeTTY(logger: logger) }
            ),
            CheckSpec(
                name: "Automatic Login",
                section: "LoginWindow",
                key: "DisableAutomaticLogin",
                benchmarkID: "5.8",
                timeoutSeconds: 10,
                check: { _, _ in checkAutoLoginDisabled() },
                enforce: { logger, _ in enforceAutoLoginDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Fast User Switching",
                section: "LoginWindow",
                key: "DisableFastUserSwitching",
                benchmarkID: "5.16",
                timeoutSeconds: 10,
                check: { _, _ in checkFastUserSwitchingDisabled() },
                enforce: { logger, _ in enforceFastUserSwitchingDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Login Window Full Name",
                section: "LoginWindow",
                key: "ForceLoginWindowFullName",
                benchmarkID: "6.1.1",
                timeoutSeconds: 10,
                check: { _, _ in checkLoginWindowFullNameEnabled() },
                enforce: { logger, _ in enforceLoginWindowFullNameEnabled(logger: logger) }
            ),
            CheckSpec(
                name: "Login Window Security Banner",
                section: "LoginWindow",
                key: "EnableLoginWindowSecurityBanner",
                benchmarkID: "BANNER-LW",
                timeoutSeconds: 10,
                check: { _, cfg in checkLoginWindowSecurityBanner(expectedText: cfg.resolvedSecurityBannerText) },
                enforce: { logger, cfg in
                    enforceLoginWindowSecurityBanner(
                        expectedText: cfg.resolvedSecurityBannerText,
                        logger: logger
                    )
                }
            ),
            CheckSpec(
                name: "SSH Login Banner",
                section: "LoginWindow",
                key: "EnableSSHLoginBanner",
                benchmarkID: "BANNER-SSH",
                timeoutSeconds: 12,
                check: { logger, cfg in checkSSHLoginBanner(expectedText: cfg.resolvedSecurityBannerText, logger: logger) },
                enforce: { logger, cfg in
                    enforceSSHLoginBanner(
                        expectedText: cfg.resolvedSecurityBannerText,
                        logger: logger
                    )
                }
            ),
            CheckSpec(
                name: "Password Hints",
                section: "LoginWindow",
                key: "DisablePasswordHints",
                benchmarkID: "6.1.2",
                timeoutSeconds: 10,
                check: { _, _ in checkPasswordHintsDisabled() },
                enforce: { logger, _ in enforcePasswordHintsDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Guest User",
                section: "LoginWindow",
                key: "DisableGuestUser",
                benchmarkID: "6.1.3",
                timeoutSeconds: 10,
                check: { _, _ in checkGuestUserDisabled() },
                enforce: { logger, _ in enforceGuestUserDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Guest Access to Shares",
                section: "LoginWindow",
                key: "DisableGuestAccessToShares",
                benchmarkID: "6.1.4",
                timeoutSeconds: 10,
                check: { _, _ in checkGuestAccessToSharesDisabled() },
                enforce: { logger, _ in enforceGuestAccessToSharesDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Guest Home Folder",
                section: "LoginWindow",
                key: "RemoveGuestHomeFolder",
                benchmarkID: "6.1.5",
                timeoutSeconds: 15,
                check: { _, _ in checkGuestHomeRemoved() },
                enforce: { logger, _ in enforceGuestHomeRemoved(logger: logger) }
            ),
            CheckSpec(
                name: "Library Validation",
                section: "LoginWindow",
                key: "EnableLibraryValidation",
                benchmarkID: "5.20",
                timeoutSeconds: 10,
                check: { _, _ in checkLibraryValidationEnabled() },
                enforce: { logger, _ in enforceLibraryValidationEnabled(logger: logger) }
            ),

            // MARK: Environment
            CheckSpec(
                name: "MDM Enrollment",
                section: "Environment",
                key: "RequireMDMEnrollment",
                benchmarkID: "ENV-MDM",
                timeoutSeconds: 10,
                check: { logger, _ in checkMDMEnrollment(logger: logger) },
                enforce: nil
            ),
            CheckSpec(
                name: "Directory Service",
                section: "Environment",
                key: "RequireDirectoryService",
                benchmarkID: "ENV-DIR",
                timeoutSeconds: 10,
                check: { logger, _ in checkDirectoryServiceConfigured(logger: logger) },
                enforce: nil
            ),
            CheckSpec(
                name: "Security Agent",
                section: "Environment",
                key: "RequireSecurityAgent",
                benchmarkID: "ENV-AV",
                timeoutSeconds: 12,
                check: { logger, cfg in checkSecurityAgentInstalled(expectedProducts: cfg.expectedSecurityProducts, logger: logger) },
                enforce: nil
            ),

            // MARK: Network Services
            CheckSpec(
                name: "Bonjour Advertising",
                section: "Sharing",
                key: "DisableBonjourAdvertising",
                benchmarkID: "4.1",
                timeoutSeconds: 10,
                check: { _, _ in checkBonjourAdvertisingDisabled() },
                enforce: { logger, _ in enforceBonjourAdvertisingDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "Apache HTTP Server",
                section: "Sharing",
                key: "DisableHTTPServer",
                benchmarkID: "4.4",
                timeoutSeconds: 10,
                check: { _, _ in checkApacheDisabled() },
                enforce: { logger, _ in enforceApacheDisabled(logger: logger) }
            ),
            CheckSpec(
                name: "NFS Server",
                section: "Sharing",
                key: "DisableNFSServer",
                benchmarkID: "4.5",
                timeoutSeconds: 10,
                check: { _, _ in checkNFSServerDisabled() },
                enforce: { logger, _ in enforceNFSServerDisabled(logger: logger) }
            ),

            // MARK: perUser

            CheckSpec(
                name: "Bluetooth Sharing",
                section: "PerUser",
                key: "DisableBluetoothSharing",
                benchmarkID: "2.4.7",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableBluetoothSharing

                    return runPerUserWithPolicy(
                        name: "Bluetooth Sharing",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkBluetoothSharingDisabled(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforceBluetoothSharingDisabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Media Sharing",
                section: "PerUser",
                key: "DisableMediaSharing",
                benchmarkID: "2.4.11",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableMediaSharing

                    return runPerUserWithPolicy(
                        name: "Media Sharing",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkMediaSharingDisabled(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforceMediaSharingDisabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "AirDrop",
                section: "PerUser",
                key: "DisableAirDrop",
                benchmarkID: "2.4.12",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableAirDrop

                    return runPerUserWithPolicy(
                        name: "AirDrop",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkAirDropDisabled(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforceAirDropDisabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Personalized Advertising",
                section: "PerUser",
                key: "DisableAdTracking",
                benchmarkID: "2.5.6",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableAdTracking

                    return runPerUserWithPolicy(
                        name: "Personalized Advertising",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkPersonalizedAdvertisingDisabled(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforcePersonalizedAdvertisingDisabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Siri",
                section: "PerUser",
                key: "DisableSiri",
                benchmarkID: "2.13",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableSiri

                    return runPerUserWithPolicy(
                        name: "Siri",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkSiriDisabled(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforceSiriDisabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Wi-Fi Status in Menu Bar",
                section: "PerUser",
                key: "ForceShowWifiStatus",
                benchmarkID: "4.2",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.forceShowWifiStatus

                    return runPerUserWithPolicy(
                        name: "Wi-Fi Status in Menu Bar",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkWifiStatusVisible(user: user, logger: logger)
                        },
                        enforce: { user in
                            enforceWifiStatusVisible(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Secure Home Folders",
                section: "PerUser",
                key: "SecureHomeFolders",
                benchmarkID: "5.1.1",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.secureHomeFolders

                    return runPerUserWithPolicy(
                        name: "Secure Home Folders",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkHomeFolderSecure(user: user)
                        },
                        enforce: { user in
                            enforceHomeFolderSecure(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Login Keychain Lock on Inactivity",
                section: "PerUser",
                key: "LockLoginKeychain",
                benchmarkID: "5.4",
                timeoutSeconds: 30,
                check: { logger, cfg in
                    let mode = cfg.perUser.lockLoginKeychain

                    return runPerUserWithPolicy(
                        name: "Login Keychain Lock on Inactivity",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkLoginKeychainLockInactivity(
                                user: user,
                                expectedTimeout: cfg.perUser.lockKeychainInactivity
                            )
                        },
                        enforce: { user in
                            enforceLoginKeychainLockInactivity(
                                user: user,
                                timeout: cfg.perUser.lockKeychainInactivity,
                                logger: logger
                            )
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Remove User Password Hints",
                section: "PerUser",
                key: "RemoveUserPasswordHints",
                benchmarkID: "5.15",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.removeUserPasswordHints

                    return runPerUserEnforceOnly(
                        name: "Remove User Password Hints",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        enforce: { user in
                            enforceUserPasswordHintRemoved(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Show File Name Extensions",
                section: "PerUser",
                key: "ForceShowFileNameExtensions",
                benchmarkID: "6.2",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.forceShowFileNameExtensions

                    return runPerUserWithPolicy(
                        name: "Show File Name Extensions",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkShowFileNameExtensionsEnabled(user: user)
                        },
                        enforce: { user in
                            enforceShowFileNameExtensionsEnabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Enable Secure Keyboard Entry in terminal.app",
                section: "PerUser",
                key: "EnableTerminalSecureKeyboard",
                benchmarkID: "6.3",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.enableTerminalSecureKeyboard

                    return runPerUserWithPolicy(
                        name: "Terminal Secure Keyboard Entry",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkTerminalSecureKeyboardEnabled(user: user)
                        },
                        enforce: { user in
                            enforceTerminalSecureKeyboardEnabled(user: user, logger: logger)
                        }
                    )
                }
            ),
            CheckSpec(
                name: "Safari Safe Downloads",
                section: "PerUser",
                key: "DisableSafariDownloadAutoRun",
                benchmarkID: "6.3",
                timeoutSeconds: 20,
                check: { logger, cfg in
                    let mode = cfg.perUser.disableSafariDownloadAutoRun

                    return runPerUserWithPolicy(
                        name: "Safari Safe Downloads",
                        mode: mode,
                        logger: logger,
                        users: PerUserPreferences.localUsers(),
                        check: { user in
                            checkSafariDownloadAutoRunDisabled(user: user)
                        },
                        enforce: { user in
                            enforceSafariDownloadAutoRunDisabled(user: user, logger: logger)
                        }
                    )
                }
            )
        ]
    }
}
