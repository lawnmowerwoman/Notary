# Benchmark-Matrix

Diese Matrix bündelt den aktuellen Stand zwischen:

- `Config-Schema-1.2.json` als vorgesehene Konfigurations- und Benchmark-Oberfläche
- dem aktuellen Notary-Code unter `Sources/NotaryRunner`
- den Jamf-/mSCP-Referenzskripten aus `/Users/steffi/Coding/CIS/Archive.zip`

Ziel ist eine belastbare Arbeitsgrundlage für `#5 Further CIS benchmarks`.

## Quellen

- Schema:
  `Config-Schema-1.2.json`
- Notary-Implementierung:
  `Sources/NotaryRunner/CheckRegistry.swift` plus zugehörige `Check_*.swift`
- Jamf-/mSCP-Referenz:
  `compliance_benchmark_68e7fccbd6498d6f5068366d_tahoe.sh.txt`
  `compliance_benchmark_69007c78a3b34492c4460dc3_tahoe.sh.txt`
- Jamf NIST 800-171 Referenz:
  `compliance_benchmark_69f21c8498ef566f5d7de6ea_tahoe.sh.txt`
- Jamf CIS v8 Referenz:
  `compliance_benchmark_69f21d2998ef566f5d7de6ff_tahoe.sh.txt`

Hinweis:
Die Datei `Config-Schema-1.2.json` trägt intern bereits den Titel `Konfiguration 1.3`. Das ist aktuell nur ein Benennungs-Mismatch, aber kein inhaltlicher Blocker.

## Snapshot

- `82` Schema-Keys insgesamt
- `15` davon sind reine Hilfs-/Parameterfelder
- `67` davon sind eigentliche Action-/Benchmark-Einträge
- `67` Action-/Benchmark-Einträge sind aktuell direkt im `CheckRegistry` vertreten
- `0` Einträge sind funktional nur teilweise vorhanden oder derzeit falsch verdrahtet
- `0` Einträge sind im Schema vorgesehen, aber im Notary-Code noch nicht umgesetzt

## Status-Legende

- `Wired`
  Im Schema vorgesehen und im aktuellen Notary-Code direkt verdrahtet.
- `Missing`
  Im Schema vorhanden, aber aktuell nicht im Notary-Code umgesetzt.
- `Helper`
  Parameter-/Begleitfeld, kein eigener Benchmark.

## Matrix nach Sektion

| Sektion | Schema-Action-Keys | Wired | Partial | Missing | Hinweise |
| --- | ---: | ---: | ---: | ---: | --- |
| `CoreSecurity` | 5 | 5 | 0 | 0 | Solide Basis vorhanden |
| `Firewall` | 4 | 4 | 0 | 0 | Gute Abdeckung, nur Benchmark-ID `2.5.2.X` später präzisieren |
| `DiagnosticsAudit` | 6 | 6 | 0 | 0 | Audit-Failure und Audit-Core-Flags jetzt als erste NIST/CIS-Welle enthalten |
| `Location` | 1 | 1 | 0 | 0 | Abgedeckt |
| `ScreenSaver` | 2 | 2 | 0 | 0 | Zwei Action-Keys plus Parameterfelder |
| `TimeNTP` | 1 | 1 | 0 | 0 | `ForceTimeServer` ist Action-Key; Server/Zeitzone sind Helper |
| `System` | 1 | 1 | 0 | 0 | Uptime-Check plus Warn-/Max-Parameter vorhanden |
| `SSH` | 3 | 3 | 0 | 0 | Passwortauthentifizierung und ClientAlive-Werte als erste SSH-Welle umgesetzt |
| `Sharing` | 12 | 12 | 0 | 0 | Sehr guter Stand |
| `PowerManagement` | 4 | 4 | 0 | 0 | Gute Basis |
| `LoginWindow` | 14 | 14 | 0 | 0 | Sudo-Detailhärtung und lokale/SSH-Banner jetzt enthalten |
| `Environment` | 3 | 3 | 0 | 0 | MDM, Directory und AV/EDR als produktabhängige Umfeldchecks umgesetzt |
| `PerUser` | 12 | 12 | 0 | 0 | Vollständig im aktuellen Schema-Scope |

