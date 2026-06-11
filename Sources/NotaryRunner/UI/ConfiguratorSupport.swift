import Foundation

final class ConfigNode: NSObject {
    enum Kind {
        case section
        case field
    }

    let keyPath: String
    let title: String
    let summary: String
    let kind: Kind
    let type: String
    let defaultValue: String?
    let allowedValues: [String]
    let allowedValueTitles: [String]
    let children: [ConfigNode]

    init(
        keyPath: String,
        title: String,
        summary: String,
        kind: Kind,
        type: String,
        defaultValue: String?,
        allowedValues: [String],
        allowedValueTitles: [String],
        children: [ConfigNode]
    ) {
        self.keyPath = keyPath
        self.title = title
        self.summary = summary
        self.kind = kind
        self.type = type
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
        self.allowedValueTitles = allowedValueTitles
        self.children = children
    }
}

extension ConfigNode {
    func matchesSearchTerms(_ terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let haystack = [
            title,
            keyPath,
            summary,
            type,
            defaultValue ?? "",
            allowedValues.joined(separator: " "),
            allowedValueTitles.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return terms.allSatisfy { haystack.contains($0) }
    }
}

struct ConfigFieldHelp {
    let summary: String
    let compatibility: String?

    static func lookup(_ keyPath: String) -> ConfigFieldHelp? {
        byKeyPath[keyPath]
    }

