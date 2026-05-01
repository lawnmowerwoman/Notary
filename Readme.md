![Notary App Icon](Dokumentation/Notary-App-Icon-Concept.svg)

# Notary

Notary ist ein macOS-Compliance- und Hardening-Projekt mit Fokus auf lokale Prüfungen, strukturierte Findings und Jamf-orientierten Ergebnistransport. Die aktuelle Implementierung ist ein Swift-basierter Runner mit optionaler Remediation und einem Transporter, der Ergebnisse nur bei Änderungen oder im Heartbeat-Intervall weiterreicht.

## Aktueller Ist-Zustand

Heute sind diese Kernelemente real vorhanden:

- Swift-CLI `notary` als eigentlicher Prüflauf
- sichtbare `Notary.app` als lokaler GUI-Einstiegspunkt
- Persistenter Zustand in `/var/db/notary.plist`
- Jamf-Transport über Extension Attributes
- Token-Reuse für das Jamf-API-Token bis zum Ablauf
- Update-on-change für Findings und Compliance-Zustand
- Heartbeat für den Transporter nur alle 60 Minuten
- `Engagement` als laufender Main-Loop-Service über LaunchDaemon
- Report-only GUI für lokale Einsicht in Findings und Transportzustand

## Runner vs. Engagement

Die Begriffstrennung ist wichtig:

- `Runner`
  Der Runner ist der einzelne Prüfzyklus. Er lädt Konfiguration und Zustand, führt die Checks aus, berechnet Proof und Transportdaten und liefert einen abgeschlossenen Lauf zurück.

- `Engagement`
  Das Engagement ist das heutige Service-Laufzeitmodell. Es hält Timer, Profil-Reloads, Signal-Handling und wiederkehrende Runner-Zyklen zusammen.

Aktuell existieren im Produkt beide Ebenen:

- `Runner` für One-shot-Läufe
- `Engagement` für den dauerhaften Hintergrundbetrieb

## Laufzeitmodell heute

Der aktuelle Ablauf im Service-Modell ist:

1. Start des `Engagement` über LaunchDaemon oder eines einzelnen Runner-Laufs über CLI.
2. Laden von Konfiguration und gespeichertem Zustand aus der Plist.
3. Ausführen der konfigurierten Checks.
4. Erzeugen von Proof-Daten und Transportwerten.
5. Optionales Jamf-Update, aber nur wenn sich Findings geändert haben oder der Heartbeat fällig ist.
6. Schreiben des aktualisierten Zustands.
7. Im `Engagement` folgt danach der nächste Zyklus über Timer oder Reload-Trigger.

Wichtig dabei:

- Der Heartbeat des Transporters beträgt aktuell `60 Minuten`.
- Die Werte `Notary Runner`, `Notary Issues` und `Notary Compliance` werden in `/var/db/notary.plist` abgelegt.
- Der Heartbeat-Timer wird nur nach erfolgreichem Schreiben der Transportdaten zurückgesetzt.

## Transporter-Verhalten

Der Transporter verwendet heute folgende Regeln:

- Ergebnisse werden mit dem zuletzt transportierten Stand verglichen.
- Ein Jamf-Update erfolgt nur bei Änderungen an Status, Findings oder Compliance-Wert.
- Falls keine Änderung vorliegt, wird frühestens nach 60 Minuten ein Heartbeat geschrieben.
- Das Jamf-Bearer-Token wird in der Plist wiederverwendet und erst bei Ablauf oder nach einem `401` erneuert.
- Die EA-Definitionen werden gecacht und mit Cooldown aktualisiert, um unnötige API-Last zu vermeiden.

## Persistenz

Der zentrale Speicherort ist:

- `/var/db/notary.plist` bei `root`

Für Entwicklungs- oder Nicht-Root-Läufe verwendet der `SecurePlistStore` eine Fallback-Datei unter `/tmp`, damit das Verhalten lokal testbar bleibt.

In der Plist liegen heute unter anderem:

- Jamf-Client-ID und Client-Secret
- zuletzt verwendetes Bearer-Token samt Ablaufzeit
- gecachte EA-Definitionen
- Zeitstempel des letzten erfolgreichen Transports
- zuletzt transportierte Werte für Runner, Issues und Compliance

## Konfiguration

Der Runner liest seine Managed-Preferences standardmäßig aus der Domain:

- `de.twocent.notary`

Hilfreiche CLI-Optionen:

- `--dump-config`
  Zeigt den rohen effektiven Managed-Prefs-Snapshot.

- `--dump-resolved`
  Zeigt zusätzlich die aufgelösten Pentabool-Werte und normalisierte Parameter.

- `-v` oder `--verbose`
  Aktiviert erweitertes Logging.

- `--develop`
  Aktiviert das ausführlichste Logging.

## Deployment und LaunchDaemon

`Tools/deploy.sh` richtet das heutige Betriebsmodell aus:

- schreibt oder aktualisiert `/var/db/notary.plist`
- hinterlegt Jamf-Zugangsdaten und Flags
- richtet einen LaunchDaemon für `--engagement` ein
- setzt `KeepAlive` und `ExitTimeOut=15`
- startet das Service-Binary unter `/usr/local/libexec/notary` mit `--engagement --engagement-interval <sekunden>`