## Priorität A: Verdrahtungslücken geschlossen

Diese Punkte sind jetzt bereinigt und stehen damit nicht mehr als Blocker vor der nächsten Benchmark-Welle.

| Schema-Key | Sektion | Neuer Stand | Notiz |
| --- | --- | --- | --- |
| `DisableDiagnosticData` | `DiagnosticsAudit` | `Wired` | Registry folgt jetzt dem Schema-Key und bleibt per Fallback kompatibel zu `DisableDiagnostics`. |
| `LimitAuditRecordsAccess` | `DiagnosticsAudit` | `Wired` | Registry folgt jetzt dem Schema-Key und bleibt per Fallback kompatibel zu `SecureAuditLogPermissions`. |
| `SetSudoTimeout` | `LoginWindow` | `Wired` | Der Check ist jetzt registriert und validiert den konfigurierten Minutenwert statt nur die Existenz einer Policy. |

## Priorität B: Aktueller Schema-Scope vollständig

Das aktuelle `Config-Schema-1.2.json` ist jetzt vollständig im Notary-Code verdrahtet. Die nächste Benchmark-Welle kann sich damit vollständig auf neue archive-only Themen oder fachliche Nachschärfung bereits vorhandener Checks konzentrieren.

## Priorität C: Bereits implementiert, aber fachlich nachschärfen

Diese Punkte laufen zwar bereits, sollten aber später fachlich oder dokumentarisch präzisiert werden.

| Thema | Aktueller Stand | Notiz |
| --- | --- | --- |
| `Firewall BlockAll` | `Wired` | Nutzt aktuell `benchmarkID = 2.5.2.X`; die genaue CIS-Zuordnung sollte später konkretisiert werden. |
| `Firewall AllowSigned` | `Wired` | Ebenfalls mit Platzhalter-ID `2.5.2.X`. |
| `EnableTerminalSecureKeyboard` | `Wired` | Schema-Titel zeigt `2.10`, der Code meldet aktuell `benchmarkID = 6.3`; das ist eine sichtbare ID-Drift. |

## Jamf-/mSCP-Referenz: zusätzliche Kandidaten außerhalb des aktuellen Schemas

Das neuere Archivskript `69007c78..._tahoe.sh.txt` wirkt als die breitere Referenz und listet `169` Rules. Es enthält mehrere Kandidaten, die im aktuellen Notary-Schema noch nicht oder nicht vollständig sichtbar sind.

### Hohe Relevanz

| mSCP-Rule | Einschätzung |
| --- | --- |
| `audit_acls_*`, `audit_files_*`, `audit_folder_*` | Erweiterte Audit-/Dateiberechtigungsfamilie, sinnvoll als eigener Block nach den bestehenden Audit-Basics |
| `audit_retention_configure` | Gute Ergänzung zu `3.3` und `3.5` |
| `os_config_data_install_enforce` | Passt gut in den Sicherheits-/Update-Bereich |
| `os_mobile_file_integrity_enable` | Relevanter Plattform-Sicherheitscheck |
| `os_sudo_log_enforce` | Gute Ergänzung zum vorhandenen `Sudo Timeout` |
| `os_sudoers_timestamp_type_configure` | Gehört in denselben Themenblock wie `Sudo Timeout` |
| `system_settings_softwareupdate_current` | Hoher praktischer Nutzen, aber stärker versions- und netzwerkabhängig |

### Mittlere Relevanz

| mSCP-Rule | Einschätzung |
| --- | --- |
| `os_mail_summary_disable` | Interessant, aber eher UX-/Privacy-orientiert |
| `os_notes_transcription_disable` | Für aktuelle macOS-Versionen relevant, aber vermutlich eher Per-User/Privacy |
| `os_notes_transcription_summary_disable` | ähnlich gelagert |
| `os_on_device_dictation_enforce` | Gute spätere Ergänzung im Privacy-/AI-Bereich |
| `os_writing_tools_disable` | Für neuere macOS-Generationen relevant |
| `system_settings_hot_corners_secure` | Nützlich, aber nicht vor Kern-Sicherheitskontrollen |
| `system_settings_time_machine_encrypted_configure` | Inhaltlich spannend, braucht aber klare Produktentscheidung |
| `system_settings_time_machine_auto_backup_enable` | eher Organisationspolicy als klassischer CIS-Kern |