    private static let byKeyPath: [String: ConfigFieldHelp] = [
        "Org.OrgName": .init(
            summary: "Name der Organisation, der für automatisch erzeugte Login- und SSH-Hinweistexte verwendet werden kann.",
            compatibility: nil
        ),
        "Org.OrgContact": .init(
            summary: "Kontaktangabe für Support, Sicherheit oder Betreiber. Sie kann in automatisch erzeugten Hinweistexen erscheinen.",
            compatibility: nil
        ),
        "CoreSecurity.UpdateXProtect": .init(
            summary: "XProtect ist Apples integrierter Malware-Schutz. Diese Einstellung prüft oder erzwingt, dass die Signaturen und Schutzkomponenten automatisch aktuell gehalten werden.",
            compatibility: "macOS integrierte Sicherheitsfunktion; die genaue Update-Architektur ist abhängig von der macOS-Version"
        ),
        "CoreSecurity.CheckFileVaultStatus": .init(
            summary: "FileVault ist die in macOS integrierte Festplattenverschlüsselung. Sie schützt persönliche Daten auf dem Mac vor unbefugtem Zugriff, indem sie das Startvolume verschlüsselt.",
            compatibility: "FileVault 2 ab Mac OS X 10.7 Lion"
        ),
        "CoreSecurity.CheckGateKeeperStatus": .init(
            summary: "Gatekeeper ist eine integrierte Sicherheitsfunktion in macOS. Sie dient als digitaler Türsteher und verhindert, dass versehentlich Schadsoftware auf dem Mac ausgeführt wird.",
            compatibility: "ab Mac OS X 10.8 Mountain Lion"
        ),
        "CoreSecurity.CheckSIPStatus": .init(
            summary: "System Integrity Protection schützt zentrale Systembereiche vor ungewollten Änderungen, auch durch Prozesse mit Administratorrechten.",
            compatibility: "ab OS X 10.11 El Capitan"
        ),
        "CoreSecurity.CheckARStatus": .init(
            summary: "Das Sealed System Volume (SSV), auch signiertes Systemvolume, schützt macOS vor Manipulationen, indem Systemdateien kryptografisch versiegelt werden.",
            compatibility: "ab macOS 11 Big Sur"
        ),
        "Firewall.EnableFirewall": .init(
            summary: "Die macOS Application Firewall kontrolliert eingehende Netzwerkverbindungen und reduziert die Angriffsfläche lokaler Dienste.",
            compatibility: "macOS integrierte Application Firewall"
        ),
        "Firewall.EnableFirewallStealthMode": .init(
            summary: "Stealth Mode lässt den Mac auf unerwartete Netzwerk-Anfragen weniger sichtbar reagieren, zum Beispiel auf bestimmte Ping- oder Scan-Versuche.",
            compatibility: "macOS integrierte Application Firewall"
        ),
        "Firewall.EnableFirewallBlockAllIncoming": .init(
            summary: "Blockiert möglichst alle eingehenden Verbindungen und erlaubt nur systemnotwendige Dienste. Das ist eine strenge Firewall-Option für besonders restriktive Umgebungen.",
            compatibility: "macOS integrierte Application Firewall"
        ),
        "Firewall.EnableFirewallAllowSigned": .init(
            summary: "Erlaubt eingehende Verbindungen für signierte und vertrauenswürdige Apps automatisch. Das ist komfortabler, aber weniger strikt als manuelle Freigaben.",
            compatibility: "macOS integrierte Application Firewall"
        ),
        "DiagnosticsAudit.DisableDiagnosticData": .init(
            summary: "Verhindert, dass Diagnose- und Nutzungsdaten automatisch an Apple gesendet werden. Das unterstützt Datenschutzvorgaben in verwalteten Umgebungen.",
            compatibility: nil
        ),
        "DiagnosticsAudit.EnableSecurityAuditing": .init(
            summary: "Aktiviert das macOS Security Auditing, damit sicherheitsrelevante Ereignisse nachvollziehbar protokolliert werden.",
            compatibility: "macOS auditd / OpenBSM"
        ),
        "DiagnosticsAudit.RetainInstallLog": .init(
            summary: "Stellt sicher, dass die Installationshistorie länger nachvollziehbar bleibt. Das hilft bei Audits, Fehleranalyse und späterer Ursachenklärung.",
            compatibility: nil
        ),
        "DiagnosticsAudit.LimitAuditRecordsAccess": .init(
            summary: "Beschränkt den Zugriff auf Audit-Logs auf privilegierte Konten. So bleiben sicherheitsrelevante Protokolle vor normalen Benutzern geschützt.",
            compatibility: "macOS auditd / OpenBSM"
        ),
        "Location.EnableLocationServices": .init(
            summary: "Prüft oder aktiviert Ortungsdienste. Das kann für Funktionen wie Zeitzone, Wiederfinden oder bestimmte Verwaltungsprozesse relevant sein.",
            compatibility: "macOS Ortungsdienste"
        ),
        "ScreenSaver.SetScreenSaverDelay": .init(
            summary: "Legt fest, ob Notary den Zeitraum bis zum Bildschirmschoner oder zur Inaktivität überwachen beziehungsweise setzen soll.",
            compatibility: nil
        ),
        "ScreenSaver.ScreenSaverDelay": .init(
            summary: "Definiert, nach welcher Inaktivitätszeit der Bildschirmschoner beziehungsweise die Sperrlogik greifen soll.",
            compatibility: nil
        ),
        "ScreenSaver.RequirePasswordOnWake": .init(
            summary: "Verlangt nach Ruhezustand oder Bildschirmschoner wieder eine Authentifizierung. Das schützt eine unbeaufsichtigte Sitzung.",
            compatibility: nil
        ),
        "ScreenSaver.ScreenSaverPasswordDelay": .init(
            summary: "Definiert, wie schnell nach Bildschirmschoner oder Display-Abschaltung wieder ein Passwort erforderlich ist.",
            compatibility: nil
        ),
        "TimeNTP.ForceTimeServer": .init(
            summary: "Legt fest, ob Notary Zeitserver und Zeitzone verwalten soll. Korrekte Zeit ist wichtig für Zertifikate, Logs und Authentifizierung.",
            compatibility: nil
        ),
        "TimeNTP.TimeServer": .init(
            summary: "Zeitserver, den macOS für die automatische Zeitsynchronisierung verwenden soll.",
            compatibility: nil
        ),
        "TimeNTP.DefaultTimeZone": .init(
            summary: "Optionale Standard-Zeitzone für verwaltete Geräte, zum Beispiel Europe/Berlin.",
            compatibility: nil
        ),
        "Sharing.DisableBonjourAdvertising": .init(
            summary: "Deaktiviert Bonjour-Ankündigungen, damit der Mac lokale Dienste nicht unnötig im Netzwerk sichtbar macht.",
            compatibility: "Bonjour / mDNSResponder"
        ),
        "Sharing.DisableRemoteAppleEvents": .init(
            summary: "Deaktiviert Remote Apple Events. Dadurch können entfernte Macs keine AppleScript-/Automation-Befehle an dieses Gerät senden.",
            compatibility: nil
        ),
        "Sharing.DisableInternetSharing": .init(
            summary: "Deaktiviert die Internetfreigabe, damit der Mac nicht unbeabsichtigt als Router oder Netzwerkbrücke arbeitet.",
            compatibility: nil
        ),
        "Sharing.DisableScreenSharing": .init(
            summary: "Deaktiviert Bildschirmfreigabe, um interaktive Fernzugriffe über die macOS-Freigabefunktion zu verhindern.",
            compatibility: nil
        ),
        "Sharing.DisablePrinterSharing": .init(
            summary: "Deaktiviert Druckerfreigabe, damit lokal eingerichtete Drucker nicht automatisch im Netzwerk angeboten werden.",
            compatibility: nil
        ),
        "Sharing.DisableRemoteLogin": .init(
            summary: "Deaktiviert Remote Login über SSH, wenn auf dem Gerät kein administrativer SSH-Zugriff vorgesehen ist.",
            compatibility: "macOS Remote Login / OpenSSH"
        ),
        "Sharing.DisableDVDSharing": .init(
            summary: "Deaktiviert CD-/DVD-Freigabe. Diese ältere Freigabefunktion ist in modernen Umgebungen meist nicht mehr erforderlich.",
            compatibility: "relevant vor allem für ältere macOS- und Hardware-Generationen"
        ),
        "Sharing.DisableFileSharing": .init(
            summary: "Deaktiviert Dateifreigabe, damit lokale Ordner nicht per SMB oder verwandten Diensten im Netzwerk verfügbar sind.",
            compatibility: nil
        ),
        "Sharing.DisableRemoteManagement": .init(
            summary: "Deaktiviert Apple Remote Management, sofern das Gerät nicht bewusst über ARD verwaltet werden soll.",
            compatibility: "Apple Remote Desktop / Remote Management"
        ),
        "Sharing.DisableContentCaching": .init(
            summary: "Deaktiviert Content Caching, damit der Mac keine Apple-Inhalte für andere Geräte im Netzwerk zwischenspeichert.",
            compatibility: "ab macOS 10.13 High Sierra"
        ),
        "Sharing.DisableHTTPServer": .init(
            summary: "Stoppt beziehungsweise deaktiviert einen lokalen Apache HTTP-Server, wenn auf dem Mac kein Webdienst betrieben werden soll.",
            compatibility: "Apache/httpd auf macOS"
        ),
        "Sharing.DisableNFSServer": .init(
            summary: "Stoppt beziehungsweise deaktiviert NFS-Freigaben, wenn auf dem Mac kein NFS-Dateidienst vorgesehen ist.",
            compatibility: "NFS-Dienst auf macOS"
        ),
        "PowerManagement.DisableWOMP": .init(
            summary: "Deaktiviert Wake for Network Access, damit Netzwerkereignisse den Mac nicht unnötig aus dem Ruhezustand wecken.",
            compatibility: nil
        ),
        "PowerManagement.DisablePowerNap": .init(
            summary: "Deaktiviert Power Nap. Diese Funktion erlaubte bestimmten Intel-Macs, im Ruhezustand Aufgaben wie Mail- oder iCloud-Aktualisierungen auszuführen.",
            compatibility: "Intel-Macs; auf Apple Silicon nicht relevant"
        ),
        "PowerManagement.ForceHibernateOnSleep": .init(
            summary: "Erzwingt einen restriktiveren Schlafmodus, bei dem der Arbeitsspeicherinhalt auf das verschlüsselte Laufwerk geschrieben wird.",
            compatibility: nil
        ),
        "PowerManagement.DestroyFileVaultKeyOnStandby": .init(
            summary: "Entfernt FileVault-Schlüssel aus dem Speicher, wenn das Gerät in Standby geht. Das reduziert Risiken bei physischem Zugriff auf ein schlafendes Gerät.",
            compatibility: "FileVault 2"
        ),
        "LoginWindow.DisableAutomaticLogin": .init(
            summary: "Deaktiviert automatische Anmeldung, damit nach Neustart oder Abmeldung immer eine Benutzer-Authentifizierung erforderlich ist.",
            compatibility: nil
        ),
        "LoginWindow.ForceLoginWindowFullName": .init(
            summary: "Zeigt im Login-Fenster keine Benutzerliste an, sondern verlangt Name und Passwort. Das erschwert das Erraten gültiger lokaler Konten.",
            compatibility: nil
        ),
        "LoginWindow.DisablePasswordHints": .init(
            summary: "Deaktiviert Passwort-Hinweise, damit keine zusätzlichen Informationen über lokale Benutzerkennwörter angezeigt werden.",
            compatibility: nil
        ),
        "LoginWindow.SudoTimeout": .init(
            summary: "Legt fest, wie lange eine sudo-Authentifizierung wiederverwendet werden darf, bevor erneut ein Passwort erforderlich ist.",
            compatibility: "sudo"
        ),
        "LoginWindow.DisableGuestUser": .init(
            summary: "Deaktiviert den Gastbenutzer, damit sich niemand ohne persönliches Konto lokal anmelden kann.",
            compatibility: nil
        ),
        "LoginWindow.DisableGuestAccessToShares": .init(
            summary: "Verhindert Gastzugriff auf Dateifreigaben. Netzwerkzugriffe sollen dadurch authentifizierten Konten vorbehalten bleiben.",
            compatibility: nil
        ),
        "LoginWindow.RemoveGuestHomeFolder": .init(
            summary: "Entfernt verbliebene Gastbenutzer-Daten nach der Nutzung, damit temporäre lokale Daten nicht liegen bleiben.",
            compatibility: nil
        ),
        "LoginWindow.ForceAdminPWForPreferences": .init(
            summary: "Verlangt ein Administratorpasswort für systemweite Einstellungen, damit Standardbenutzer keine sicherheitsrelevanten Änderungen vornehmen.",
            compatibility: nil
        ),
        "LoginWindow.DisableFastUserSwitching": .init(
            summary: "Deaktiviert schnellen Benutzerwechsel. Diese ältere Benchmark-Empfehlung verhindert parallel angemeldete GUI-Sitzungen.",
            compatibility: "bis macOS 10.15 Catalina relevant"
        ),
        "LoginWindow.EnableLibraryValidation": .init(
            summary: "Prüft die Aktivierung von Library Validation, damit Prozesse nur vertrauenswürdige Bibliotheken laden.",
            compatibility: "Hardened Runtime / Library Validation; abhängig von macOS-Version und App-Kontext"
        ),
        "PerUser.DisableBluetoothSharing": .init(
            summary: "Deaktiviert Bluetooth-Sharing je Benutzer, damit Dateien nicht unbeabsichtigt über Bluetooth angenommen oder angeboten werden.",
            compatibility: nil
        ),
        "PerUser.DisableMediaSharing": .init(
            summary: "Deaktiviert Medienfreigabe je Benutzer, damit lokale Musik-, TV- oder Medienbibliotheken nicht im Netzwerk erscheinen.",
            compatibility: nil
        ),
        "PerUser.DisableAirDrop": .init(
            summary: "Deaktiviert AirDrop je Benutzer, wenn spontane Dateiübertragung in der Umgebung nicht erlaubt ist.",
            compatibility: "AirDrop-fähige Macs"
        ),
        "PerUser.DisableAdTracking": .init(
            summary: "Deaktiviert personalisierte Werbung je Benutzer und reduziert damit Tracking- beziehungsweise Profiling-Oberflächen.",
            compatibility: nil
        ),
        "PerUser.EnableTerminalSecureKeyboard": .init(
            summary: "Aktiviert Secure Keyboard Entry in Terminal, damit andere Prozesse Tastatureingaben schwerer mitlesen können.",
            compatibility: "Terminal.app"
        ),
        "PerUser.DisableSiri": .init(
            summary: "Deaktiviert Siri je Benutzer, wenn Sprachassistenz oder die zugehörige Datenverarbeitung nicht gewünscht ist.",
            compatibility: "ab macOS 10.12 Sierra"
        ),
        "PerUser.ForceShowWifiStatus": .init(
            summary: "Blendet den WLAN-Status in der Menüleiste ein, damit Benutzer und Support Netzwerkzustände schneller erkennen.",
            compatibility: nil
        ),
        "PerUser.SecureHomeFolders": .init(
            summary: "Härtet Benutzer-Home-Verzeichnisse, damit andere lokale Benutzer nicht unnötig auf persönliche Dateien zugreifen können.",
            compatibility: "lokale macOS-Benutzerkonten"
        ),
        "PerUser.LockLoginKeychain": .init(
            summary: "Sperrt den Login-Schlüsselbund nach Inaktivität, damit gespeicherte Geheimnisse nicht dauerhaft in einer offenen Sitzung verfügbar bleiben.",
            compatibility: "macOS Schlüsselbund"
        ),
        "PerUser.LockKeychainInactivity": .init(
            summary: "Zeitspanne bis zur automatischen Sperre des Login-Schlüsselbunds.",
            compatibility: "macOS Schlüsselbund"
        ),
        "PerUser.RemoveUserPasswordHints": .init(
            summary: "Entfernt Passwort-Hinweise aus Benutzerkonten, damit lokale Hinweise keine Kennwortinformationen preisgeben.",
            compatibility: nil
        ),
        "PerUser.ForceShowFileNameExtensions": .init(
            summary: "Zeigt Dateiendungen im Finder an, damit Dateitypen und potenziell irreführende Namen besser erkennbar sind.",
            compatibility: "Finder"
        ),
        "PerUser.DisableSafariDownloadAutoRun": .init(
            summary: "Verhindert, dass Safari als sicher eingestufte Downloads automatisch öffnet. Dadurch bleibt der Benutzer vor der Ausführung eingebunden.",
            compatibility: "Safari"
        )
    ]
}

enum ConfigSchemaLoader {
    static func loadNodes() throws -> [ConfigNode] {
        guard let url = bundledSchemaURL() else {
            throw NSError(domain: "NotaryConfigurator", code: 404, userInfo: [NSLocalizedDescriptionKey: "Config schema not found in app resources."])
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any],
              let properties = root["properties"] as? [String: Any] else {
            throw NSError(domain: "NotaryConfigurator", code: 422, userInfo: [NSLocalizedDescriptionKey: "Invalid schema format."])
        }

        return sortedPropertyEntries(from: properties).compactMap { key, node in
            buildNode(key: key, path: key, node: node)
        }
    }

