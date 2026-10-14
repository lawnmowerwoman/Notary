# Roadmap

Diese Roadmap bündelt die aktuell bekannten Themen für Notary in einer Reihenfolge, die Architektur, Produktreife und Delivery sinnvoll zusammenführt. Sie dient als Arbeitsgrundlage für GitHub-Issues, Releases und spätere Meilensteine.

## Aktueller Stand

Bereits umgesetzt oder als Basis vorhanden:

- Wiederverwendung des Jamf-API-Tokens mit Refresh erst bei Ablauf
- Transport-Updates nur noch bei Änderungen der Findings
- Heartbeat des Transporters nur noch alle 60 Minuten
- GitHub-Repository, Versionsbasis und initiale Projektdokumentation

## Nächste Schwerpunkte

### 2.1 Stabilitäts- und Sichtbarkeitsrelease

- `Menu-Bar Status`
  Ziel: Notary sitzt als StatusItem in der macOS-Menüleiste und zeigt den lokalen Zustand unmittelbar als Ampelstatus.
  Release-Merker:
  Vor dem 2.1-Release soll der Klick auf das Shield ohne Detailwissen verständlich machen, ob das Gerät `OK`, `Achtung` oder `Fail` ist. Das geschlossene Menüleisten-Icon bleibt bewusst leise und systemkonform; Farbe und klare Sprache erscheinen erst in der geöffneten Statusfläche. Die Darstellung orientiert sich bewusst an etablierten Security-Statusmustern wie Jamf Trust, bleibt aber in Notary-Sprache: Shield, ruhiger Grundzustand, klare Statusfarbe nach Interaktion und kurzer Text.

- `Report GUI Polish`
  Issue: `#3`
  Ziel: Die lokale Report-Ansicht grafischer und schneller erfassbar machen.
  Release-Merker:
  2.1 soll ein Eye-Candy-Release werden, ohne die Admin-Nutzbarkeit zu verlieren: Compliance-Kachel, Key Indicators, Findings-Gruppen und klare Statusfarben statt reiner Textflächen.

- `Configurator hardening`
  Issue: `#6`
  Ziel: Den Configurator als praktische Admin-Oberfläche für bestehende und neue Notary-Konfigurationen stabilisieren.
  Release-Merker:
  Der Import aus `/Library/Managed Preferences`, mobileconfig-Import/-Export und die neue Startabfrage müssen vor der Beta gezielt getestet werden.

- `Access policy for local UI surfaces`
  Ziel: Report, Configurator und Jamf Reporter erhalten ein gemeinsames Rechte-/Policy-Modell.
  Release-Merker:
  Die Jamf-API ist zu mächtig für einfache lokale Annahmen. Ein Config-Passwort ist ausdrücklich keine Zielarchitektur. Für 2.1 muss geklärt werden, welche lokalen Benutzer welche UI-Flächen öffnen dürfen und wie eine spätere IAM-Lösung eingebunden wird.

### 2.2 Licensing, Telemetrie und Stabilität

Release-Entscheidung vom 2026-10-14:
Version 2.2 wird als finales Release ohne Kanalbuchstaben veröffentlicht.
Seit dem Rollout von 1C44k wurden auf den gemeldeten Testgeräten und Build Agents
keine erneuten Cocoa-257-State-Zugriffsfehler beobachtet; weitere Beobachtung bleibt
sinnvoll. Security-Agent-Timeouts bleiben ein separater bekannter Stabilitätspunkt
mit unverändertem, maximal einstündigem Last-PASS-Fallback.
Die eigenständige Reporter-/Configurator-Lösung und der Token Escrow Service
(Jamf Token Broker) sind ausdrücklich keine Release-Voraussetzung für 2.2,
sondern werden mit 2.3 weiterentwickelt. Bestehende Funktionen bleiben verfügbar.

- `Menu-Bar Verlaufsgrafiken`
  Ziel: Das Menubar-Element soll Netzwerk- und CPU-Auslastung als kompakten Verlauf über die letzten drei Minuten darstellen.
  Release-Merker:
  Die Darstellung muss klein, ruhig und schnell erfassbar bleiben. Sie ist Observability, nicht Compliance-Entscheidung.