### Geringere oder gesondert zu behandelnde Relevanz

| mSCP-Rule | Einschätzung |
| --- | --- |
| `pwpolicy_*`-Familie | Hoher Policy-Wert, aber oft durch Plattform-/IdP-/MDM-Kontext beeinflusst; separat planen |
| `os_anti_virus_installed` | Eher produkt- und umgebungsabhängig als generischer Notary-Baseline-Check |
| `icloud_sync_disable` | Produktentscheidung nötig, nicht blind als Standardbenchmark übernehmen |
| `system_settings_external_intelligence_*` | fachlich interessant, aber klar versions- und organisationsspezifisch |

## Empfohlene Abarbeitung für `#5`

1. Als Nächstes die ersten archive-only Erweiterungen im nächsten Block angehen.
2. Archive-only Themen nach Blöcken schneiden, nicht einzeln:
   `Audit-Berechtigungen`, `Sudo/Privilege`, `Privacy/AI`, `Software Update`.

## Praktische Interpretation

Für die nächste Implementierungsphase heißt das:

- Wir müssen nicht blind nach neuen CIS-Punkten suchen.
- Das bestehende Schema ist vollständig umgesetzt und liefert jetzt eine stabile Basis für die nächste Beta-Aktualisierung.
- Die Jamf-/mSCP-Skripte dienen als Referenz für Detailverhalten, Shell-Kommandos und fehlende Themenfamilien.
- Die Verdrahtungslücken zwischen Konfiguration und Laufzeit sind geschlossen; der nächste Ausbau kann sich auf fehlende Checks statt auf Reparaturarbeit konzentrieren.

## NIST 800-171 Abgleich (Jamf-Stand vom 2026-04-29)

Das aktuelle Jamf-NIST-Skript `compliance_benchmark_69f21c8498ef566f5d7de6ea_tahoe.sh.txt` enthält:

- `195` Rule-Blöcke insgesamt
- `143` eindeutige Rules nach Deduplizierung

Wichtig:
Das Skript mischt einen breiten Privacy-/iCloud-/Apple-Intelligence-Scope mit klassischen Hardening- und Audit-Kontrollen. Es ist damit deutlich breiter als der heutige Notary-Schema-Scope.

### Bereits fachlich abgedeckt oder sehr nah abgedeckt

Diese Jamf-NIST-Rules entsprechen bereits vorhandenen Notary-Checks oder liegen sehr nahe an deren heutiger Wirkung:

| Jamf-NIST-Rule | Notary-Key / Check | Einordnung |
| --- | --- | --- |
| `system_settings_filevault_enforce` | `CoreSecurity.CheckFileVaultStatus` | Bereits abgedeckt |
| `os_gatekeeper_enable` | `CoreSecurity.CheckGateKeeperStatus` | Bereits abgedeckt |
| `system_settings_gatekeeper_identified_developers_allowed` | `CoreSecurity.CheckGateKeeperStatus` | Nahezu abgedeckt |
| `system_settings_gatekeeper_override_disallow` | `CoreSecurity.CheckGateKeeperStatus` | Nahezu abgedeckt |
| `os_sip_enable` | `CoreSecurity.CheckSIPStatus` | Bereits abgedeckt |
| `os_authenticated_root_enable` | `CoreSecurity.CheckARStatus` | Bereits abgedeckt |
| `system_settings_location_services_disable` | `Location.EnableLocationServices` | Gegenläufige Policy-Formulierung, aber gleicher Themenbereich |
| `system_settings_firewall_enable` | `Firewall.EnableFirewall` | Bereits abgedeckt |
| `system_settings_firewall_stealth_mode_enable` | `Firewall.EnableFirewallStealthMode` | Bereits abgedeckt |
| `system_settings_diagnostics_reports_disable` | `DiagnosticsAudit.DisableDiagnosticData` | Bereits abgedeckt |
| `audit_auditd_enabled` | `DiagnosticsAudit.EnableSecurityAuditing` | Bereits abgedeckt |
| `audit_retention_configure` | `DiagnosticsAudit.RetainInstallLog` | Nahe thematische Ergänzung zum bestehenden Log-Retention-Check |
| `audit_acls_*`, `audit_files_*`, `audit_folder_*`, `audit_folders_mode_configure` | `DiagnosticsAudit.LimitAuditRecordsAccess` | Teilweise abgedeckt, Jamf ist hier deutlich granularer |
| `os_time_server_enabled` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `system_settings_time_server_configure` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `system_settings_time_server_enforce` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `os_bonjour_disable` | `Sharing.DisableBonjourAdvertising` | Bereits abgedeckt |
| `system_settings_rae_disable` | `Sharing.DisableRemoteAppleEvents` | Bereits abgedeckt |
| `system_settings_internet_sharing_disable` | `Sharing.DisableInternetSharing` | Bereits abgedeckt |
| `system_settings_screen_sharing_disable` | `Sharing.DisableScreenSharing` | Bereits abgedeckt |
| `system_settings_ssh_disable` | `Sharing.DisableRemoteLogin` | Bereits abgedeckt |
| `auth_ssh_password_authentication_disable` | `SSH.DisableSSHPasswordAuthentication` | Jetzt direkt abgedeckt |
| `system_settings_smbd_disable` | `Sharing.DisableFileSharing` | Bereits abgedeckt |
| `os_httpd_disable` | `Sharing.DisableHTTPServer` | Bereits abgedeckt |
| `os_nfsd_disable` | `Sharing.DisableNFSServer` | Bereits abgedeckt |
| `system_settings_automatic_login_disable` | `LoginWindow.DisableAutomaticLogin` | Bereits abgedeckt |
| `system_settings_loginwindow_prompt_username_password_enforce` | `LoginWindow.ForceLoginWindowFullName` | Teilweise verwandt, aber nicht identisch |
| `os_loginwindow_adminhostinfo_disabled` | `LoginWindow.ForceLoginWindowFullName` | Nahezu abgedeckt |
| `system_settings_password_hints_disable` | `LoginWindow.DisablePasswordHints` | Bereits abgedeckt |
| `system_settings_guest_account_disable` | `LoginWindow.DisableGuestUser` | Bereits abgedeckt |
| `system_settings_guest_access_smb_disable` | `LoginWindow.DisableGuestAccessToShares` | Bereits abgedeckt |
| `system_settings_system_wide_preferences_configure` | `LoginWindow.ForceAdminPWForPreferences` | Bereits abgedeckt |
| `system_settings_token_removal_enforce` | `LoginWindow.EnableLibraryValidation` | Nahezu abgedeckt |
| `system_settings_bluetooth_sharing_disable` | `PerUser.DisableBluetoothSharing` | Bereits abgedeckt |
| `system_settings_media_sharing_disabled` | `PerUser.DisableMediaSharing` | Bereits abgedeckt |
| `os_airdrop_disable` | `PerUser.DisableAirDrop` | Bereits abgedeckt |
| `system_settings_personalized_advertising_disable` | `PerUser.DisableAdTracking` | Bereits abgedeckt |
| `system_settings_siri_disable` | `PerUser.DisableSiri` | Bereits abgedeckt |
| `os_siri_prompt_disable` | `PerUser.DisableSiri` | Nahezu abgedeckt |
| `os_home_folders_secure` | `PerUser.SecureHomeFolders` | Bereits abgedeckt |

### Neu für Notary-Schema oder klar unterrepräsentiert

Diese Bereiche sind im aktuellen Notary-Schema noch gar nicht oder nur sehr grob vertreten und wären gute Kandidaten für die nächste Ausbaustufe:

