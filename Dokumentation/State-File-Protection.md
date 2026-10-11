# Dienst-State und Cocoa 257

## Befund vom 2026-10-11

Notary 1C42m meldet bei zeitweise verweigertem Lesen von /var/db/notary.plist
Cocoa 257 mit unterliegendem POSIX EPERM. Der gleiche Dienst arbeitet später
wieder erfolgreich. Nach dem Update wurde dies auch auf dem zweiten Test-Mac
beobachtet. Der genaue Zusammenhang mit Display Off, Sleep, Dark Wake oder
Benutzersitzung ist noch nicht abschließend nachgewiesen.

Metadaten auf dem lokalen Entwicklungs-Mac zeigen tatsächlich
NSFileProtectionCompleteUnlessOpen, root:wheel und 0600. SecurePlistStore und
ReconEAStore setzen die Class-B-Schutzklasse beim Schreiben ausdrücklich.
Der bisherige load()-Fehlerpfad bezeichnet auch reine Lesefehler als Decode-Fehler.

## Anpassung

- Class C (NSFileProtectionCompleteUntilFirstUserAuthentication) für den
  Hintergrunddienst verwenden. Auf macOS entspricht ihre Schlüsselverfügbarkeit
  dem gemounteten Volume und damit FileVault-Eigenschaften.
- Bestehende Datei vor dem Zyklus unter dem bestehenden Dateilock per
  Attributänderung migrieren, ohne Inhalte zu lesen, zu löschen oder zu ersetzen.
- Beide Schreibpfade behalten Class C und private 0600-Rechte; Root bleibt Eigentümer.
- Read und Decode separat melden. Fehlgeschlagene Migration/Lesen bricht den Zyklus
  weiter ab; keine leere Ersatzkonfiguration, kein frischer Compliance-/Kontaktwert.
- Keine Änderung an FileVault, SIP, Sandbox, Sleep-Einstellungen oder Entitlements.

Quelle: [Apple Data Protection classes](https://support.apple.com/guide/security/secb010e978a/web).
Apple beschreibt auf macOS für Class B Login/Logout als Grenze, nicht bloßes
Bildschirmsperren. Deshalb beweist die vorhandene Schutzklasse allein noch
keine macOS-27.2-Regression beim Sleep.

## Verifikation

Regressionstests prüfen Migration ohne Inhaltsänderung, Class C/0600 nach Save,
Merge und EA-Schreiben, erhaltene Werte und getrennte Read-/Decode-Fehler.
Diese Tests ersetzen keinen echten Sleep/Wake-Test auf beiden Geräten.

Mit installiertem Test-Build Display Off, Bildschirmsperre, System Sleep und
Wake separat beobachten. Zeitstempel mit pmset Sleep-/DarkWake-/Wake-Ereignissen
korrelieren. Während echtem System Sleep erwartet Notary keine Ausführung;
bei gesperrtem Display oder Dark Wake ist ein laufender Zyklus möglich.
Kein Mac wird für Notary künstlich wach gehalten.

Der installierte 1C42m-Build und die produktive Plist werden durch reine
Quellcode-/Teständerungen nicht migriert. Die Migration erfolgt erst mit dem
neuen Runner bei dessen nächstem Zyklus.
