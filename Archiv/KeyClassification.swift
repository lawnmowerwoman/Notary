let modeKeys: Set<String> = [
  // PerUser modes (enforce/off)
  "PerUser.DisableBluetoothSharing",
  "PerUser.DisableMediaSharing",
  "PerUser.DisableAirDrop",
  "PerUser.DisableAdTracking",
  "PerUser.EnableTerminalSecureKeyboard",
  "PerUser.DisableSiri",
  "PerUser.ForceShowWifiStatus",
  "PerUser.SecureHomeFolders",
  "PerUser.LockLoginKeychain",
  "PerUser.RequirePasswordOnWake",
  "PerUser.RemoveUserPasswordHints",
  "PerUser.ForceShowFileNameExtensions",
  "PerUser.DisableSafariDownloadAutoRun",

  // Beispiele aus deinem aktuellen Dump (Pentabool Strings)
  "CoreSecurity.CheckARStatus",
  "CoreSecurity.CheckFileVaultStatus",
  "CoreSecurity.CheckGateKeeperStatus",
  "CoreSecurity.CheckSIPStatus",
  "CoreSecurity.UpdateXProtect",

  "Firewall.EnableFirewall",
  "Firewall.EnableFirewallLogging",
  "Firewall.EnableFirewallStealthMode",

  "PowerManagement.DisablePowerNap",
  "PowerManagement.DestroyFileVaultKeyOnStandby",
  "PowerManagement.ForceHibernateOnSleep",
  "PowerManagement.DisableWOMP",

  "Sharing.DisablePrinterSharing",
  "Sharing.DisableRemoteManagement",
  "Sharing.DisableDVDSharing",
  "Sharing.DisableInternetSharing",
  "Sharing.DisableFileSharing",
  "Sharing.DisableRemoteLogin",
  "Sharing.DisableContentCaching",
  "Sharing.DisableBonjourAdvertising",
  "Sharing.DisableScreenSharing",
  "Sharing.DisableRemoteAppleEvents",
  "Sharing.DisableNFSServer",
  "Sharing.DisableHTTPServer",

  "DiagnosticsAudit.RetainInstallLog",
  "DiagnosticsAudit.EnableSecurityAuditing",
  "DiagnosticsAudit.DisableDiagnosticData",
  "DiagnosticsAudit.LimitAuditRecordsAccess",

  "Location.EnableLocationServices",

  "LoginWindow.DisableGuestUser",
  "LoginWindow.DisableAutomaticLogin",
  "LoginWindow.ForceLoginWindowFullName",
  "LoginWindow.ForceAdminPWForPreferences",
  "LoginWindow.DisableFastUserSwitching",
  "LoginWindow.EnableLibraryValidation",
  "LoginWindow.DisablePasswordHints",
  "LoginWindow.DisableGuestAccessToShares",
  "LoginWindow.RemoveGuestHomeFolder",
  "LoginWindow.SetSudoTimeout"
]

let parameterKeys: Set<String> = [
  // PerUser parameters
  "PerUser.LockKeychainInactivity",

  // LoginWindow parameters
  "LoginWindow.SudoTimeout",

  // TimeNTP parameters
  "TimeNTP.ForceTimeServer",
  "TimeNTP.TimeServer",
  "TimeNTP.DefaultTimeZone",

  // Org parameters
  "Org.OrgName",
  "Org.OrgContact",

  // Misc parameters (depending on semantics; keep as bool for now)
  "Misc.DestroyKeyOnMajorIssue"
]