| Themenblock | Beispiel-Rules | Einschätzung |
| --- | --- | --- |
| Erweiterte Audit-Flags und Audit-Fehlerreaktionen | `audit_failure_halt`, `audit_flags_*`, `audit_settings_failure_notify` | Erste Welle umgesetzt über `EnableAuditFailureHalt` und `ConfigureAuditFlagsCore`; feinere `audit_flags_*`-Breite bleibt offen |
| SSH-/SSHD-Härtung | `os_ssh_fips_compliant`, `os_ssh_server_alive_*`, `os_sshd_*`, `auth_ssh_password_authentication_disable` | Erste Welle umgesetzt: Passwortauthentifizierung sowie `ClientAliveInterval` und `ClientAliveCountMax`; FIPS und weitere Detailhärtung bleiben offen |
| Policy Banner | `os_policy_banner_loginwindow_enforce`, `os_policy_banner_ssh_*` | Erste Welle umgesetzt über Login-Fenster- und SSH-Banner mit gemeinsamem Kennzeichnungstext |
| Root/Recovery/Firmware | `os_root_disable`, `os_recovery_lock_enable`, `os_firmware_password_require` | Teilweise organisationsabhängig, aber sicherheitsrelevant |
| Sudo-Detailhärtung | `os_sudo_log_enforce`, `os_sudoers_timestamp_type_configure` | Sehr guter Anschluss an den bestehenden `Sudo Timeout`-Check |
| Passwort-/Pwpolicy-Block | `pwpolicy_*` | Noch komplett außerhalb des heutigen Schemas |
| Softwareupdate-Stand | `system_settings_softwareupdate_current` | Hoher praktischer Wert |
| MDM-Anbindung | `os_mdm_require` | Erste Umfeldprüfung umgesetzt; spätere Vertiefung bleibt bei Issue `#1 MDM Status Watch` |

### Breiter Jamf-/NIST-Scope, aber aktuell bewusst außerhalb des Notary-Kerns

Diese Rules sind wichtig, würden den aktuellen Notary-Scope aber deutlich verbreitern und sollten bewusst als eigener Produktentscheid behandelt werden:

| Themenblock | Beispiel-Rules | Notiz |
| --- | --- | --- |
| iCloud-Dienste | `icloud_*`, `system_settings_find_my_disable` | Derzeit nicht Teil des Notary-Kerns |
| Apple Intelligence / AI / Writing Tools | `os_genmoji_disable`, `os_image_playground_disable`, `os_notes_transcription_*`, `os_writing_tools_disable`, `system_settings_external_intelligence_*` | Interessant für spätere Privacy-/AI-Policies |
| Prompt-/UX-Unterdrückung | `os_appleid_prompt_disable`, `os_privacy_setup_prompt_disable`, `os_skip_*`, `os_touchid_prompt_disable` | Eher Setup-/UX-Härtung als klassischer Compliance-Kern |
| Handoff / Watch / iPhone Mirroring / Relay | `os_handoff_disable`, `os_iphone_mirroring_disable`, `system_settings_apple_watch_unlock_disable`, `icloud_private_relay_disable` | Organisationsabhängig |
| Internet Accounts / Mail / Photos / Notes Einzelkontrollen | `system_settings_internet_accounts_disable`, `os_mail_summary_disable`, `os_photos_enhanced_search_disable` usw. | Gute spätere Ergänzungen, aber nicht erste Priorität |

### Empfehlung für den nächsten Abgleichsschritt

Nach diesem NIST-Vergleich ist die sinnvollste Reihenfolge:

1. `SSH-/SSHD-Härtung` als ersten fehlenden Technikblock schneiden.
2. `Audit-Flags / Audit-Fehlerreaktion` als zweiten Block ergänzen.
3. `Policy Banner` und `Sudo-Detailhärtung` als dritte Welle aufnehmen.
4. `MDM-Anforderung` bleibt fachlich mit Issue `#1` verbunden, ist aber als erste Umfeldprüfung bereits sichtbar.

### Kurzfazit

- Der heutige Notary-Stand deckt einen spürbaren Kern des Jamf-NIST-Skripts bereits ab.
- Der größte Abstand liegt aktuell nicht bei klassischen Kern-Härtungen wie Firewall, FileVault oder Sharing, sondern bei:
  - feingranularer Audit-Konfiguration
  - SSH-/SSHD-Härtung
  - Passwort-/Policy-Detailregeln
  - iCloud-/AI-/Privacy-Breiten-Scope