    private static func buildNode(key: String, path: String, node: [String: Any]) -> ConfigNode? {
        let title = (node["title"] as? String) ?? key
        let description = (node["description"] as? String) ?? ""
        let type = (node["type"] as? String) ?? "unknown"
        let defaultValue = stringify(node["default"])
        let summary = description.isEmpty ? inferredSummary(for: node, type: type) : description

        if type == "object", let properties = node["properties"] as? [String: Any] {
            let children = sortedPropertyEntries(from: properties).compactMap { childKey, childNode in
                buildNode(key: childKey, path: "\(path).\(childKey)", node: childNode)
            }
            return ConfigNode(
                keyPath: path,
                title: title,
                summary: summary,
                kind: .section,
                type: type,
                defaultValue: nil,
                allowedValues: [],
                allowedValueTitles: [],
                children: children
            )
        }

        let allowedValues = (node["enum"] as? [Any])?.map { stringify($0) ?? String(describing: $0) } ?? []
        let options = node["options"] as? [String: Any]
        let allowedTitles = (options?["enum_titles"] as? [String]) ?? []
        return ConfigNode(
            keyPath: path,
            title: title,
            summary: summary,
            kind: .field,
            type: type,
            defaultValue: defaultValue,
            allowedValues: allowedValues,
            allowedValueTitles: allowedTitles,
            children: []
        )
    }