- `Licensing Check-in`
  Ziel: Geräte sollen mit Activation Code und Machine Identifier beim Ministry Licensing Service einchecken können.
  Release-Merker:
  Konfigurationsprofile können den Activation Code bereits enthalten. Der Activation Code identifiziert den Kunden, die Machine Identifier messen Nutzung; daraus darf in 2.2 noch keine lokale harte Lizenzentscheidung entstehen.

- `Licensing Admin-Tool`
  Ziel: Ein kleines Tool soll die aktiven Activation Codes und die Zahl der eingecheckten Rechner vom Licensing Service abrufen können.
  Architektur-Merker:
  Offen ist, ob dies zunächst als Shell-freundliche API-Nutzung, kleines Swift-CLI oder beides umgesetzt wird.

- `XProtect macOS 27.2`
  Ziel: Das XProtect-Verhalten ist erneut bewertet, weil `xprotect check` unter macOS 27.2 wieder verwertbare Ergebnisse liefert.
  Beobachtung vom 2026-10-07:
  `xprotect check` meldet wieder Current Update mit Datum und Version, `xprotect status` zeigt Launch- und Background-Scans als enabled, und `xprotect version` liefert Version `5366`.
  Release-Merker:
  Die 2.1-Logik übersprang XProtect unter macOS 27 und neuer wegen `XProtectUpdateError Code=11`. Für 2.2 ist daraus eine präzisere Versionsentscheidung geworden: Skip nur für betroffene 27.0/27.1-Builds und reguläre Prüfung ab 27.2.

### 2.3 Licensing Deployment, Admin-App und Token Escrow

- `Licensing Server Import API`
  Ziel: Der Licensing Service soll per API mit neuen Activation Codes beziehungsweise Token-Deployment-Daten bespielt werden können.
  Architektur-Merker:
  Der Licensing Service stellt inzwischen gerätebezogene App Token selbst aus. Signing Keys bleiben ausschließlich auf der autorisierten Hersteller-/Serverseite; Clients erhalten nur signierte Token. Offline erzeugte Deployment-Artefakte bleiben ein eigener Importpfad.

- `Notary Reporter App`
  Ziel: Die Reporter-Schnittstelle für Jamf Pro soll zur eigenständigen Flottenübersicht vorbereitet werden, wie in den Demo-Grafiken gezeigt.
  Produkt-Merker:
  Der heutige Report in der Notary App ist Übergangslösung. Perspektivisch soll er durch die Notary Reporter App ersetzt werden.

