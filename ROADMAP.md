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