    private static func sortedPropertyEntries(from properties: [String: Any]) -> [(String, [String: Any])] {
        properties.compactMap { key, value in
            guard let dict = value as? [String: Any] else { return nil }
            return (key, dict)
        }
        .sorted { lhs, rhs in
            let lhsOrder = (lhs.1["propertyOrder"] as? Int) ?? .max
            let rhsOrder = (rhs.1["propertyOrder"] as? Int) ?? .max
            if lhsOrder == rhsOrder { return lhs.0 < rhs.0 }
            return lhsOrder < rhsOrder
        }
    }

    private static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return String(describing: value)
    }

    private static func inferredSummary(for node: [String: Any], type: String) -> String {
        switch type {
        case "object":
            return "Schema section"
        case "string", "integer", "number", "boolean":
            if let values = node["enum"] as? [Any], !values.isEmpty {
                return "Allowed values: \(values.map { stringify($0) ?? String(describing: $0) }.joined(separator: ", "))"
            }
            return "Config field"
        default:
            return "Schema field"
        }
    }

    private static func bundledSchemaURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "Config-Schema-1.2", withExtension: "json") {
            return bundled
        }

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Config-Schema-1.2.json")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }
}

enum MobileConfigImport {
    static func importNotaryValues(from url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        guard let root = plist as? [String: Any] else {
            throw NSError(domain: "NotaryConfigurator", code: 422, userInfo: [NSLocalizedDescriptionKey: "Invalid plist structure."])
        }

        let settings = try managedPreferencesSettings(from: root)
        var result: [String: String] = [:]
        flatten(settings: settings, prefix: nil, into: &result)
        if result.isEmpty {
            throw NSError(domain: "NotaryConfigurator", code: 422, userInfo: [NSLocalizedDescriptionKey: "No importable Notary settings found in the selected file."])
        }
        return result
    }