- `Eigenständige Notary Admin Beta`
  Planungsentscheidung vom 2026-10-11:
  Reporter und Configurator parallel zu v2.2 als eigenständige Notary Admin App für die v2.3-Beta vorbereiten. Vorhandene Module wiederverwenden, statt Report- und Konfigurationslogik zu duplizieren. Der Reporter darf in dieser App nicht vom lokalen Runner-State oder dessen Transport-Credentials abhängen.
  Arbeitsversion und Feature Freeze:
  Seit 2026-10-11 liegt die eigenständige Arbeitsversion unter `../Ministry/Notary Admin`. Der Launcher öffnet die übernommenen Reporter- und Configurator-Oberflächen direkt. Die ursprünglichen Notary-Implementierungen sind ab sofort feature-frozen, deprecated und marked for removal; neue Funktionen werden ausschließlich in der Admin-App entwickelt. Notwendige Sicherheits-/Kompatibilitätskorrekturen bleiben möglich. Dies ist noch kein Entfernen aus Notary und kein öffentlicher Beta-Release.
  Versionierung:
  Eigenständige Produktversion 1.0 mit geklontem Notary-Build-Schema und unabhängigem Zähler. Start bei 0A1z (Major-Index 0, Minor A, Build 1, Kanal z); keine v0-Produktversion. Die geplante Bereitstellung zur Notary-2.3-Beta ist eine Release-Zuordnung, keine gemeinsame Versionsnummer.
  Entwicklungsmodus:
  Ausschließlich auf Steffis Entwicklungs-Mac mit explizit hinterlegter URL, Client ID und Client Secret ihres eigenen Jamf Servers arbeiten. Zugangsdaten im Keychain speichern, nicht im Quellcode, in Plists oder Logs. Dieser lokale Zugang ist ein interner Entwicklungsweg, keine öffentliche Umgehung der Reporter-Autorisierung. Lesender Report-Zugriff erhält keine Setup-/Konfigurations-Schreibrechte.
  Broker-Ziel:
  Den Licensing Token Broker parallel entwickeln und später lokal im vollständigen Ablauf testen. Lokalen Credential-Zugang und Broker-Zugang am Authentifizierungsübergang trennen, ohne doppelte Reportlogik. Der Broker bleibt der vorgesehene Zugangsweg der veröffentlichten Reporter-Lösung; seine Autorisierung ist vor Freigabe nachzuweisen.
  Umfang der ersten Beta:
  Reporter-Flottenansicht und vorhandenen Configurator mit Import/Export übernehmen. Vollständiges Jamf-Setup und direkte Veröffentlichung von Benchmark-Profilen bleiben v3-Ziele. Die Licensing-Admin-Backup-Funktion ist weiterhin Voraussetzung für die Reporter-Bereitstellung.
  Release-Gate:
  Aktualisiert am 2026-10-14: Notary 2.2 wird unabhängig von der Admin-Beta veröffentlicht. Reporter und Configurator bleiben in Notary 2.2 verfügbar und feature-frozen. Ihre Auslagerung und der Token Escrow Service werden für 2.3 vorbereitet; Entfernung erst bei verfügbarer, ausreichend getesteter eigenständiger Lösung und geprüftem Übergang. Broker-Autorisierung und Licensing-Admin-Backup einschließlich Restore-Test bleiben Voraussetzungen für die öffentliche Reporter-Bereitstellung.

- `Token Escrow Service / Jamf Token Broker`
  Ziel für 2.3: Kundenbezogene Reporter-Autorisierung und Ausgabe kurzlebiger Jamf Access Tokens durch den Licensing Service. Dauerhafte Jamf Credentials bleiben verschlüsselt auf dem Server; Reporter-Clients erhalten ausschließlich den zeitlich begrenzten Access Token. Das detaillierte Sicherheitsmodell unter 3.0 beschreibt die auch für die 2.3-Beta geltenden Anforderungen, keine Verschiebung ihrer Umsetzung auf 3.0.
  Release-Gate:
  Ohne serverseitig geprüfte Bestätigung der Kundenermächtigung nimmt die API weder Jamf Client ID noch Client Secret an. Autorisierung, Rotation/Widerruf, Mandantentrennung und tatsächliche Token-Laufzeit müssen vor öffentlicher Bereitstellung getestet sein. Keine Credentials oder Bearer Tokens in Logs; lesender Reporter-Zugang berechtigt nicht zu Setup-/Konfigurationsänderungen.

- `Licensing Admin Backup als Reporter-Release-Voraussetzung`
  Ziel: Zeitgleich mit Bereitstellung der Reporter-App in v2.3 muss der Ministry Licensing Admin einen vollständigen SQLite-Dump vom Licensing Service abrufen und lokal am gewählten Speicherort ablegen können.
  Architektur-Merker:
  Der Service erzeugt einen konsistenten Snapshot der laufenden Datenbank und daraus den Dump; keine einfache Kopie der geöffneten DB-Datei. Der Export ist ausschließlich über einen autorisierten Hersteller-Admin-Zugang verfügbar, niemals über den kundenbezogenen Reporter-Bearer. Download atomar speichern und erst nach vollständigem, geprüftem Export als erfolgreich melden.
  Sicherheits-/Recovery-Merker:
  Der Dump enthält sensible Kunden-, Lizenz-, Geräte- und gegebenenfalls verschlüsselte Zugangsdaten und Token; geschützte lokale Ablage, keine Inhalte in Logs. Signing Keys, Verschlüsselungsschlüssel und Server-Konfiguration sind nicht Teil des Datenbank-Dumps und benötigen eine getrennte sichere Sicherung. Vor Reporter-Freigabe die Wiederherstellung in einer isolierten Testumgebung einschließlich Lizenzrevisionen, gerätebezogener Token und Check-ins prüfen; bei verschlüsselten Credentials auch die Wiederherstellbarkeit mit dem separat gesicherten Schlüssel nachweisen.
  Nicht-Ziele:
  Keine automatische Sicherung privater Schlüssel im Dump und noch keine HA-/Replikationslösung. Bestehende Backups werden nicht automatisch überschrieben.