- Für ein sinnvolles „Gleichziehen“ mit Jamf NIST sollten wir nicht alles auf einmal übernehmen, sondern gezielt zuerst die technisch harten Blöcke nachziehen.

## CIS v8 Abgleich (Jamf-Stand vom 2026-04-29)

Das aktuelle Jamf-CIS-v8-Skript `compliance_benchmark_69f21d2998ef566f5d7de6ff_tahoe.sh.txt` enthält:

- `214` Rule-Blöcke insgesamt
- `155` eindeutige Rules nach Deduplizierung

Im Vergleich zum NIST-Skript ist CIS v8:

- etwas breiter bei klassischen Hardening-/Systemkontrollen
- stärker bei Passwort-, Update- und Systemverzeichnisregeln
- etwas schmaler bei einzelnen Privacy-/Cloud-Sonderfällen

### Bereits durch Notary gut oder teilweise abgedeckt

Diese CIS-v8-Rules fallen weitgehend in Themen, die Notary heute schon direkt oder nahe abdeckt:

| CIS-v8-Rule | Notary-Key / Check | Einordnung |
| --- | --- | --- |
| `system_settings_filevault_enforce` | `CoreSecurity.CheckFileVaultStatus` | Bereits abgedeckt |
| `os_gatekeeper_enable` | `CoreSecurity.CheckGateKeeperStatus` | Bereits abgedeckt |
| `os_sip_enable` | `CoreSecurity.CheckSIPStatus` | Bereits abgedeckt |
| `os_authenticated_root_enable` | `CoreSecurity.CheckARStatus` | Bereits abgedeckt |
| `os_config_data_install_enforce` | `CoreSecurity.UpdateXProtect` | Nahezu abgedeckt, aber nicht identisch |
| `system_settings_firewall_enable` | `Firewall.EnableFirewall` | Bereits abgedeckt |
| `system_settings_firewall_stealth_mode_enable` | `Firewall.EnableFirewallStealthMode` | Bereits abgedeckt |
| `system_settings_location_services_enable` | `Location.EnableLocationServices` | Bereits abgedeckt |
| `system_settings_diagnostics_reports_disable` | `DiagnosticsAudit.DisableDiagnosticData` | Bereits abgedeckt |
| `audit_auditd_enabled` | `DiagnosticsAudit.EnableSecurityAuditing` | Bereits abgedeckt |
| `os_install_log_retention_configure` | `DiagnosticsAudit.RetainInstallLog` | Bereits abgedeckt |
| `audit_acls_*`, `audit_control_*`, `audit_files_*`, `audit_folder_*`, `audit_folders_mode_configure` | `DiagnosticsAudit.LimitAuditRecordsAccess` | Teilweise abgedeckt, CIS ist deutlich feingranularer |
| `os_time_server_enabled` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `system_settings_time_server_configure` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `system_settings_time_server_enforce` | `TimeNTP.ForceTimeServer` | Bereits abgedeckt |
| `system_settings_content_caching_disable` | `Sharing.DisableContentCaching` | Bereits abgedeckt |
| `os_bonjour_disable` | `Sharing.DisableBonjourAdvertising` | Bereits abgedeckt |
| `system_settings_rae_disable` | `Sharing.DisableRemoteAppleEvents` | Bereits abgedeckt |
| `system_settings_screen_sharing_disable` | `Sharing.DisableScreenSharing` | Bereits abgedeckt |
| `system_settings_internet_sharing_disable` | `Sharing.DisableInternetSharing` | Bereits abgedeckt |
| `system_settings_printer_sharing_disable` | `Sharing.DisablePrinterSharing` | Bereits abgedeckt |
| `system_settings_ssh_disable` | `Sharing.DisableRemoteLogin` | Bereits abgedeckt |
| `system_settings_remote_management_disable` | `Sharing.DisableRemoteManagement` | Bereits abgedeckt |
| `system_settings_smbd_disable` | `Sharing.DisableFileSharing` | Bereits abgedeckt |
| `os_httpd_disable` | `Sharing.DisableHTTPServer` | Bereits abgedeckt |
| `os_nfsd_disable` | `Sharing.DisableNFSServer` | Bereits abgedeckt |
| `system_settings_wake_network_access_disable` | `PowerManagement.DisableWOMP` | Bereits abgedeckt |
| `os_power_nap_disable` | `PowerManagement.DisablePowerNap` | Bereits abgedeckt |
| `os_sleep_and_display_sleep_apple_silicon_enable` | `PowerManagement.ForceHibernateOnSleep` | Nur thematisch verwandt |
| `system_settings_automatic_login_disable` | `LoginWindow.DisableAutomaticLogin` | Bereits abgedeckt |
| `system_settings_loginwindow_prompt_username_password_enforce` | `LoginWindow.ForceLoginWindowFullName` | Teilweise verwandt |
| `system_settings_password_hints_disable` | `LoginWindow.DisablePasswordHints` | Bereits abgedeckt |
| `system_settings_guest_account_disable` | `LoginWindow.DisableGuestUser` | Bereits abgedeckt |
| `system_settings_guest_access_smb_disable` | `LoginWindow.DisableGuestAccessToShares` | Bereits abgedeckt |
| `system_settings_system_wide_preferences_configure` | `LoginWindow.ForceAdminPWForPreferences` | Bereits abgedeckt |
| `os_library_validation_enabled` | `LoginWindow.EnableLibraryValidation` | Bereits abgedeckt |
| `system_settings_bluetooth_sharing_disable` | `PerUser.DisableBluetoothSharing` | Bereits abgedeckt |
| `system_settings_media_sharing_disabled` | `PerUser.DisableMediaSharing` | Bereits abgedeckt |
| `os_airdrop_disable` | `PerUser.DisableAirDrop` | Bereits abgedeckt |
| `system_settings_personalized_advertising_disable` | `PerUser.DisableAdTracking` | Bereits abgedeckt |
| `os_terminal_secure_keyboard_enable` | `PerUser.EnableTerminalSecureKeyboard` | Bereits abgedeckt |
| `system_settings_siri_disable` | `PerUser.DisableSiri` | Bereits abgedeckt |
| `system_settings_wifi_menu_enable` | `PerUser.ForceShowWifiStatus` | Bereits abgedeckt |
| `os_home_folders_secure` | `PerUser.SecureHomeFolders` | Bereits abgedeckt |
| `os_password_hint_remove` | `PerUser.RemoveUserPasswordHints` | Bereits abgedeckt |
| `os_safari_open_safe_downloads_disable` | `PerUser.DisableSafariDownloadAutoRun` | Bereits abgedeckt |