Wichtige Eigenschaften des heutigen Deploy-Pfads:

- bestehende Jamf-Credentials in `/var/db/notary.plist` werden bei Updates weiterverwendet
- die Plist wird atomisch über Temp-Datei und finalen Austausch aktualisiert
- temporär blockierte Locks werden intern erneut versucht
- verwaiste Lock-Verzeichnisse werden nach kurzer Altersschwelle bereinigt
- für den Schreibpfad werden nur macOS-Bordmittel verwendet, keine Command Line Tools

### Deploy Troubleshooting

Wenn ein Client beim Deployment auffällig wird, lohnt sich zuerst der Blick auf diese typischen Ursachen:

- `Could not write domain /var/db/notary.plist`
  Früherer `defaults`-Schreibpfad. Der aktuelle Stand von `Tools/deploy.sh` vermeidet diesen Fehler durch atomisches Schreiben ohne `defaults`.

- `xcode-select: error: No developer tools were found`
  Hinweis auf einen veralteten Deploy-Script-Stand, der noch `python3` voraussetzt. Der aktuelle Stand verwendet keine Entwicklerwerkzeuge.

- `could not acquire plist lock for /var/db/notary.plist`
  Kurzzeitige Kollision zwischen Deployment und laufendem Service. Der aktuelle Deploy-Pfad enthält interne Retries und Stale-Lock-Bereinigung. Bleibt der Fehler bestehen, sollte geprüft werden, ob auf dem Client ältere Script-Versionen oder manuelle Eingriffe Locks hinterlassen.

- `mktemp ... File exists`
  Hinweis auf einen älteren Deploy-Script-Stand mit nicht BSD-kompatiblem Template. Der aktuelle Stand bereinigt fehlerhafte Alt-Tempdateien und verwendet ein macOS-kompatibles `mktemp`-Pattern.

Für Jamf-Policies ist deshalb wichtig:

- `Tools/deploy.sh` immer zusammen mit dem aktuellen PKG-Stand aktualisieren
- auf die im Script ausgegebene Deploy-Version achten, z. B. `Deploy Notary – v2.1.0`
- bei Supportfällen Deploy-Version, Build-Label und den relevanten Ausschnitt aus dem Policy-Log gemeinsam betrachten

## Jamf API Voraussetzungen

Für den API-basierten Transport muss in Jamf Pro ein API Client mit folgenden Rechten vorhanden sein:

- `Update Computer Extension Attributes`
- `Update Computers`
- `Read Computers`
- `Read Computer Extension Attributes`
- `Create Computer Extension Attributes`

Zusätzlich muss für diesen API Client eine Token-Lebensdauer von `86400` Sekunden gesetzt werden.

Wichtig für Beta-Tester:

- Wenn bereits ein bestehender Notary-API-Client verwendet wird, sollte die Token-Lebensdauer aktiv auf `86400` angepasst werden.
- Notary kann das Token lokal wiederverwenden, aber nur innerhalb der von Jamf erlaubten Laufzeit.
- Zu kurze Token-Laufzeiten erzeugen unnötige OAuth-Erneuerungen und verschlechtern genau das Verhalten, das mit dem Token-Reuse reduziert werden soll.

## Projektstruktur

- `Sources/NotaryRunner`
  Runner, Checks, Jamf-Transport, Persistenz und Logging

  Wichtige Unterteilung im aktuellen Source-Pfad:
  `Core` für gemeinsame Fachlogik, `Service` für Runner/Engagement-Einstiege und `UI` für die lokale App-Oberfläche

- `Tools`
  Hilfsskripte für Deployment, Versionierung und Schema-Generierung

- `.version`
  Steuerdateien für Marketing-Version, Build-Label und Release-Kanal

- `Dokumentation`
  Arbeitsnotizen, Legacy-Material und Referenzen

- `.github`
  Issue-Templates und GitHub-Projektstruktur

## Design und GUI

Die visuelle Richtung für Notary ist aktuell in zwei Referenzen festgehalten:

- [Design-Styleguide](/Users/steffi/Coding/Notary/Dokumentation/Design-Styleguide.md)
- [App-Icon-Konzept](/Users/steffi/Coding/Notary/Dokumentation/Notary-App-Icon-Concept.svg)
- [Packaging-Plan](/Users/steffi/Coding/Notary/Dokumentation/Packaging-Plan.md)

Diese Dateien definieren den derzeit bekannten Zielcharakter für GUI, Materialität, Informationshierarchie und das Motiv `Proof im Shield`.

## Architektur-Merker

Die Zielarchitektur ist jetzt nicht mehr nur vorgemerkt, sondern im Build angelegt:

- ein gemeinsamer `NotaryCore` für Checks, Proof, Transport, State und Konfiguration
- ein GUI-Frontend für Report und späteren Configurator
- ein separates Service-/Daemon-Frontend für `Engagement`
- optional ein eigenständiges `NotaryCLI` für Debug, Admin und Automatisierung

Wichtig für diese Trennung:

