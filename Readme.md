![Notary App Icon](Dokumentation/Notary-App-Icon-Concept.svg)

# Notary

Notary ist ein macOS-Compliance- und Hardening-Projekt mit Fokus auf lokale Prüfungen, strukturierte Findings und eine klare Trennung zwischen öffentlichem Kern und optionalen vertraulichen Integrationen. Die aktuelle Implementierung ist ein Swift-basierter Runner mit Menüleisten-Begleiter, lokaler Report-App und einer stabilen Transport-Schnittstelle.

## Aktueller Ist-Zustand

Heute sind diese Kernelemente real vorhanden:

- Swift-CLI `notary` als eigentlicher Prüflauf
- sichtbare `Notary.app` als lokaler GUI-Einstiegspunkt
- Persistenter Zustand in `/var/db/notary.plist`
- öffentlicher Dummy-Transporter ohne Netzwerkzugriff
- optionaler vertraulicher Transporter in autorisierten Ministry-Builds
- AppToken-Capability-Gate für optionale Integrationen
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
5. Optionaler Transport über die stabile Transport-Schnittstelle, sofern die Build-Variante und das App Token dies erlauben.
6. Schreiben des aktualisierten Zustands.
7. Im `Engagement` folgt danach der nächste Zyklus über Timer oder Reload-Trigger.

Wichtig dabei:

- Die Werte `Notary Runner`, `Notary Issues` und `Notary Compliance` werden in `/var/db/notary.plist` abgelegt.
- Public Builds führen keinen Remote-Transport aus.

## Transporter-Verhalten

Notary verwendet eine produktinterne Transport-Schnittstelle. Diese Schnittstelle ist Teil des öffentlichen Kerns; die echte Transport-Implementierung ist es nicht.

- Public Builds enthalten einen Dummy-Transporter.
- Der Dummy führt keine Netzwerkzugriffe aus.
- Der Dummy verarbeitet keine Credentials.
- Der Dummy meldet eindeutig `implementationUnavailable`.
- Confidential Ministry Builds können eine echte Implementierung aus `Sources.local/` einbinden.
- Auch Confidential Builds transportieren nur, wenn das App Token die Capability `transporter` freigibt.

## Persistenz

Der zentrale Speicherort ist:

- `/var/db/notary.plist` bei `root`

Für Entwicklungs- oder Nicht-Root-Läufe verwendet der `SecurePlistStore` eine Fallback-Datei unter `/tmp`, damit das Verhalten lokal testbar bleibt.

In der Plist liegen heute unter anderem:

- Zeitstempel des letzten erfolgreichen Transports
- zuletzt transportierte Werte für Runner, Issues und Compliance
- optionaler lokaler Betriebszustand für autorisierte vertrauliche Integrationen

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

Public Builds liefern die App, den Runner, die Menüleisten-Komponente und die lokale Report-Funktionalität. Ministry-spezifische Deployment- und Bootstrap-Skripte liegen nicht im öffentlichen Repository.

Autorisierte Ministry-Setups halten vertrauliche Deployment-Helfer unter:

```text
Sources.local/Deployment/
```

Diese Dateien dürfen nicht in öffentliche Source-Archive oder öffentliche Release-Anhänge gelangen.

## Projektstruktur

- `Sources/NotaryRunner`
  Runner, Checks, Transport-Vertrag, Persistenz und Logging

  Wichtige Unterteilung im aktuellen Source-Pfad:
  `Core` für gemeinsame Fachlogik, `Service` für Runner/Engagement-Einstiege und `UI` für die lokale App-Oberfläche

- `Tools`
  öffentliche Hilfsskripte für Versionierung, Schema-Generierung und Build-Artefakte

- `Sources.local`
  lokaler, ignorierter Bereich für vertrauliche Ministry-Quellen; nicht Bestandteil des öffentlichen Repositorys

- `.version`
  Steuerdateien für Marketing-Version, Build-Label und Release-Kanal

- `Dokumentation`
  Arbeitsnotizen, Legacy-Material und Referenzen

- `.github`
  Issue-Templates und GitHub-Projektstruktur

## Design und GUI

Die visuelle Richtung für Notary ist aktuell in zwei Referenzen festgehalten:

- [Design-Styleguide](Dokumentation/Design-Styleguide.md)
- [App-Icon-Konzept](Dokumentation/Notary-App-Icon-Concept.svg)
- [Packaging-Plan](Dokumentation/Packaging-Plan.md)

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
- LaunchAgent für den Menüleisten-Begleiter im Paketinhalt
- vertrauliche Bootstrap-Helfer separat unter `*.local/`

## Versionierung

Notary verwendet aktuell ein zweistufiges Versionsmodell:

- Marketing-Version: numerisch, z. B. `2.1`
- Build-Label: intern, z. B. `1B32h`

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

Für laufende Beta-Entwicklung gilt:

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
- finaler `2.0`-Build: `1A315`

Empfohlene Tag-Namenskonvention für künftige Releases:

- öffentliche Beta: `1B32h-v2.1-beta`
- Release Candidate: `1B188a-v2.1-rc`
- finaler Release: `v2.1-1B227`
- späterer Hotfix: `v2.1.1`

Bei Vorabständen steht das Build-Label bewusst am Anfang. Nur finale Releases beginnen mit der Marketing-Version. Die GitHub-Release-Titel dürfen lesbarer gesetzt werden, z. B. `1B32h - v2.1 Beta` oder `v2.1 - 1B227`.

Für den praktischen Workflow im Repository:

- Branching und Beitragsablauf: [CONTRIBUTING.md](CONTRIBUTING.md)
- Release-Ablauf: [RELEASE.md](RELEASE.md)

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