### Neu oder deutlich unterrepräsentiert gegenüber CIS v8

Diese CIS-v8-Bereiche fehlen im aktuellen Notary-Schema oder sind nur am Rand sichtbar:

| Themenblock | Beispiel-Rules | Einschätzung |
| --- | --- | --- |
| Audit-Control-Datei und Audit-Flags | `audit_control_*`, `audit_flags_*` | Starker fehlender Audit-Detailblock |
| Softwareupdate / Patchmanagement | `system_settings_softwareupdate_current`, `system_settings_critical_update_install_enforce`, `system_settings_download_software_update_enforce`, `system_settings_install_macos_updates_enforce`, `system_settings_security_update_install`, `system_settings_software_update_download_enforce`, `os_software_update_app_update_enforce` | Sehr hoher praktischer Wert |
| Passwort-/Pwpolicy-Härtung | `pwpolicy_*`, `pwpolicy_alpha_numeric_enforce`, `pwpolicy_special_character_enforce`, `pwpolicy_max_lifetime_enforce`, `pwpolicy_minimum_lifetime_enforce` | Noch komplett außerhalb des Schemas |
| SSH-/SSHD-Detailhärtung | `auth_ssh_password_authentication_disable`, `os_ssh_fips_compliant`, `os_ssh_server_alive_*`, `os_sshd_*` | Gleiches Defizit wie im NIST-Abgleich |
| Sudo-Detailhärtung | `os_sudo_log_enforce`, `os_sudo_timeout_configure`, `os_sudoers_timestamp_type_configure` | Gute nächste Welle |
| Systemverzeichnisse / Schreibrechte | `os_world_writable_library_folder_configure`, `os_world_writable_system_folder_configure`, `os_system_wide_applications_configure` | Klassischer CIS-Block, aktuell nicht vorhanden |
| Banner / Login-Text | `system_settings_loginwindow_loginwindowtext_enable` | Fehlender UI-/Policy-Banner-Block |
| Bluetooth / AirPlay / Wallet / Wi‑Fi Settings | `system_settings_bluetooth_disable`, `system_settings_airplay_receiver_disable`, `system_settings_wallet_applepay_settings_disable`, `system_settings_wifi_disable`, `system_settings_bluetooth_settings_disable`, `system_settings_touch_id_settings_disable` | Neuer Geräte-/UX-Härtungsblock |
| Time Machine | `system_settings_time_machine_auto_backup_enable`, `system_settings_time_machine_encrypted_configure` | Produktentscheidung nötig |
| Directory / MDM / Anti-Virus | `os_directory_services_configured`, `os_mdm_require`, `os_anti_virus_installed` | Umgebungsabhängig, aber relevant |