### 3.0 Notary Admin: Reporter, Configurator und Jamf-Setup

Planungsstand: 2026-10-11. Diese Punkte sind Zielarchitektur, noch keine implementierten Funktionen.

- `Gemeinsame Notary Admin App`
  Ziel: Reporter und Configurator in einer kundenbezogenen Admin-App zusammenführen. Der Ministry Licensing Admin bleibt das getrennte Herstellerwerkzeug zur Lizenzverwaltung.
  Produkt-Merker:
  Die lokale Notary App verliert perspektivisch die administrativen Report-/Config-Flächen; lokale Compliance-Auswertung, Statusanzeige und Offline-Lizenzprüfung bleiben unabhängig davon.

- `Kundenbezogener Reporter-Zugang und Jamf Token Broker`
  Ziel: Pro Activation Code einen separaten, rotierbaren und sperrbaren Reporter-Bearer vorsehen. Bestehende Lizenzen werden ergänzt; neue Lizenzen erhalten ihn bei Erstellung. Der Activation Code selbst ist keine Zugriffsberechtigung.
  Sicherheits-Merker:
  Bearer nur einmal anzeigen und serverseitig als Hash speichern. Jamf-URL, Client ID und verschlüsseltes Client Secret dürfen erst nach serverseitig geprüfter Bestätigung "AV mit Kunden liegt vor" gespeichert werden. Bestätigung mit Zeitpunkt und Administrator dokumentieren; sie ersetzt weder den tatsächlichen Vertrag noch die technische Zugriffsfreigabe. Verschlüsselungsschlüssel getrennt von Datenbank und Signing Keys halten; keine Secrets in Logs oder normalen Lizenzantworten.
  Ablauf:
  Die Admin-App fragt nach Licensing-Server-URL und Reporter-Bearer, mit optionaler Keychain-Speicherung. Vor jedem Report-Reload prüft der Licensing Service Zugang, Mandant und Reporter-Berechtigung erneut und holt mit den hinterlegten Credentials einen kurzlebigen Jamf Access Token. Nur Jamf-URL und Access Token gelangen zum Client; das dauerhafte Client Secret bleibt auf dem Server. Compliance-Attribute werden direkt aus Jamf geladen, nicht auf dem Licensing Service gespeichert. Notary Last Contact wird zur Erkennbarkeit veralteter Meldungen berücksichtigt.
  Lifetime-Merker:
  Zielwert zunächst 120 Sekunden, am Jamf API Client konfiguriert und im Integrationstest zu bestätigen. Die tatsächlich von Jamf gelieferte Gültigkeit ist maßgeblich. Bei Ablauf während paginierter/großer Berichte wird erneut über den Licensing Service autorisiert; kein unvollständiger Bericht darf als vollständig erscheinen. Sperrung verhindert neue Token-Ausgaben, macht bereits ausgegebene Jamf Access Tokens aber nicht automatisch ungültig. Bereits geladene Daten werden durch Ablauf nicht zurückgerufen.

- `Notary-Setup und Extension Attributes über die Admin-App`
  Ziel: Einrichtung in Jamf einschließlich Erzeugung und Aktualisierung der benötigten Notary Extension Attributes in die Admin-App verlagern.
  Migrations-Merker:
  Wiederholbares Setup ohne doppelte EAs; bestehende Attributwerte und IDs erhalten. Erst mit verfügbarer und getesteter Ablösung entfällt die EA-Funktion aus dem Deploy-Script. Das bisherige Deployment bleibt bis dahin unverändert nutzbar.

