# Reporter / Configurator Ownership

Entscheidung vom 2026-10-11: Die neue Arbeitsversion liegt in
`/Users/steffi/Coding/Ministry/Notary Admin`.

## Ziele

- Eigenständiger Launcher mit den bestehenden Reporter-/Configurator-Funktionen.
- Neue Funktionen ausschließlich in der Admin-Arbeitsversion entwickeln.
- Die bisherige Notary UI ab sofort feature-freezen, als deprecated und zur
  späteren Entfernung vorgesehen behandeln.
- Vorhandene Funktionen bis zum getesteten Ersatz unverändert anbieten.
- Lokale Entwicklungs-Credentials unabhängig vom Notary-Dienst im Keychain halten.

## Eingefrorene Quellen

- Reporter: `Sources.local/NotaryConfidentialReporter/` (gesamtes Modul).
- Configurator: `NotaryConfiguratorWindowDelegate` in
  `Sources/NotaryRunner/UI/NotaryGUI.swift` und `ConfiguratorSupport.swift`.

Der lokale Gerätebericht, Menüleistenstatus und NotaryCore sind nicht durch
diesen UI-Feature-Freeze eingefroren. Sicherheits-/Kompatibilitätsreparaturen
der alten Oberflächen bleiben möglich. Neue Admin-Features werden nicht
in die Legacy-Oberflächen zurückkopiert.

## Nicht-Ziele

- Noch keine Entfernung oder Abschaltung in Notary 2.2.
- Keine Veröffentlichung der vertraulichen Reporter-Quellen auf GitHub.
- Kein öffentlicher Release mit lokalem Entwicklungszugang als Autorisierung.
- Noch kein vollständiges Jamf-Setup oder direktes Profil-Publishing (v3).

Release-Entscheidung Mitte November 2026 nach getesteter eigenständiger Beta,
Broker-Autorisierung, Übergang und Licensing-Admin-Backup/Restore.