### Überschneidung NIST und CIS: klare gemeinsame Kandidaten

Diese Themen tauchen in beiden Referenzfamilien auf und sind damit die stärksten Kandidaten für die nächste Notary-Welle:

| Gemeinsamer Themenblock | NIST | CIS | Empfehlung |
| --- | --- | --- | --- |
| SSH-/SSHD-Härtung | Ja | Ja | Höchste Priorität |
| Audit-Flags / Audit-Failure / Audit-Feinrechte | Ja | Ja | Höchste Priorität |
| Sudo-Detailhärtung | Ja | Ja | Sehr hohe Priorität |
| Policy Banner | Ja | Teilweise / angrenzend | Erste Welle umgesetzt |
| MDM-Anforderung | Ja | Ja | Erste Umfeldprüfung umgesetzt; spätere Vertiefung mit Issue `#1` |
| Softwareupdate-Stand | NIST begrenzt | CIS stark | Hohe praktische Priorität |
| Passwort-/Pwpolicy-Regeln | NIST stark | CIS sehr stark | Eigener großer Themenblock |

### Gemeinsame Priorisierung auf Basis von Notary, NIST und CIS

Wenn wir Notary an beide Jamf-Referenzlinien angleichen wollen, ist die sinnvollste Reihenfolge:

1. `SSH-/SSHD-Härtung`
   Status: erste Welle umgesetzt über `DisableSSHPasswordAuthentication`,
   `ConfigureSSHClientAliveInterval` und `ConfigureSSHClientAliveCountMax`;
   offen bleiben `os_ssh_fips_compliant` und weitere `os_sshd_*`-Details
2. `Audit-Detailblock`
   Status: erste Welle umgesetzt über `EnableAuditFailureHalt` und `ConfigureAuditFlagsCore`;
   offen bleiben `audit_control_*`, weitere `audit_flags_*`-Breite und `audit_settings_failure_notify`
3. `Sudo-/Privilege-Härtung`
   `os_sudo_log_enforce`, `os_sudo_timeout_configure`, `os_sudoers_timestamp_type_configure`
4. `Software Update / Patch Compliance`
   `system_settings_softwareupdate_current` plus CIS-Update-Install-Regeln
5. `Pwpolicy-Block`
   `pwpolicy_*`
6. `MDM / Directory / Produktabhängige Checks`
   Status: erste Welle umgesetzt über `RequireMDMEnrollment`,
   `RequireDirectoryService` und `RequireSecurityAgent`

### Ergebnis

Mit dem CIS-v8-Abgleich bestätigt sich das Bild aus NIST:

- Notary ist bei den sichtbaren Kern-Härtungen bereits erstaunlich nah dran.
- Die größten Lücken liegen nicht mehr in „einfachen“ Desktop-Settings, sondern in tieferen Systemblöcken:
  - SSH
  - Audit
  - Sudo
  - Update-/Patch-Härtung
  - Pwpolicy
- Genau diese Blöcke tauchen jetzt sowohl in NIST als auch in CIS als gemeinsame nächste Ausbaurichtung auf.