- `Benchmark-Konfiguration direkt in Jamf veröffentlichen`
  Ziel: Änderungen aus der Configurator-Oberfläche per Jamf API im zugeordneten Konfigurationsprofil hinterlegen, ohne manuellen .mobileconfig-Upload.
  Sicherheits-Merker:
  Report-Lesen und Setup-/Konfigurations-Schreiben sind getrennte Berechtigungen mit separaten, minimal privilegierten Jamf API Clients. Ein Reporter-Bearer berechtigt nicht automatisch zu Änderungen. Vor Veröffentlichung Änderungen und Ziel-Scope bestätigen; fremde Profile und Payloads nicht überschreiben. Änderungen nachvollziehbar protokollieren und einen Rückweg zur vorherigen Konfiguration vorsehen.

Jamf-Grundlagen: [Client Credentials](https://developer.jamf.com/jamf-pro/docs/client-credentials), [API Client und Access Token Lifetime](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Creating_an_API_Client).

### Architektur und Laufzeit

- `MDM Status watch`
  Issue: `#1`
  Ziel: MDM-Erreichbarkeit, Enrollment- oder Policy-Status sichtbar machen und in Findings/Proof einfließen lassen.

- `Instant Compliance monitoring for Admins`
  Issue: `#2`
  Ziel: Lokalen Admins eine Jamf-basierte Reporter-Ansicht auf Geräte, letzte Notary-Transporte, Proof-Werte und gruppierte Issues geben.
  Release-Merker:
  Der aktuelle Beta-Stand darf die vorhandenen Jamf-API-Credentials lesend verwenden. Vor dem öffentlichen Release braucht der Reporter aber eine zusätzliche Konfiguration, ob lokale Admins diese mandantenweite Geräteansicht öffnen dürfen.

- `Strict sections in code for Notary Engagement/Runner, Proof, Transporter`
  Issue: `#4`
  Ziel: Den Code klar nach Verantwortungsbereichen strukturieren und langfristig wartbarer machen.
  Architektur-Merker:
  Der aktuelle Stand darf vorerst in einem Binary bleiben. Langfristig ist aber ein gemeinsamer `NotaryCore` mit getrennten Frontends für `NotaryGUI`, `NotaryService`/`Engagement` und optional `NotaryCLI` die bevorzugte Zielrichtung. Der Daemon soll dabei die schreibende Instanz und Quelle der Wahrheit bleiben, während die GUI primär lesend und beobachtend arbeitet.

- `LaunchDaemon with main loop`
  Issue: `#8`
  Ziel: Notary als dauerhaft laufenden Dienst ausführen, damit Checks nicht nur pro Einzelstart stattfinden.

### Compliance und Checks

- `Further CIS benchmarks`
  Issue: `#5`
  Ziel: Die bestehende Check-Abdeckung gezielt erweitern.
  Release-Merker:
  Neue Benchmark-Wellen sind für 2.2 vorgesehen. 2.1 priorisiert Stabilität, UI-Status, Rechteklärung und Feldtauglichkeit.

- `System uptime / last reboot monitoring`
  Issue: `#7`
  Ziel: Uptime und letzten Reboot überwachen und optional Warnungen ausgeben, wenn Schwellenwerte überschritten werden.

## Geparkte Themen

Aktuell keine GUI-Themen mehr geparkt: Report, Configurator und Menu-Bar-Status sind aktive 2.1-Themen.

## Vorschlag für Abarbeitung

1. 2.1 als Stabilitäts- und Sichtbarkeitsrelease fertigstellen.
2. Rechte-/IAM-Modell für lokale UI-Flächen klären.
3. Menu-Bar-Ampelstatus und grafischere Reports vor der Beta abrunden.
4. Configurator-Import/-Export und Engagement-Laufzeit im Feld testen.
5. Neue Benchmark-Wellen für 2.2 planen.

## In GitHub abbilden

Jeder Punkt dieser Roadmap sollte als eigenes GitHub-Issue gepflegt werden. So können wir:

- Fortschritt sichtbar verfolgen
- Prioritäten sauber justieren
- spätere Releases und Milestones daran ausrichten
