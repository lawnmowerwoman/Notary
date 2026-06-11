# Notary Design Styleguide

Dieser Leitfaden beschreibt den aktuell gewünschten visuellen Charakter von Notary. Er ist bewusst leichtgewichtig, damit GUI, App-Icon und spätere Produktoberflächen an einer gemeinsamen Richtung ausgerichtet bleiben, ohne ein starres Design-System zu erzwingen.

## Zielbild

Notary soll sich anfühlen wie:

- ruhig
- vertrauenswürdig
- präzise
- lokal und systemnah
- modern im Sinne aktueller macOS-Gestaltung

Notary soll sich nicht anfühlen wie:

- laute Security-Software
- dunkles Admin-Tool mit Utility-Optik
- Dashboard mit überladener Warnästhetik
- generische Enterprise-Web-App

## Visuelle Leitidee

Die Kernidee von Notary ist nicht nur "Prüfung", sondern "Beurkundung".

Deshalb basiert die visuelle Sprache auf drei Motiven:

- `Proof`
  ein dokumentartiges Blatt oder eine notariell wirkende Urkunde
- `Shield`
  Schutz, Integrität, Systemvertrauen
- `Glass`
  Transparenz, Schichtung, lokale Einsicht statt aggressiver Alarmierung

Für die aktuelle Richtung bedeutet das:

- keine schweren massiven Vollflächen als Hauptcharakter
- halbtransparente Materialien statt flacher dunkler Kacheln
- Lichtkanten und innere Tiefe statt dicker schwarzer Konturen
- klare Typografie und viel Luft zwischen den Elementen

## GUI Definition

Die Standard-GUI von Notary bleibt report-only, soll aber visuell hochwertig und sofort verständlich wirken.

### Informationshierarchie

1. App-Titel und kurzer Statuskontext
2. Proof-Zusammenfassung
3. Findings-Liste
4. Detailansicht / technische Einordnung
5. Transport- und Laufzeitstatus

### Empfohlener Fensteraufbau

- oberer Bereich:
  Produktname, kurzer Untertitel, letzter Lauf, Transportzustand
- Summary-Zeile:
  `Runner`, `Compliance`, `Issues`, `Last Update`
- Hauptbereich links:
  Findings-Liste mit späterer Baum- oder Gruppenansicht
- Hauptbereich rechts:
  Details zum ausgewählten Finding oder zum letzten Lauf
- unterer Bereich:
  passive Statuszeile mit "read-only", Build-Label, Refresh-Hinweisen

### Interaktionsmodell

- Standardstart ohne Parameter öffnet die Report-GUI
- GUI startet keinen eigenen Engagement-Lauf
- GUI liest die öffentliche Report-Datei und reagiert auf Änderungen
- manueller Refresh bleibt als Fallback vorhanden
- spätere Admin-Funktionen gehören in Menüs, nicht in den Primärfokus

## Layout-Prinzipien

- großzügige Außenabstände
- klare Spalten und Karten
- wenige, dafür starke Oberflächenebenen
- nicht mehr als zwei konkurrierende Akzentfarben
- Monospace nur für technische Details und Log-/Build-Werte

## Material und Oberflächen

Die bevorzugte Richtung lehnt sich an das an, was heute mit Liquid Glass, Frosting und subtiler Tiefenstaffelung auf Apple-Plattformen vertraut wirkt.

Bevorzugt:

- helle oder leicht getönte Glasflächen
- weiche innere Schatten
- feine Lichtkante entlang der Oberfläche
- dezente Hintergrundverläufe
- transluzente Layer mit klarer Trennung zwischen Inhalt und Material

Vermeiden:

- harte schwarze Outlines
- vollgesättigte Security-Farben als Grundfläche
- schwere Drop-Shadows
- zu viele getrennte Boxen ohne visuelle Ordnung

## Farbkonzept

Die Farbpalette soll Vertrauen und technische Ruhe transportieren.

### Basisfarben

- `Notary Ink`
  tiefes blaugraues Grundpigment für Text, Linien und Symbolkern
