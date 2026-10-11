# Engagement: Check-Intervalle

## Stand

Diese Definition ist als Metadaten in `CheckSpec.executionPolicy` und der
Check-Registry verankert. Der aktuelle Runner fuehrt weiterhin vollstaendige
Laeufe aus. Die Metadaten aktivieren noch keinen Scheduler, keine parallelen
Worker und keinen Ergebnis-Cache. One-shot-Verhalten bleibt unveraendert.

## Ausfuehrungsklassen

| Prio | Klasse | Ausfuehrung |
| --- | --- | --- |
| 0 | realtime | Ereignisgesteuert; kurzes Polling als Fallback |
| 1 | configuredInterval | Wiederkehrend nach konfiguriertem Intervall |
| 2 | everyTenMinutes | Alle zehn Minuten |
| 3 | hourly | Stuendlich |
| 4 | daily | Alle 24 Stunden |
| 5 | serviceStart | Einmal pro Engagement-Prozessstart |

Die Zahlen beschreiben Frequenz, nicht Finding-Severity, Ausfuehrungsreihenfolge
oder Worker-Prioritaet. Realtime-Polling wird noch separat definiert; es ist
keine Garantie fuer sofortige Erkennung. Beim Start sind konfigurierte Checks
zunaechst zu pruefen, bevor ihre wiederkehrenden Intervalle greifen.

## Technische Fehler und Retry

Ein technischer Auslesefehler liefert kein belastbares Ergebnis. Der Benchmark
wird dann unabhaengig von seinem regulaeren Intervall bei jedem folgenden
Scheduler-Durchlauf versucht. Kein Busy Loop, keine ueberlappenden Versuche
desselben Checks. Nach einem belastbaren Ergebnis endet Retry; wiederkehrende
Checks starten ihr regulaeres Intervall erneut. Fuer Prio 2 bis 5 ist das die
vereinbarte Regel. Bei Prio 0/1 gilt vorlaeufig derselbe Metadaten-Default.

Ein gueltiges negatives Ergebnis ist kein Auslesefehler: Es gilt sofort nach
konfigurierter Severity. Ein deaktiviertes SSV mit hard fail bedeutet Verlust
der Compliance; fehlende Remediation macht daraus keinen Retry. SIP/SSV bleiben
nach belastbarer Auslesung bis zum naechsten Service-Start abgeschlossen.

Scheduler-Durchlauf und bisheriger vollstaendiger Compliance-Lauf sind nicht
gleichzusetzen. Die kuenftige Scheduler-Taktung wird separat festgelegt.
Nach einem Service-Neustart duerfen Ergebnisse der Klasse serviceStart nicht
als bereits fuer den neuen Prozess geprueft gelten.

## XProtect-Sonderregel

- Prio 3: beim Start, danach stuendlich.
- Technischer Fehler: Retry alle fuenf Minuten statt bei jedem Scheduler-Takt.
- Letztes belastbares Ergebnis maximal eine Stunde ab dem ersten Fehler halten.
- Weitere Fehler verlaengern diese Frist nicht; das Ergebnis ist als veraltet
  kenntlich zu machen.
- Nach Ablauf: nicht aktuell verifizierbar, keine fortgesetzte Compliance-Zusage.
- Gueltiges negatives Ergebnis gilt sofort, ohne Schonfrist.
- Erfolgreiche Pruefung beendet die Fehlerphase und startet das Stundenintervall.
- Ohne vorheriges Ergebnis gibt es keinen Status, der erhalten werden kann.

Ausfuehrungsklasse und Fehlerstrategie werden getrennt modelliert. Ohne explizite
Schonfrist gibt es keinen impliziten Erhalt alter Ergebnisse. Die vorhandene
macOS-27.0/27.1-SKIP-Regel bleibt davon unberuehrt.

## Registry-Zuordnung

Bereits festgelegt: SIP/SSV = Prio 5; XProtect = Prio 3 mit Sonderregel.
Alle anderen Checks bleiben vorlaeufig Prio 1. Insbesondere FileVault wird
nicht stillschweigend auf zehn Minuten umgestellt: der besprochene Fuenf-Minuten-
Wert waere ueber ein konfiguriertes Intervall abzubilden.

Weitere Zuordnungen, Ereignisquellen, Parallelitaet, Profilwechsel, Sleep/Wake
und die Darstellung unverifizierbarer Ergebnisse sind vor Scheduler-Aktivierung
zu definieren. Compliance, Proof, Persistenz und Transport sollen zentral vom
Koordinator geschrieben werden, nicht von einzelnen Workern.