    private static func managedPreferencesSettings(from root: [String: Any]) throws -> [String: Any] {
        if let settings = managedPreferencesPayloadSettings(from: root) {
            return settings
        }

        if root["PayloadContent"] != nil {
            throw NSError(domain: "NotaryConfigurator", code: 404, userInfo: [NSLocalizedDescriptionKey: "No `de.twocent.notary` payload found in the selected mobileconfig."])
        }

        if let forced = root["Forced"] as? [[String: Any]],
           let firstForced = forced.first,
           let settings = firstForced["mcx_preference_settings"] as? [String: Any] {
            return settings
        }

        return root
    }

    private static func managedPreferencesPayloadSettings(from root: [String: Any]) -> [String: Any]? {
        guard let payloads = root["PayloadContent"] as? [[String: Any]] else { return nil }

        for payload in payloads {
            guard let payloadType = payload["PayloadType"] as? String,
                  payloadType == "com.apple.ManagedClient.preferences",
                  let payloadContent = payload["PayloadContent"] as? [String: Any],
                  let notaryDomain = payloadContent["de.twocent.notary"] as? [String: Any],
                  let forced = notaryDomain["Forced"] as? [[String: Any]],
                  let firstForced = forced.first,
                  let settings = firstForced["mcx_preference_settings"] as? [String: Any] else {
                continue
            }

            return settings
        }

        return nil
    }