- `Mist Glass`
  fast weißes, leicht kühles Material für Flächen
- `Slate Fog`
  neutral-kühler Sekundärton für Kartenhintergründe und getönte Glasflächen

### Akzentfarben

- `Proof Blue`
  kühles Cyan-Blau für aktive Zustände, Fokus und Glasreflexe
- `Seal Silver`
  helles Silber für Lichtkanten und ikonische Materialwirkung

### Statusfarben

- Erfolg:
  gedämpftes Grün, nicht neonhaft
- Warnung:
  warmes Amber mit geringer Sättigung
- Fehler:
  klares Rot nur für echte Problemzustände, nicht als Grundthema der App

## Typografie

Bevorzugt:

- `SF Pro Display` für große Titel
- `SF Pro Text` für Standardtext
- `SF Mono` für Build-Label, Logs und technische Zustände

Regeln:

- Titel groß, ruhig, nicht schreierisch
- Statuswerte prägnant und semantisch trennbar
- technische Nebeninformationen kleiner und sekundär
- keine dekorativen Fonts

## App-Icon Definition

Das App-Icon soll das Motiv `Proof im Shield` beibehalten, aber klar in eine modernere Apple-nahe Materialität übersetzen.

### Pflichtmerkmale

- kein ausgeschriebener Produktname im Icon
- abgerundete App-Kachel als Container
- Schildmotiv als primäre Form
- Dokument-/Proof-Element im Schild
- glasartige Tiefenwirkung
- lesbar bei kleinen Größen

### Stilmerkmale

- weiche, kühle Verlaufsfläche im Hintergrund
- Schild als halbtransparente helle Form mit Lichtkante
- Dokument als schwebender Layer im Schild
- reduzierte Linien im Dokument statt kleinteiliger Details
- dezente Reflexe statt dicker Umrandungen

### Was der aktuelle erste Entwurf gut trifft

- das Grundmotiv ist richtig
- Schutz plus Dokument ist sofort verständlich
- Notary bleibt als Produktidee klar lesbar

### Was gegenüber dem ersten Entwurf verändert werden soll

- kein Text im Icon
- weniger schwere dunkle Fläche
- weniger dicke schwarze Kontur
- mehr Transparenz, Lichtkante und Tiefenstaffelung
- insgesamt stärker in Richtung macOS-/Apple-Systemästhetik

## Icon-Referenz im Repository

Die aktuelle Konzeptdatei liegt unter:

- [Notary-App-Icon-Concept.svg](/Users/steffi/Coding/Notary/Dokumentation/Notary-App-Icon-Concept.svg)

Diese Datei ist noch kein finales Produktions-Asset, sondern eine visuelle Richtungsdefinition für App-Icon, GUI-Sprache und spätere Branding-Arbeit.

## Komponentenstil für die GUI

### Summary Cards

- große Werte
- kurze Titel
- mehrzeilige Werte erlaubt
- helle Glasfläche mit feiner Kontur

### Findings-Bereich

- ruhige Listendarstellung
- Priorität über Ordnung, nicht über Farbe
- später vorbereitbar für Baumdarstellung

### Detailbereich

- technische Lesbarkeit vor Dekoration
- Monospace nur dort, wo wirklich hilfreich
- ausreichend Zeilenhöhe

### Footer / Status

- unaufdringlich
- sekundäre Farbe
- keine laute Alarmierung im Grundzustand

## Motion

Animationen sollen knapp und funktional bleiben:

- sanftes Einblenden beim Fensterstart
- unaufgeregte Aktualisierung bei neuem Report
- keine übertriebenen Bounce- oder Scale-Effekte

## Do / Don't

Do:

- Shield und Proof als Kern behalten
- Tiefe über Material statt über Masse erzeugen
- die GUI lesbar und ruhig halten
- Apple-nahe Zurückhaltung mit eigener Identität verbinden

Don't:

- Schrift ins App-Icon setzen
- dunkle Kachel plus weiße Kontur als Endzustand übernehmen
- Security-Alarmästhetik als Grundgefühl etablieren
- jede Information gleich laut darstellen
