# Notary 1C: Licensing Check-In und lokaler Cache

Die 1C-Beta spricht mit:

```text
POST https://license.ministryofcode.de/api/v1/devices/check-in
```

Der Aktivierungscode kommt aus dem dedizierten oder allgemeinen Managed Profile
oder dem bereits gespeicherten Runner-State. Ohne konfigurierten Code gibt es
keinen Check-In. Diese Beta extrahiert keinen Aktivierungscode aus einem Token
und speichert ihn auch nicht als Konfiguration. Die Erweiterung des Deploy-
Scripts folgt spaeter; eine manuelle Eingabe in der lokalen GUI ist nicht Teil
dieses Builds.

## Cache und Vertrauen

Der Runner verwendet weiterhin `/var/db/notary.plist` (root, Modus `0600`).
Es gibt keine neue Token-Datenbank. Unter `apptoken` liegt das unveraenderte
signierte Artefakt, unter `appTokenCache` die zugehoerige Server-Metadatenstruktur:

- `activationCode`: der fuer die Anfrage konfigurierte Code;
- `tokenId` und `tokenVersion`: zuletzt akzeptierte Antwort-Metadaten;
- `serverManaged`: der Server ist fuer diesen Code massgeblich;
- `rejectionReason`: eine bestaetigte Ablehnung, falls vorhanden.

Token und Metadaten werden gemeinsam unter Dateisperre atomar geschrieben.
Die Metadaten sind keine eigene Berechtigung; jede Verwendung prueft erneut
Signatur, bekannten Public Key, Issuer, Produkt und Gueltigkeit des Tokens.
Vor dem Speichern muessen der signierte Aktivierungscode, die Token-ID, das
Produkt und das Ablaufdatum mit Anfrage bzw. Antwort uebereinstimmen.
Rueckschritte der bekannten Token-Version werden verworfen. Die Version ist
Server-Metadatum und wird nicht nachtraeglich in das signierte Token eingebaut.

Ein bereits gueltiges Profil-Token kann den lokalen Cache vor dem ersten
Serverabruf initialisieren. Bestehende serververwaltete Caches werden dabei
nicht ueberschrieben. Das generische AppTokenKit behaelt seine bisherigen
Quellenregeln; Notarys 1C-Handler bevorzugt fuer den konfigurierten Code einen
bereits serververwalteten Cache. Ein abgelaufenes Server-Token erlaubt keinen
Rueckfall auf ein altes, laenger gueltiges Profil-Token.

## Antwortverhalten

- `200`: erst lokal pruefen, dann Token/Revision speichern und Features neu
  auswerten. Eine erfolgreiche neue Ausgabe hebt eine vorherige Ablehnung auf.
- `304`: wird nur akzeptiert, wenn eine gueltige bekannte Token-ID und die
  tatsaechlich gespeicherte Version uebermittelt wurden.
- `403 license_disabled` / `license_not_valid`: Ablehnung speichern und
  optionale Features deaktivieren. Der Cache hebt diese Ablehnung nicht auf.
- `404 activation_code_unknown`: ebenfalls eine bestaetigte Lizenzablehnung.
- Timeout, DNS-/TLS-Fehler, `5xx`, Rate Limit oder nicht erkannte Proxy-Fehler:
  den vorhandenen gueltigen Cache behalten. Fehler heben bestehende
  Ablehnungen nicht auf. Umleitungen werden nicht verfolgt.
- Ungueltige Tokens, unpassende Metadaten oder fehlerhafte JSON-Antworten:
  keine Uebernahme; ein vorhandener gueltiger Cache bleibt erhalten.

Die Anfrage enthaelt keinen Bearer Token und keinen privaten Signing Key.
Sie uebermittelt Code, pseudonymen Machine Identifier, Notary-Build und, falls
bekannt, die aktuelle Token-ID/Version. Ohne bekannte Version wird keine `1`
geraten; der Server liefert das Token erneut aus.

Die lokale Compliance-Auswertung benoetigt keinen erreichbaren Lizenzserver.
Licensing steuert Transporter-, Reporter- und Configurator-Freigaben, nicht das
Ergebnis der lokalen Checks. Der Jamf-Last-Contact wird dadurch nicht aktualisiert.

## GUI und Menu-Bar

Die normale GUI darf die private Runner-Plist nicht lesen. Sie verwendet fuer
serververwaltete Lizenzen deshalb die bereits bestehende oeffentliche Report-
Plist mit den vom Runner geprueften effektiven Features und dem Ablaufdatum.
Fuer diese Freigaben wird nur der root-eigene, nicht gruppen-/weltbeschreibbare
Report samt geschuetztem Elternverzeichnis akzeptiert, nicht ein Benutzer-
Report aus `/tmp`. Das signierte Token selbst wird nicht veroeffentlicht.

Lizenzinformationen werden bei einer Serverantwort bereits vor dem naechsten
vollstaendigen lokalen Check in den vorhandenen Report projiziert. Compliance-
Werte, Auswertungszeit und letzter Jamf-Kontakt bleiben dabei unveraendert.
Alte Reports ohne `appTokenServerManaged` bleiben lesbar.

## Vorbereitung auf dem Server

Vor dem Rollout die bereits importierten Lizenzdatensaetze vervollstaendigen:
Kunde, Produkt, Gueltigkeit, Feature Flags und erlaubte Geraeteanzahl. Nach dem
ersten erfolgreichen Abruf bestimmen die Server-Flags die optionalen Features;
das alte Profil kann entfernte Features nicht wieder freischalten.

## Tests

```sh
swift run apptoken-tests
swift run transport-tests
zsh Tools/test_licensing_integration.sh
```

Die Integration verwendet das lokale AMD64-Image
`ministry/licensingservice:0B1`, einen isolierten Container, eine oeffentliche
Test-Schluesselfixture und temporaere Plists. Sie veraendert keine produktiven
Lizenzdatensaetze, Profile oder Tokens. Der Test-Container und seine Volumes
werden anschliessend entfernt. Auf diesem Mac wird fuer Builds/Tests das
vollstaendige Xcode mit `DEVELOPER_DIR` verwendet.

Interner Paket-Build mit echten lokalen Modulen, ohne Notarisierung:

```sh
make release-confidential
```
