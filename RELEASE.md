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

Notary trennt ab sofort sauber zwischen:

- öffentlichen Betas
- Release Candidates
- finalen Releases
- Hotfixes nach einem finalen Release

Empfohlenes Tag-Schema:

- öffentliche Beta: `v2.1-beta.1`
- weitere Beta: `v2.1-beta.2`
- Release Candidate: `v2.1-rc.1`
- finaler Release: `v2.1`
- späterer Hotfix: `v2.1.1`

Verwendung:

- `vX.Y-beta.N`
  Für öffentliche Teststände. Diese Tags verbrauchen bewusst keinen Patch-Slot.
- `vX.Y-rc.N`
  Für die Einfrierphase kurz vor dem Release.
- `vX.Y`
  Für den finalen Release einer Minor-Linie.
- `vX.Y.Z`
  Ausschließlich für echte Fehlerbehebungen nach einem finalen Release.

Wichtig:

- Ein finaler Release bekommt keinen `.0`-Suffix mehr.
- Öffentliche Betas werden im Release-Titel lesbar benannt, die Tags bleiben kurz und maschinenfreundlich.
- Das interne Build-Label, z. B. `1B15n` oder `1B100`, bleibt davon getrennt und wird zusätzlich im Paket-, Release- oder Support-Kontext geführt.

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
git tag -a vX.Y -m "Release vX.Y"
git push origin vX.Y
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
