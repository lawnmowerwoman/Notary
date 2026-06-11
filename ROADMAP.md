# Roadmap

Diese Roadmap bündelt die aktuell bekannten Themen für Notary in einer Reihenfolge, die Architektur, Produktreife und Delivery sinnvoll zusammenführt. Sie dient als Arbeitsgrundlage für GitHub-Issues, Releases und spätere Meilensteine.

## Aktueller Stand

Bereits umgesetzt oder als Basis vorhanden:

- Wiederverwendung des Jamf-API-Tokens mit Refresh erst bei Ablauf
- Transport-Updates nur noch bei Änderungen der Findings
- Heartbeat des Transporters nur noch alle 60 Minuten
- GitHub-Repository, Versionsbasis und initiale Projektdokumentation

## Nächste Schwerpunkte

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

- `System uptime / last reboot monitoring`
  Issue: `#7`
  Ziel: Uptime und letzten Reboot überwachen und optional Warnungen ausgeben, wenn Schwellenwerte überschritten werden.

## Geparkte Themen

Die beiden GUI-Themen bleiben bewusst außerhalb der aktiven Produktdokumentation, bis mindestens ein erster Dummy oder Scaffold im Repository vorhanden ist.

- `Reporting option via local GUI`
  Issue: `#3`

- `Configuration GUI for admins generating mobileconfig`
  Issue: `#6`

## Vorschlag für Abarbeitung

1. Architekturthemen zuerst stabilisieren.
2. Anschließend die Check-Abdeckung und weitere Benchmarks ausbauen.
3. Danach Dokumentation, Release-Prozess und Branching weiter schärfen.
4. GUI-Themen erst wieder aktiv in die Produktdokumentation aufnehmen, sobald ein erster Dummy existiert.

## In GitHub abbilden

Jeder Punkt dieser Roadmap sollte als eigenes GitHub-Issue gepflegt werden. So können wir:

- Fortschritt sichtbar verfolgen
- Prioritäten sauber justieren
- spätere Releases und Milestones daran ausrichten
