# Notary Packaging Plan

Dieser Plan beschreibt die nächste Packaging-Stufe für Notary: eine sichtbare App in `/Applications` und ein separater Service-Pfad für `Engagement`.

## Ziel

Notary soll für Benutzer sichtbar und normal startbar sein, ohne die Betriebssicherheit des Hintergrunddienstes an einen beweglichen App-Pfad zu koppeln.

Deshalb gilt künftig:

- GUI als `Notary.app` in `/Applications`
- `Engagement` als separates Service-Binary außerhalb der App
- LaunchDaemon startet den stabilen Service-Pfad
- GUI bleibt lesend und startet keinen eigenen Hintergrunddienst

## Zielstruktur auf dem Client

- `/Applications/Notary.app`
  Sichtbare App für Report-GUI und spätere lokale Produktinteraktion

- `/usr/local/libexec/notary`
  Stabiler Pfad für das Service-Binary, das `--engagement` ausführt

- `/Library/LaunchDaemons/de.twocent.notary.plist`
  LaunchDaemon mit Verweis auf `/usr/local/libexec/notary`

- `/var/db/notary.plist`
  Geschützter Root-State für Transport, Token und Laufzeitdaten

## Warum nicht direkt aus der App starten

Ein LaunchDaemon sollte nicht von `/Applications/Notary.app/Contents/MacOS/Notary` abhängen, weil:

- Benutzer die App umbenennen können
- Benutzer die App verschieben können
- Bundle-Ersetzungen während Updates unnötige Betriebsrisiken erzeugen
- Support und Policy-Logik mit einem stabilen Service-Pfad einfacher bleiben

## Rollenmodell

### Notary.app

- Standardstart ohne Parameter
- öffnet die Report-GUI
- liest den öffentlichen Report
- bietet später sichtbare Menüpunkte wie Configurator oder Hilfe

### Service-Binary

- läuft als `root`
- wird durch LaunchDaemon mit `--engagement` gestartet
- schreibt State, Proof und Transportdaten
- bleibt die operative Quelle der Wahrheit

## Packaging-Ziele

### Paketinhalt künftig

- `Notary.app` nach `/Applications`
- Service-Binary nach `/usr/local/libexec/notary`
- optional Hilfsdateien oder Ressourcen im App-Bundle
- LaunchDaemon weiter über `Tools/deploy.sh`

### Was bei Updates weiter gelten soll

- bestehende `notary.plist` bleibt erhalten
- Deploy-Script darf Legacy-Pfade bereinigen
- LaunchDaemon zeigt nur auf den libexec-Pfad
- sichtbare App und Service dürfen unabhängig aktualisiert werden, solange sie denselben Code- und Formatstand verstehen

## Legacy-Cleanup

Mit der Umstellung sollen alte Pfade aktiv aufgeräumt werden:

- `/usr/local/sbin/notary`
- ältere historische Artefakte wie `ComplianceRunner` oder `harden.sh`

## Makefile-Anpassungen

Die nächste Packaging-Stufe braucht voraussichtlich:

- neues Ziel für das App-Bundle
- Payload für `/Applications/Notary.app`
- Payload für `/usr/local/libexec/notary`
- weiter signiertes PKG mit beiden Inhalten
- später optional Bundle-Metadaten wie `Info.plist`, App-Icon und Ressourcen

## Mindestumfang für den ersten Schritt

Der erste Umbau muss noch kein endgültiges Multi-Target-Produkt sein.

Ausreichend für Phase 1:

- vorhandenes Binary weiterverwenden
- einmal als App-Bundle einbetten
- einmal als Service-Binary nach `libexec` installieren
- Deploy-Script auf `libexec` zeigen lassen

## Spätere Ausbaupfade

- getrennte Targets für GUI und Service
- eigener `NotaryCore`
- App-Ressourcen und finales Icon-Set
- sichtbare About-/Help-/Configurator-Oberflächen

## Entscheidungsstand

Aktueller Beschluss:

- sichtbare App in `/Applications`: ja
- Service-Binary unter `/usr/local/libexec`: ja
- LaunchDaemon direkt aus der App starten: nein
