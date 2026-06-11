# Contributing

Diese Datei beschreibt den praktischen Standard-Workflow für Änderungen an Notary.

## Branching

Für das Projekt gilt aktuell ein bewusst einfacher Ablauf:

- `main`
  Stabiler Integrationszweig und Quelle für Releases

- `feature/<kurzbeschreibung>`
  Für neue Funktionen, Architekturarbeiten und Benchmarks

- `fix/<kurzbeschreibung>`
  Für Fehlerbehebungen und Regressionen

- `docs/<kurzbeschreibung>`
  Für reine Dokumentationsänderungen

Empfehlung:

- Kleine, klar abgegrenzte Änderungen pro Branch
- Branch-Namen kurz, aber eindeutig halten
- Keine direkte Arbeit auf `main`, außer für initiale Bootstrap- oder Notfallarbeiten

## Commit-Stil

Commits sollten kurz und beschreibend sein, zum Beispiel:

- `Add GitHub issue templates and roadmap`
- `Refresh documentation for current runtime model`
- `Persist Jamf bearer token between runs`

Wichtiger als ein starres Schema ist hier gute Lesbarkeit.

## Entwicklungsablauf

1. Von `main` aus einen neuen Branch anlegen.
2. Änderungen lokal umsetzen.
3. Relevante Prüfung ausführen, mindestens wenn Code betroffen ist.
4. Änderungen committen.
5. Branch pushen.
6. Pull Request nach `main` eröffnen.
7. Nach Prüfung und Abschluss in `main` mergen.

## Lokale Validierung

Für Codeänderungen ist der aktuelle Mindestpfad:

```sh
make build
```

Wenn Packaging oder Deployment betroffen ist, zusätzlich je nach Bedarf:

```sh
make release
make staple
```

## Pull Requests

Jeder Pull Request sollte mindestens beantworten:

- Was wurde geändert?
- Warum wurde es geändert?
- Welche Auswirkungen hat das auf Runner, Proof oder Transporter?
- Wie wurde der Stand validiert?

## Releases

Releases werden von `main` aus erzeugt und mit Git-Tags markiert. Details stehen in [RELEASE.md](/Users/steffi/Coding/Notary/RELEASE.md).
