# Release Process

Diese Datei beschreibt den gewünschten Release-Ablauf für Notary.

## Grundmodell

Notary nutzt zwei Versionsebenen:

- Marketing-Version, z. B. `2.0`
- internes Build-Label, z. B. `1A148f`

Für Git und GitHub ist die Marketing-Version führend. Das Build-Label bleibt für Laufzeit, Logging, Jamf und Supportfälle relevant.

## Branch-Basis

Releases werden ausschließlich von `main` erzeugt.

Vor einem Release sollte gelten:

- `main` ist grün und baut lokal
- relevante Änderungen sind in `CHANGELOG.md` unter `Unreleased` erfasst
- offene, nicht zum Release gehörende Arbeiten bleiben in separaten Branches oder späteren PRs

## Tag-Schema

Empfohlenes Tag-Schema:

- `v2.0.0`
- `v2.1.0`
- `v2.1.1`

Verwendung:

- Major: nur bei größeren inkompatiblen Umstellungen
- Minor: für neue Funktionen oder größere Erweiterungen
- Patch: für Fehlerbehebungen, kleinere Verbesserungen und reine Wartungsreleases

## Release-Ablauf

1. `main` auf den gewünschten Stand bringen.
2. `CHANGELOG.md` für den Release-Inhalt prüfen.
3. Lokalen Build ausführen:

```sh
make build
```

4. Falls Paketartefakte Teil des Releases sind:

```sh
make release
```

Vor einem Release mit geändertem `Tools/deploy.sh` zusätzlich prüfen:

- Script-Subminor wurde erhöht, z. B. `2.0.7 -> 2.0.8`
- Jamf-Policy kann den neuen Script-Stand tatsächlich übernehmen
- bekannte Deploy-Fixes sind in `README` oder Release Notes erwähnt, wenn sie für Feldbetrieb relevant sind
- bei Packaging-Umstellungen wurden Service-Pfad und Legacy-Cleanup bewusst gegen ältere Clients geprüft

5. Git-Tag erzeugen:

```sh
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

6. Auf GitHub ein Release auf Basis des Tags veröffentlichen.

## Inhalt eines GitHub Releases

Ein Release sollte kurz dokumentieren:

- wichtigste Änderungen
- betroffene Bereiche, z. B. Runner, Proof, Transporter
- Build-/Packaging-Hinweise, wenn relevant
- Deploy-/Policy-Hinweise, wenn sich `Tools/deploy.sh` oder das LaunchDaemon-Verhalten geändert haben
- bekannte Einschränkungen oder Folgearbeiten

## Changelog-Pflege

Arbeitsstand kommt zunächst unter:

- `## Unreleased`

Beim Release wird daraus der eigentliche Release-Inhalt für GitHub und die Versionshistorie abgeleitet. Solange wir noch keinen streng formalen Changelog-Prozess fahren, reicht ein knapper, ehrlicher Überblick.
