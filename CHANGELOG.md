# Changelog

Alle wesentlichen Änderungen an Notary sollen hier in knapper Form dokumentiert werden.

## Unreleased

- Report-GUI als gerätebezogenes Dashboard überarbeitet, inklusive Seriennummer, Hardware-Modell, Management-Zuordnung und Build-Hinweis im Kopfbereich.
- Jamf Reporter als lokale Admin-Ansicht ergänzt: filterbare Geräteliste aus Jamf sowie Detailblöcke für letzten Transport, Proof und gruppierte Notary-Issues pro Gerät.
- Transporter erkennt eine vorhandene `Notary Percent`-EA nachträglich und aktiviert das Prozent-Reporting automatisch; bei manuell in Jamf angelegter EA kann dies wegen EA-Cache/Cooldown ohne erneuten Deploy-Lauf bis zu 24 Stunden dauern.
- Konfigurator um schema-basierten Editor, Import bestehender `.mobileconfig`-Werte für `de.twocent.notary` und Export einer vollständigen Mobileconfig mit Betriebs-Payloads erweitert.
- Neuen System-Uptime-Check mit konfigurierbaren Schwellenwerten für Warnung und Maximal-Laufzeit ergänzt.
- Sichtbaren Uptime-Hinweis in `Notary.app` ergänzt, inklusive 24h-Cooldown sowie Unterdrückung bei Vollbild- und aktiver Screen-Sharing-Sitzung.
- Uptime-Hinweis-Start auf entkoppelten GUI-Spawn umgestellt und Hinweisfenster in Größe und Lebenszyklus stabilisiert.
- Persistente Wiederverwendung des Jamf-API-Tokens mit Erneuerung erst bei Ablauf eingeführt.
- Transport-Updates auf Änderungen der Findings begrenzt.
- Heartbeat des Transporters auf 60 Minuten reduziert und an erfolgreiche Updates gekoppelt.
- GitHub-Repository, `main`-Branch und Start-Tag `v2.0.0` eingerichtet.
- Repository-Dokumentation an den aktuellen Runner-/Transporter-Stand angepasst.
- Unterschied zwischen heutigem Runner und geplantem Engagement in der Doku geschärft.
- Branching-, PR- und Release-Grundlagen für GitHub dokumentiert.
- Runner-, Proof- und Transporter-Logik als Vorbereitung für ein späteres Engagement entkoppelt.
- Managed-Profile-Reload-Baustein über Darwin-Notifications als Vorbereitung für das Engagement ergänzt.
- Ersten Engagement-Service mit Main Loop, Timer und Profil-Reload-Trigger eingeführt, ohne den One-shot-Runner zu entfernen.
- Report-only NotaryGUI als Dummy-Ausgabe ergänzt und impliziten GUI-Start für Console-Sessions vorbereitet.
- LaunchDaemon-Deployment auf `--engagement` mit internem Zyklusintervall umgestellt.
- NotaryGUI um strukturierte Reportansicht, Menüführung und Auto-Refresh auf Report-Änderungen erweitert.
- Managed-Config-Ableitung pro Lauf auf einen einzelnen Build reduziert, um doppelte Warnungen und unnötige Normalisierung zu vermeiden.
- Report-Karten in NotaryGUI für Runner- und Compliance-Werte auf Mehrzeilenanzeige mit sauberem Umbruch umgestellt.
- GUI-Report-Monitor bei Shutdown und Dateiersatz defensiver gemacht und Engagement-Lifecycle um Stop-/Cleanup-Geländer erweitert.
- Engagement um Signal-Handling für SIGTERM/SIGINT sowie optionales SIGHUP-Reload ergänzt; LaunchDaemon-Deployment mit `ExitTimeOut` gehärtet.
- CLI-Startpfad für `--engagement` auf lazy Config-Ladung umgestellt, damit Managed-Config-Warnungen beim Service-Start nicht doppelt entstehen.
- Shutdown-Härtung ergänzt: `SIGTERM`/`SIGINT` brechen laufende Engagement-Zyklen kooperativ ab und unterbinden danach Transport-, State- und Public-Report-Persistenz.
- Architektur-Merker für spätere Trennung in gemeinsamen `NotaryCore` plus getrennte GUI-/Service-Frontends dokumentiert.
- Benchmark-Matrix aus Schema, aktuellem Notary-Code und Jamf-/mSCP-Referenzskripten als Arbeitsgrundlage für `#5` ergänzt.
- Drei bestehende Schema-Checks vollständig verdrahtet: `DisableDiagnosticData`, `LimitAuditRecordsAccess` und `SetSudoTimeout`.
- `SetSudoTimeout` fachlich geschärft: Notary prüft und erzwingt jetzt den konfigurierten Minutenwert statt nur das Vorhandensein einer Sudo-Policy-Datei.
- Nächste Benchmark-Welle umgesetzt: `RetainInstallLog`, `DisableBluetoothSharing`, `DisableMediaSharing` und `DisableAirDrop` sind jetzt im Runner verdrahtet.
- Per-User-Prüfungen um `currentHost`-Defaults-Unterstützung erweitert, damit Bluetooth-Sharing zuverlässig im Benutzerkontext gelesen und erzwungen werden kann.
- Verbleibende Schema-Checks ergänzt: `DisableAdTracking`, `DisableSiri`, `ForceShowWifiStatus` und `EnableLibraryValidation` sind jetzt ebenfalls im Runner verdrahtet.
- Das aktuelle `Config-Schema-1.2.json` ist damit vollständig im Notary-Code abgebildet.
- Transport-Trigger gegen Timeout-Rauschen gehärtet: Timeout-Schwankungen bleiben im lokalen Proof sichtbar, lösen aber ohne echte Finding-/Compliance-Änderung kein Jamf-Update mehr aus.
- Deploy-Script schreibt `/var/db/notary.plist` jetzt atomisch und gelockt über macOS-Bordmittel statt über `defaults`, um sporadische Schreibfehler auf einzelnen Clients zu vermeiden und keine Command Line Tools vorauszusetzen.
- Deploy-Script ergänzt fehlende Jamf-Credentials jetzt gezielt aus vorhandener `notary.plist` und vermeidet beim State-Kopieren problematische `cp`-Metadatenpfade.
- Deploy-Script behandelt temporär blockierte oder verwaiste `notary.plist`-Locks robuster durch interne Retries und Stale-Lock-Bereinigung.
- Deploy-Script verwendet jetzt ein BSD-kompatibles `mktemp`-Template und räumt fehlerhafte Alt-Tempdateien in `/var/db` mit auf.
- GUI- und Icon-Richtung erstmals als Styleguide dokumentiert, inklusive moderner `Proof im Shield`-Referenz für ein Apple-nahes App-Icon.
- Packaging-Zielbild für `Notary.app` in `/Applications` plus separates Service-Binary unter `/usr/local/libexec` dokumentiert; Deploy-Script räumt den alten `/usr/local/sbin/notary`-Pfad als Legacy auf.
- Packaging auf sichtbare `Notary.app` plus Service-Binary unter `/usr/local/libexec/notary` umgestellt; Deploy-Script zeigt jetzt auf den neuen Service-Pfad.
- Report-GUI beim Beenden gehärtet, auf robustes Dateistempel-Refresh umgestellt und um About-Menü sowie Bundle-App-Icon ergänzt.
- Report-GUI zeigt jetzt zusätzlich die gestartete App-Version gegenüber der zuletzt beurkundeten Runner-Version; `Issues` und `Details` wurden vergrößert, und `About` ist direkt im Fenster erreichbar.
- Deploy-Script unterstützt jetzt `--ignorelocal` zum erzwungenen Neuaufbau von `/var/db/notary.plist` und fällt bei lokalen Leseproblemen automatisch auf eine frische State-Datei zurück.
- Source-Pfad in `Core`, `Service` und `UI` aufgeteilt.
- SwiftPM in echte Targets für `NotaryCore`, `notary` und `NotaryApp` getrennt; die sichtbare App läuft damit nicht länger als umbenanntes CLI-Binary im Bundle.
- Versions- und Schema-Generator auf paketfähige `Core`-Ausgabe umgestellt, damit generierte Dateien den Multi-Target-Build nicht zurückdrehen.
- Veraltetes `Config-Schema-f-Beta.json` aus dem aktiven Stand entfernt.