    private static func flatten(settings: [String: Any], prefix: String?, into result: inout [String: String]) {
        for (key, value) in settings {
            let path = prefix == nil ? key : "\(prefix!).\(key)"
            if let nested = value as? [String: Any] {
                flatten(settings: nested, prefix: path, into: &result)
            } else if let string = stringify(value) {
                result[path] = string
            }
        }
    }

    private static func stringify(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return String(describing: value)
    }
}

enum MobileConfigExport {
    private static let domain = "de.twocent.notary"
    private static let appBundleIdentifier = "de.twocent.notary.app"
    private static let serviceIdentifier = "de.twocent.notary.service"
    private static let teamIdentifier = "KP5T66DWT2"
    private static let defaultDisplayName = "Notary Compliance Reporting"
    private static let defaultOrganization = "TwoCent Labs"

    static func exportProfile(configState: [String: String], nodes: [ConfigNode], to url: URL) throws -> Int {
        let fieldMap = collectFieldMap(from: nodes)
        let managedSettings = buildManagedSettings(from: configState, fieldMap: fieldMap)
        let organization = normalizedOrganization(from: configState)
        let profile = buildProfile(managedSettings: managedSettings, organization: organization)
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        return fieldMap.count
    }

    private static func buildProfile(managedSettings: [String: Any], organization: String) -> [String: Any] {
        let rootUUID = UUID().uuidString
        return [
            "PayloadContent": [
                makePPPCPayload(organization: organization),
                makeManagedPreferencesPayload(settings: managedSettings, organization: organization),
                makeManagedLoginItemsPayload(organization: organization),
                makeNotificationPayload(organization: organization),
            ],
            "PayloadDescription": "",
            "PayloadDisplayName": defaultDisplayName,
            "PayloadEnabled": true,
            "PayloadIdentifier": "de.twocent.notary.profile.\(rootUUID)",
            "PayloadOrganization": organization,
            "PayloadRemovalDisallowed": true,
            "PayloadScope": "System",
            "PayloadType": "Configuration",
            "PayloadUUID": rootUUID,
            "PayloadVersion": 1,
        ]
    }

