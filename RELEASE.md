# Release Process

Diese Datei beschreibt den gewünschten Release-Ablauf für Notary.

## Grundmodell

Notary nutzt zwei Versionsebenen:

- Marketing-Version, z. B. `2.1`
- internes Build-Label, z. B. `1B32h`

Für finale Releases ist auf Git und GitHub die Marketing-Version führend. Für öffentliche Vorabstände ist das Build-Label führend, damit nur das finale Release einer Linie den prominenten `vX.Y`-Tag belegt.

Hinweis: Git-Tags dürfen keine Leerzeichen enthalten. Die GitHub-Release-Titel dürfen lesbar mit Leerzeichen gesetzt werden.

## Branch-Basis

Releases werden ausschließlich von `main` erzeugt.

Vor einem Release sollte gelten:

- `main` ist grün und baut lokal
- relevante Änderungen sind in `CHANGELOG.md` unter `Unreleased` erfasst
- offene, nicht zum Release gehörende Arbeiten bleiben in separaten Branches oder späteren PRs

## Tag-Schema

Notary trennt ab sofort sauber zwischen:

- öffentlichen Betas
- Release Candidates
- finalen Releases
- Hotfixes nach einem finalen Release

Empfohlenes Tag-Schema:

- öffentliche Beta: `1B32h-v2.1-beta`
- weitere Beta: `1B87c-v2.1-beta`
- Release Candidate: `1B188a-v2.1-rc`
- finaler Release: `v2.1-1B227`
- späterer Hotfix: `v2.1.1`

Verwendung:

- `<Build-Label>-vX.Y-beta`
  Für öffentliche Teststände. Das Build-Label steht vorn, damit GitHub-Vorabstände nicht wie finale Versions-Tags wirken.
- `<Build-Label>-vX.Y-rc`
  Für die Einfrierphase kurz vor dem Release.
- `vX.Y-<Build-Label>`
  Für den finalen Release einer Minor-Linie. Nur finale Releases tragen die Marketing-Version an erster Stelle.
- `vX.Y.Z`
  Ausschließlich für echte Fehlerbehebungen nach einem finalen Release.

Wichtig:

- Ein finaler Release bekommt keinen `.0`-Suffix mehr.
- Öffentliche Betas und Release Candidates werden über ihr konkretes Build-Label identifiziert.
- Nur der finale Build einer Linie darf als Tag mit der Marketing-Version beginnen, z. B. `v2.1-1B227`.
- GitHub-Release-Titel dürfen menschenlesbar sein, z. B. `1B32h - v2.1 Beta` oder `v2.1 - 1B227`.

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

Für Confidential Ministry Builds zusätzlich prüfen:

- `make release-confidential` zeigt vor der Signierung den Confidential-Build-Banner.
- Der vertrauliche Transporter wird ausschließlich aus `Sources.local/` eingebunden.
- Operative Deployment-Helfer bleiben in `*.local/`-Verzeichnissen.
- Bei Packaging-Umstellungen wurden Service-Pfad und Legacy-Cleanup bewusst gegen ältere Clients geprüft.

5. Git-Tag erzeugen:

```sh
git tag -a "1B32h-v2.1-beta" -m "1B32h - v2.1 Beta"
git push origin "1B32h-v2.1-beta"

git tag -a "v2.1-1B227" -m "Release v2.1 - 1B227"
git push origin "v2.1-1B227"
```

6. Auf GitHub ein Release auf Basis des Tags veröffentlichen.

## Inhalt eines GitHub Releases

Ein Release sollte kurz dokumentieren:

- wichtigste Änderungen
- betroffene Bereiche, z. B. Runner, Proof, Transporter
- Build-/Packaging-Hinweise, wenn relevant
- Deploy-/Policy-Hinweise, wenn sich der Confidential Deployment Workflow oder das LaunchDaemon-Verhalten geändert haben
- bekannte Einschränkungen oder Folgearbeiten

## Aktueller Beta-Kandidat

- Version: `2.1`
- Build: `1B19h`
- Paket: `dist/notary-2.1-1B19h.pkg`
- Build-Typ: Confidential Release Build
- Transport: confidential implementation
- Eingebettete Public Keys: `1`
- Signatur: Developer ID Installer, gültig
- Notarisierung: Accepted
- Staple: valid
- Gatekeeper: `accepted`, `source=Notarized Developer ID`
- Größe: `2.9M`
- SHA-256: `59381a1172b8a136850da6ffd2eab1e2858c325d436dfdf89d9977c8a9935307`

Hinweis: Ein GitHub Beta-Release darf erst erstellt werden, wenn der zugehörige
öffentliche Source-Stand bereinigt ist. GitHub erzeugt automatisch Source
Archives für Tags; ein Release-Tag auf einem noch nicht bereinigten Stand würde
alte Transporter-Quellen erneut veröffentlichen.

## Changelog-Pflege

Arbeitsstand kommt zunächst unter:

- `## Unreleased`

Beim Release wird daraus der eigentliche Release-Inhalt für GitHub und die Versionshistorie abgeleitet. Solange wir noch keinen streng formalen Changelog-Prozess fahren, reicht ein knapper, ehrlicher Überblick.