- Der Daemon bleibt die schreibende Instanz und operative Quelle der Wahrheit.
- Die GUI startet keinen zweiten Engagement-Lauf, sondern liest, beobachtet und erklärt den vorhandenen Zustand.
- Zwei Prozesse mit gemeinsamem Core sind langfristig bevorzugt gegenüber einer dauerhaft gemischten GUI-/Daemon-Instanz desselben Laufzeitprozesses.
- Das SwiftPM-Paket baut jetzt getrennte Frontends für `NotaryApp` und `notary`, die sich denselben `NotaryCore` teilen.

## Build und Packaging

Die wichtigsten Targets liegen im `Makefile`.

```sh
make build
make release
make staple
```

`make build` erzeugt vor dem Swift-Build die Laufzeit-Version aus den Dateien unter `.version`.

Der aktuelle Packaging-Zuschnitt ist:

- `Notary.app` nach `/Applications`
- Service-Binary `notary` nach `/usr/local/libexec`
- LaunchDaemon über `Tools/deploy.sh`

## Versionierung

Notary verwendet aktuell ein zweistufiges Versionsmodell:

- Marketing-Version: numerisch, z. B. `2.0`
- Build-Label: intern, z. B. `1A148f`

Die Werte werden aus folgenden Dateien abgeleitet:

- `.version/major_index`
- `.version/minor_letter`
- `.version/channel`
- `.version/build_number`

`Tools/gen_version.sh` erzeugt daraus:

- `Sources/NotaryRunner/Version.generated.swift`
- `.version/version.mk`

Die generierten Dateien sind bewusst nicht für Git vorgesehen. Damit bleibt das Repository stabil, während lokale Builds weiterhin ihre Build-Nummer fortschreiben können.

### Release-Kanäle

Der Kanal in `.version/channel` beschreibt die Reife eines Builds:

- `c`
  Letzter Feature-Kanal. Hier dürfen neue Funktionen noch aufgenommen werden.
- `b`
  Stabilisierungskanal. Ab hier werden nur noch Bugfixes, Zuverlässigkeits-, Sicherheits- und Packaging-Verbesserungen aufgenommen.
- `a`
  Release-Candidate-Kanal. Keine neuen Features mehr, nur noch Go/No-Go-Fixes.
- ohne Kanal-Suffix
  Finaler Release / Golden Master.

Praktische Merkregel:

- je höher der Buchstabe, desto weiter ist der Build vom finalen Release entfernt
- je niedriger der Buchstabe, desto näher ist der Build am finalen Release

Für Notary `2.0` gilt aktuell bewusst:

- `c`-Builds sind die letzten Builds mit neuem Funktionsumfang
- `b`-Builds dienen nur noch der Steigerung von Stabilität, Zuverlässigkeit und Sicherheit
- `a`-Builds sind Release Candidates

Hinweis:
Die interne Laufzeitversion wird aktuell aus `NotaryVersion` abgeleitet. Die `ArgumentParser`-Metadaten im CLI sollten künftig noch an das gleiche Modell angeglichen werden, damit keine sichtbaren Versionsunterschiede mehr entstehen.

## GitHub und Releases

Das Repository ist live unter:

- [lawnmowerwoman/Notary](https://github.com/lawnmowerwoman/Notary)

Aktueller Startpunkt:

- Default-Branch: `main`
- Initialer Versions-Tag: `v2.0.0`

Empfohlene Tag-Namenskonvention für künftige Releases:

- `v2.0.0`
- `v2.1.0`
- `v2.1.1`

Das interne Build-Label bleibt davon unabhängig und eignet sich weiter für Jamf, Logs und Supportfälle.

Für den praktischen Workflow im Repository:

- Branching und Beitragsablauf: [CONTRIBUTING.md](/Users/steffi/Coding/Notary/CONTRIBUTING.md)
- Release-Ablauf: [RELEASE.md](/Users/steffi/Coding/Notary/RELEASE.md)

## TCC / Full Disk Access

Einige Remediation-Schritte verwenden Apple-Systemwerkzeuge wie `systemsetup`. Auf aktuellen macOS-Versionen können diese Aktionen selbst als `root` durch TCC blockiert werden, wenn dem Runner oder dem aufrufenden Management-Prozess kein Full Disk Access gewährt wurde.

Beispiel:

```text
Turning Remote Login on or off requires Full Disk Access privileges.
```

## Empfehlung für den Produktivbetrieb

Ein PPPC-Profil sollte Full Disk Access für den Notary Runner oder den verwendeten Management-Agent bereitstellen, damit Remediation deterministisch und reproduzierbar funktioniert.

## Fallback-Verhalten

Wenn `systemsetup` durch TCC blockiert wird, kann der Runner abhängig von der Konfiguration den betroffenen Dienst best effort stoppen, z. B. per `launchctl bootout` für `sshd`.

Dieser Fallback ist nicht in jedem Fall persistent und dient als Sicherheitsnetz, falls PPPC fehlt oder fehlerhaft ist. Nach jeder Remediation wird der Zustand verifiziert. Bleibt der Zustand unklar oder schlägt die Verifikation fehl, wird das Ergebnis als `FAIL` gewertet.