    private static func makePPPCPayload(organization: String) -> [String: Any] {
        let payloadUUID = UUID().uuidString
        let codeRequirement = """
        identifier "\(serviceIdentifier)" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \(teamIdentifier)
        """
        return [
            "PayloadDescription": "",
            "PayloadDisplayName": "PRIVACY_PREFERENCES_POLICY_CONTROL",
            "PayloadEnabled": true,
            "PayloadIdentifier": payloadUUID,
            "PayloadOrganization": organization,
            "PayloadType": "com.apple.TCC.configuration-profile-policy",
            "PayloadUUID": payloadUUID,
            "PayloadVersion": 1,
            "Services": [
                "SystemPolicyAllFiles": [[
                    "Allowed": true,
                    "CodeRequirement": codeRequirement,
                    "Identifier": serviceIdentifier,
                    "IdentifierType": "bundleID",
                    "StaticCode": false,
                ]]
            ],
        ]
    }

    private static func makeManagedPreferencesPayload(settings: [String: Any], organization: String) -> [String: Any] {
        let payloadUUID = UUID().uuidString
        return [
            "PayloadContent": [
                domain: [
                    "Forced": [[
                        "mcx_preference_settings": settings,
                    ]]
                ]
            ],
            "PayloadDisplayName": "Custom Settings",
            "PayloadIdentifier": payloadUUID,
            "PayloadOrganization": organization,
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadUUID": payloadUUID,
            "PayloadVersion": 1,
        ]
    }

    private static func makeManagedLoginItemsPayload(organization: String) -> [String: Any] {
        let payloadUUID = UUID().uuidString
        return [
            "PayloadDisplayName": "Managed Login Items",
            "PayloadIdentifier": payloadUUID,
            "PayloadOrganization": organization,
            "PayloadType": "com.apple.servicemanagement",
            "PayloadUUID": payloadUUID,
            "PayloadVersion": 1,
            "Rules": [
                [
                    "RuleType": "BundleIdentifier",
                    "RuleValue": appBundleIdentifier,
                    "TeamIdentifier": teamIdentifier,
                ],
                [
                    "RuleType": "BundleIdentifier",
                    "RuleValue": serviceIdentifier,
                    "TeamIdentifier": teamIdentifier,
                ],
            ],
        ]
    }

    private static func makeNotificationPayload(organization: String) -> [String: Any] {
        let payloadUUID = UUID().uuidString
        return [
            "NotificationSettings": [[
                "BundleIdentifier": "com.apple.btmnotificationsagent",
                "CriticalAlertEnabled": false,
                "NotificationsEnabled": false,
            ]],
            "PayloadDisplayName": "Notifications Payload",
            "PayloadIdentifier": payloadUUID,
            "PayloadOrganization": organization,
            "PayloadType": "com.apple.notificationsettings",
            "PayloadUUID": payloadUUID,
            "PayloadVersion": 1,
        ]
    }

    private static func normalizedOrganization(from configState: [String: String]) -> String {
        let raw = configState["Org.OrgName"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? defaultOrganization : raw
    }

    private static func collectFieldMap(from nodes: [ConfigNode]) -> [String: ConfigNode] {
        var result: [String: ConfigNode] = [:]
        for node in nodes {
            if node.kind == .field {
                result[node.keyPath] = node
            }
            if !node.children.isEmpty {
                result.merge(collectFieldMap(from: node.children)) { _, new in new }
            }
        }
        return result
    }

    private static func buildManagedSettings(from configState: [String: String], fieldMap: [String: ConfigNode]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in fieldMap.keys.sorted() {
            guard let node = fieldMap[key] else { continue }
            let rawValue = configState[key] ?? node.defaultValue ?? ""
            insert(value: typedValue(rawValue, for: node), into: &result, at: key)
        }
        return result
    }

    private static func typedValue(_ rawValue: String, for node: ConfigNode) -> Any {
        switch node.type {
        case "boolean":
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "on"
        case "integer":
            return Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        default:
            return rawValue
        }
    }

    private static func insert(value: Any, into dictionary: inout [String: Any], at keyPath: String) {
        let components = keyPath.split(separator: ".").map(String.init)
        insert(value: value, into: &dictionary, components: components)
    }

    private static func insert(value: Any, into dictionary: inout [String: Any], components: [String]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            dictionary[head] = value
            return
        }
        var child = dictionary[head] as? [String: Any] ?? [:]
        insert(value: value, into: &child, components: Array(components.dropFirst()))
        dictionary[head] = child
    }
}
