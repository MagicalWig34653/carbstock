# Carb-Vorrats-App – Feature Spec

**Stand:** 2026-11-21 (Original vom selben Tag, hier fachlich ausgearbeitet)
**Zweck:** Kohlenhydrat-Vorrat fürs Radtraining intelligent verwalten – Bestand, Haltbarkeit, Kosten und Verbrauch in einer App, damit man nie wieder zu viel kauft (oder zu wenig hat).
**Plattform (Vorgabe Lino):** native iOS-App in Swift/SwiftUI, **kein eigenes Backend**, Synchronisation über **iCloud (CloudKit, privater Bereich des Nutzers)**.
**Status:** Spezifikation, keine Implementierung. Keine Nachricht an Dritte (auch nicht an Apple) wurde gesendet.

---

## 0. Lesehinweis, Legende, Änderungsübersicht

### 0.1 Kennzeichnung der Aussagen

| Marke | Bedeutung |
|---|---|
| **[Original]** | Vom Autor gewünscht, unverändert übernommen. Nichts davon wurde gestrichen (siehe Anhang A). |
| **[Konkretisierung]** | Fachliche Ausarbeitung desselben Wunsches (Formeln, Randfälle, Definitionen). |
| **[Vorschlag]** | Neu, nicht im Original. Gilt erst nach Freigabe. Wird nicht unbemerkt Teil des MVP. |
| **[Annahme]** | Arbeitsannahme, bis die Frage entschieden ist. Der Wert steht im Entscheidungsregister (Abschnitt 18). |
| **❓ O-nn** | Offene Produktentscheidung. Kein Wert wurde festgelegt, nur eine Empfehlung genannt. |
| **[Beleg]** | Offizielle Apple-Quelle, am 2026-11-21 abgerufen (Quellenliste in Abschnitt 13). |
| **[Nicht belegt]** | Behauptung stammt nur aus Foren/Erfahrung. Vor Verlass darauf im Spike prüfen. |

### 0.2 Was sich gegenüber dem Original geändert hat (Kurzfassung)

1. **Charge statt Produkt-Bestand:** Mehrere Kaufvorgänge mit verschiedenen MHD lassen sich im Original-Modell (ein `expiryDate` je Produkt) nicht abbilden. Eingeführt wird die **Charge** (Abschnitt 5).
2. **Bestand = Summe von Buchungen** (Bestandsbuchungen, unveränderlich), nicht ein überschreibbarer Zähler. Das macht den iCloud-Abgleich konfliktarm (Abschnitt 9).
3. **iCloud-Sync ist jetzt im MVP**, weil Lino es vorgibt. Das ersetzt die Abgrenzung „keine Multi-Geräte-Sync-Komplexität“ aus Abschnitt 6 des Originals. Ein eigenes Sync-System entsteht trotzdem nicht; es wird Apples CloudKit-Spiegelung genutzt.
4. **„Push“ wird zu lokalen Benachrichtigungen**, weil es kein Backend gibt, das Push senden könnte (Abschnitt 8).
5. **Apple-Regeln zu Gesundheitsdaten und iCloud** sind geprüft; sie ändern, was in iCloud landen darf (Abschnitt 11, Entscheidung O-01).
6. **Das Beispiel in Abschnitt 8 des Originals rechnet nicht auf:** 14 kg Vorrat bei 1,8 kg Bedarf pro 2 Wochen reichen etwa 15,6 Wochen (≈ 3,6 Monate), nicht „~8 Monate“. Siehe Abschnitt 14 und O-06.
7. **Fehlende Angaben im Original** wurden nicht erfunden, sondern als offen markiert: Carbs/h für Z2, was „Regen“ bedeutet, was die „Packlisten-Challenge“ ist, wie ein 12-Wochen-Bedarf ohne eingetragene Sessions entsteht.

---

## 1. Problem & Ziel **[Original]**

### Problem
- Man hortet Gele, Riegel und Drink-Pulver, ohne den **tatsächlichen Bedarf** zu kennen.
- **Haltbarkeit** wird übersehen → abgelaufene Gele mitten in der Peak-Phase.
- **Preisvergleiche** (Cost per Gramm Carbs) sind mühsam; Rabattaktionen (Black Friday) verleiten zu unnötigen Käufen.
- Der **Session-Bedarf** (z.B. „So-Langfahrt braucht ~5 Gele“) ist nirgends verknüpft mit dem Bestand.

### Ziel
Eine App, die drei Fragen beantwortet:
1. **„Habe ich genug für die nächsten X Wochen?“**
2. **„Was läuft bald ab und sollte ich zuerst verfahren?“**
3. **„Lohnt sich dieser Kauf wirklich?“** (Preis + Menge + Haltbarkeit vs. Bedarf)

### Leitprinzipien **[Konkretisierung]**
- **Nachvollziehbar vor klug:** Jede Aussage der App („reicht 15 Wochen“, „Kauf unnötig“) nennt ihre Zahlen und die angewandte Regel. Keine Black-Box.
- **Ehrlich bei fehlender Datenlage:** Fehlt der Bedarf (keine Sessions, keine Wochenvorlage), sagt die App „nicht beurteilbar“ statt eine Scheingenauigkeit zu liefern.
- **Offline zuerst:** Alles funktioniert ohne Netz; iCloud gleicht nur ab.
- **Datensparsam:** Nur Daten, die die drei Fragen brauchen. Keine Gewichts-, Puls-, Leistungs- oder Gesundheitsdaten (Begründung Abschnitt 11).

---

## 2. Zielnutzer (Persona) **[Original]**

- Ausdauer-Radsportler mit 8–15h Training/Woche.
- Kombinierter Vorrat: Gele, Drink-Pulver, Riegel, Jelly.
- Nutzt Struktur-Training (MyWhoosh/Kickr) + lange Ausfahrten.
- Denkt in **Gramm Carbs**, nicht in Stück.
- Kauft gerne gebündelt (Black Friday), will aber Überkauf vermeiden.

**[Konkretisierung]** MVP-Nutzer ist **eine Person mit mehreren eigenen Geräten** (iPhone, ggf. iPad) unter **einer Apple-ID**. „Einzelperson“ (Original, Abschnitt 9) bedeutet damit nicht „ein Gerät“.

---

## 3. Plattform und Architektur-Rahmen **[Konkretisierung]**

| Thema | Festlegung / Stand |
|---|---|
| Sprache/UI | Swift, SwiftUI (Vorgabe Lino) |
| Backend | keines (Vorgabe Lino); jede Berechnung läuft auf dem Gerät |
| Speicher | lokale Datenbank auf dem Gerät als Wahrheitsquelle, gespiegelt in den **privaten CloudKit-Bereich** des Nutzers (`NSPersistentCloudKitContainer`-Mechanik, auch unter SwiftData) |
| Persistenz-Framework | SwiftData (Empfehlung) oder Core Data → **❓ O-03**, Entscheidung nach Spike S1 |
| Mindest-iOS / iPad | **❓ O-04** (nicht festgelegt; zum Prüfzeitpunkt wurde nicht verifiziert, welche iOS-Version aktuell ist) |
| Domänenlogik | als **eigenes Swift-Package ohne UI- und Persistenz-Abhängigkeit** (Einheiten, Buchungen, FEFO, Prognose, Kaufurteil, Packliste); vollständig unit-testbar mit eingespeister Uhr |
| Netzwerk | nur CloudKit (Apple). Keine Drittanbieter-SDKs, kein Analytics, keine Werbung, kein Tracking |
| Web-App/Android | entfallen durch die Vorgabe „native iOS ohne Backend“ → Original-Idee „Web als Admin-Tool“ **❓ O-16** (bestätigen) |

**Die sechs Hauptbereiche der App [Vorschlag, Informationsarchitektur]:** Bestand · Verbrauch zuerst · Bedarf & Prognose · Einkauf (Liste + Kauf-Entscheider) · Training & Packliste · Einstellungen (Farbgrenzen, Carbs/h, Erinnerungen, Export, Datenschutz, Daten löschen).

---

## 4. Kern-Features (MVP) **[Original, ausgearbeitet]**

Jedes Feature hat eine ID (F-…), auf die Akzeptanzkriterien (Abschnitt 15) verweisen.

### 4.1 Bestandsverwaltung (F-BEST)

**Original:**
- Produkt anlegen mit: Name / Marke; **Carbs pro Portion/Stück (g)** ← zentrale Metrik; **Menge im Bestand** (Stück, oder g Pulver); **Kaufpreis** (€) → automatisch **Carbs pro €** berechnen; **MHD / Ablaufdatum**; Kategorie (Gel, Drink, Riegel, Jelly, Selbstgemacht); Zusammensetzung (Glucose/Fructose-Verhältnis, z.B. 1:0,8) – optional.
- Bestand ändern: Verkaufen/einlagern mit +/- Button.
- Suche, Filter (nach Kategorie, nach bald ablaufend).

**Konkretisierung:**
- **Zwei Ebenen:** *Produkt* (Stammdaten: Name, Marke, Kategorie, Carbs je Portion, Einheit, Verhältnis) und *Charge* (ein Kauf: Menge, Gesamtpreis, MHD, Kaufdatum). Beim „Produkt anlegen“ fragt die Oberfläche beides in einem Zug ab, legt aber intern Produkt + erste Charge + eine Kaufbuchung an.
- **Einheiten:** Jedes Produkt hat eine Basiseinheit: **Stück** (Gel, Riegel, Jelly) oder **Gramm** (Pulver). Für Pulver wird zusätzlich die **Portionsgröße in g** und die **Carbs je Portion** erfasst; daraus ergibt sich Carbs je Gramm. So bleibt „Denken in Gramm Carbs“ erhalten, während der Bestand in der Packungseinheit geführt wird.
- **Carbs pro € (Original-Formel unklar):** Im Original steht `carbsPerEuro = carbsPerUnit*amount / Preis`, wobei `amount` = Bestandsmenge ist. Das wäre falsch, sobald Bestand schon verbraucht ist. Definition ab jetzt: **Carbs der gekauften Menge ÷ Gesamtpreis dieser Charge**. Angezeigt wird zusätzlich der Kehrwert **€ je 100 g Carbs** (besser vergleichbar). Beide Werte werden **berechnet, nicht gespeichert**.
- **Verkaufen/einlagern:** „Einlagern“ = Kauf/Zugang, „Verkaufen“ wird als **Abgang** umgesetzt. Annahme: gemeint ist *Verbrauchen/Abgeben*, nicht Handel (**❓ O-22**). Abgangsgründe: verbraucht, verschenkt/verkauft, entsorgt, Korrektur.
- **Schnellbuchung** über +/- am Produkt bucht immer auf die **Charge mit dem frühesten MHD** (FEFO, siehe 4.2); ein Tippen auf die Chargenzeile erlaubt gezielte Buchung.
- **Geschmack (Lino 23.11.):** Optionales Feld „Geschmack“ am Produkt (Freitext, z. B. Zitrone). Jede Sorte ist ein **eigenes Produkt** mit eigenem Bestand, eigenen Chargen und eigenen Carbs; die Anzeige lautet „Name · Geschmack“. Zwei Sorten desselben Namens und derselben Marke sind **keine Doppelten** (AC-S4). Bei vorhandenen Produkten lässt sich der Geschmack in der Detailansicht nachtragen. Nur das Feld, keine Bewertung, keine Auswertung.
- **Koffein- und Laktatzusatz (Lino 23.11.):** Zwei getrennte Ja/Nein-Optionen am Produkt, die bei der Kategorie **Gel** gesetzt werden können („Mit Koffein“, „Mit Laktat“), wie der Geschmack: gleiche Marke und gleicher Name mit anderem Zusatz sind **verschiedene Produkte** mit eigenem Bestand. Anzeige „Name · Geschmack · mit Koffein · mit Laktat“, soweit gesetzt. Bewusst **ohne** Mengen, Grenzwerte oder Hinweise (nicht genannt). Beim Wechsel der Kategorie weg von Gel werden die Zusätze beim Anlegen nicht gespeichert.
- **Suche/Filter:** Textsuche über Name, Marke und Geschmack; Filter Kategorie, „läuft in ≤ X Tagen ab“, „abgelaufen“, „ohne MHD“, „Bestand 0“ (archiviert).
- **Löschen:** Ein Produkt oder eine Charge mit Buchungen wird **archiviert**, nicht hart gelöscht (Begründung: Abschnitt 9.4). Hartes Löschen nur über „Alle Daten löschen“.
- **Pflichtfelder:** Name, Kategorie, Basiseinheit, Carbs je Portion (> 0). Optional: Marke, Verhältnis, MHD, Preis. Ohne Preis erscheinen keine €-Kennzahlen; ohne MHD ist die Charge „unbegrenzt“ (grau).
- **Selbstgemacht:** In V1 ein normales Produkt der Kategorie „Selbstgemacht“ (Carbs je Portion manuell, MHD meist kurz, Preis optional). Rezepte/Drink-Mixer bleiben V2 (Abschnitt 6) **❓ O-14**.

### 4.2 Haltbarkeits-Push (F-MHD)

**Original:**
- Farblegende: grün (≥6 Monate), gelb (<6 Monate), rot (<3 Monate), abgelaufen.
- „Verbrauch zuerst“-Liste: sortiert nach MHD – was zuerst weg.
- Push-/In-App-Erinnerung, wenn etwas in <1–2 Monaten abläuft.

**Konkretisierung:**
- **Status je Charge** (Stichtag = heute, Kalendertage in der lokalen Zeitzone; ein MHD gilt **bis einschließlich** des angegebenen Tages):
  - *grün:* MHD ≥ heute + 6 Monate · *gelb:* MHD < heute + 6 Monate · *rot:* MHD < heute + 3 Monate · *abgelaufen:* MHD < heute · *ohne MHD:* grau.
  - Farbe ist nie der einzige Hinweis: zusätzlich Symbol und Text („noch 74 Tage“) wegen Barrierefreiheit.
  - Schwellen 6 und 3 Monate sind Voreinstellungen **❓ O-12** (fest oder in den Einstellungen änderbar).
- **Verbrauch-zuerst-Liste:** nach **FEFO** (first expired, first out): Charge mit frühestem MHD zuerst; Chargen ohne MHD ans Ende; abgelaufene ganz oben, deutlich markiert. Zeigt je Zeile: Produkt, Restmenge, Carbs gesamt, Restlaufzeit, **empfohlene Verbrauchsrate** („≈ 2 Gele/Woche, damit es vor dem MHD weg ist“), sofern Bedarf bekannt ist.
- **Abgelaufene Ware:** Ein MHD ist ein Mindesthaltbarkeits-, kein Verfallsdatum. Die App entscheidet nicht für den Nutzer, ob Ware noch genutzt wird. Abgelaufene Chargen **zählen standardmäßig nicht** zum nutzbaren Bestand der Prognose. Der Nutzer kann sie *entsorgen* (Buchung „expire“) oder *trotzdem nutzen* (Charge wird für die Prognose wieder mitgezählt; Markierung bleibt). Automatisch gebucht wird nichts **❓ O-09**.
- **Erinnerungen:** siehe Abschnitt 8. Zusätzlich gibt es immer eine **In-App-Anzeige** („Läuft bald ab“) – die App darf nicht davon abhängen, dass der Nutzer Benachrichtigungen erlaubt.

### 4.3 Bedarfsrechner (F-BEDARF)

**Original:**
- Trainings-Tracker-Anbindung (manuell oder Import): Sessions mit Dauer + Typ (VO₂max, Schwelle, Z2, Longride).
- Carbs/h pro Session-Typ (Vorbelegung: hart 60–80 g/h, lang 70–90 g/h, Regen 30–50 g/h; editierbar).
- Prognose: Bedarf für die nächsten 1 / 4 / 12 Wochen vs. aktueller Bestand.
- Projektion: „Reicht für X Wochen / bis [Datum]“ – inkl. Haltbarkeit: Warnung, wenn eine MHD-Lücke vor dem errechneten Verbrauchsende klafft.

**Konkretisierung:**
- **MVP-Eingabe manuell** (Original Abschnitt 9). Ein Import aus Trainingsplattformen ist V2 (Abschnitt 6) und hat eigene Datenschutzfolgen (Abschnitt 11).
- **Session-Typen:** VO₂max, Schwelle, Z2, Longride und „regen“. Annahme: **„Regen“ meint Regeneration (Recovery-Fahrt), nicht Wetter** **❓ O-07**.
- **Carbs/h-Vorbelegung** als eingebaute Standardwerte (nicht als synchronisierte Datensätze, siehe 5.5 und 9.3): Original nennt Bereiche, die App braucht je Typ einen Zahlenwert plus Anzeige des Bereichs. **[Annahme, bis O-07 entschieden]:** VO₂max 70 (60–80), Schwelle 70 (60–80), Longride 80 (70–90), Regeneration 40 (30–50). **Für Z2 gibt das Original keinen Wert**; Arbeitsannahme 60 g/h, ausdrücklich ungeprüft → O-07. Der Nutzer überschreibt Werte je Typ und je Session.
- **Bedarf einer Session** = Dauer in Stunden × Carbs/h (Session-Wert, sonst Typ-Wert). Beispiel: 240 min Longride × 80 g/h = **320 g**.
- **Woher kommen Sessions für 4 und 12 Wochen?** Niemand trägt 12 Wochen Training im Voraus ein. Deshalb braucht die Prognose entweder eingetragene Sessions oder eine **Wochenvorlage** (wiederkehrende Sessions je Wochentag, mit Gültigkeitszeitraum) **[Vorschlag, nicht im Original] ❓ O-08**. Regel: Explizit geplante Sessions gelten am jeweiligen Tag; für Tage ohne Eintrag greift die Wochenvorlage (falls vorhanden). Ohne beides lautet die Aussage: **„mindestens bis [Datum der letzten geplanten Session]; darüber hinaus keine belastbare Aussage“.**
- **Prognose-Anzeige** (1 / 4 / 12 Wochen = 7 / 28 / 84 Tage ab heute): Bedarf in g Carbs, nutzbarer Bestand in g Carbs, Differenz, Ampel (reicht / knapp / Engpass). Optional Bandbreite aus den Carbs/h-Bereichen (**❓ O-23**, Empfehlung: nur Mittelwert, Bandbreite später).
- **Reichweite („reicht bis“):** Tagessimulation ab heute: Jeden Tag wird der Tagesbedarf nach FEFO aus den nutzbaren Chargen entnommen, Chargen verfallen zum MHD. „Reicht bis“ ist der letzte Tag, an dem der Tagesbedarf voll gedeckt ist; Wochenangabe = Tage ÷ 7, **abgerundet auf eine Nachkommastelle**.
- **MHD-Lücke (Original nicht eindeutig) – zwei getrennte Warnungen:**
  1. **Verfallsrisiko:** Menge je Charge, die bei FEFO-Verbrauch **vor dem MHD nicht aufgebraucht** wird („12 Gele · 300 g Carbs laufen am 15.01. unverbraucht ab“).
  2. **Versorgungslücke:** frühester Tag, an dem der nutzbare (nicht abgelaufene) Bestand den Bedarf der nächsten 7 Tage nicht mehr deckt, **obwohl** Ware vorhanden war, die abgelaufen ist.
- **Kategorien:** Die MVP-Prognose rechnet **in Gesamt-Carbs** und zeigt die Verteilung nach Kategorie nur an. Ob Gele durch Drink ersetzbar sind (Bedarf je Kategorie), ist offen **❓ O-19**.

### 4.4 Einkaufsliste & Kauf-Entscheider (F-KAUF)

**Original:**
- „Kaufen oder nicht?“-Urteil basierend auf: Bedarf vs. Bestand; Ablaufdatum des Angebots vs. Verbrauchszeitraum; Preis pro Gramm (Vergleich mit bisherigen Käufen).
- Black-Friday-Szenario: „X Gele zu 0,80 € – lohnt sich?“ → ja/nein + Begründung.

**Konkretisierung:**
- **Eingabe (Angebot):** Produkt (vorhandenes wählen oder neu), Menge, Gesamtpreis oder Stückpreis, optional Versandkosten und Rabatt, MHD des Angebots (optional), Kaufhorizont (Voreinstellung siehe unten). Die Bewertung ist ein **Gedankenspiel**; nichts wird gebucht, bis der Nutzer „Gekauft“ wählt (dann entstehen Charge + Kaufbuchung).
- **Urteil (deterministisch, regelbasiert, Regeln R1–R6 siehe Abschnitt 7.3):** `kaufen` · `teilweise kaufen (Menge n)` · `nicht kaufen` · `nicht beurteilbar` (dritter Zustand, weil ohne Bedarfsdaten kein ehrliches Ja/Nein möglich ist). Jede Begründung ist eine Liste von Zeilen mit Zahl und Regelnummer.
- **Kaufhorizont:** Zeitraum, für den der Bestand ausreichen soll. Arbeitsannahme **12 Wochen** (= größtes Prognosefenster des Originals) **❓ O-05**.
- **Schnäppchenregel** (Kauf trotz gedecktem Bedarf, weil der Preis außergewöhnlich ist): **standardmäßig aus**, weil „Überkauf vermeiden“ der Zweck der App ist **[Vorschlag] ❓ O-05**.
- **Einkaufsliste:** Liste geplanter Käufe (Produkt oder Freitext, Menge, geschätzter Preis, Status offen/gekauft). Aus einem Urteil „kaufen“ lässt sich ein Eintrag erzeugen. „Gekauft“ erzeugt Charge + Buchung.
- **Preisvergleich mit bisherigen Käufen:** Referenz = **Median** von € je g Carbs der **eigenen früheren Chargen desselben Produkts** (mindestens 2 Käufe), sonst derselben Kategorie (mindestens 3), sonst keine Referenz. Aussage „x % günstiger/teurer als dein Median“ nur mit Referenz.

### 4.5 Session-Packliste (F-PACK)

**Original:**
- Für eine geplante Session (z.B. „So-Langfahrt 4h“): errechnet konkrete Packliste („5 Gele + 1 Drink + 1 Bar“).
- Checkliste beim Packen abhaken → Bestand wird beim Haken automatisch reduziert.

**Konkretisierung:**
- **Ziel-Carbs** = Sessionbedarf (4.3) × (1 + Reserve). Reserve-Vorgabe **❓ O-10** (Empfehlung 10 %; Vorgabe 0 % ist möglich).
- **Zusammensetzung:** nach **Kategorieanteilen je Session-Typ** (z. B. 50 % Gel / 30 % Drink / 20 % Riegel). Ohne hinterlegte Anteile verteilt die App nach vorhandenem Bestand (FEFO über alle Kategorien). Anteile sind Nutzer-Einstellungen **❓ O-10**.
- **Algorithmus (Abschnitt 7.4):** Rundung je Kategorie auf ganze Stück/Portionen, danach auffüllen bis Ziel erreicht; Chargen nach FEFO; reicht der Bestand nicht, sagt die App klar „es fehlen ≈ 40 g Carbs“.
- **Abhaken bucht ab (Original):** Das Setzen des Hakens erzeugt eine unveränderliche Buchung (Typ *pack*, −Menge, Charge). **Entfernen des Hakens erzeugt eine Gegenbuchung (Storno)** – ein versehentliches Abhaken darf nie Bestand vernichten.
- **Gepackt ≠ verbraucht [Vorschlag] ❓ O-10:** Nach der Fahrt kann der Nutzer „Rest zurücklegen“ (Buchung *return*, +Menge). Statistik „Verbrauch“ rechnet Rückbuchungen netto.
- **Ablauf einer Packliste:** Entwurf → Packen → Fertig. Eine fertige Packliste ist schreibgeschützt; Korrektur über normale Buchungen.
- **Packliste ohne Session:** frei erstellbar („Ziel: 300 g Carbs“).

### 4.6 Inventarisierungshelfer (Lino 23.11., Entscheidung auf der Karte „Inventarisierungshelfer“: Erstaufnahme und Zählen zusammen)

Lino: „In CarbStock soll es auch einen Inventarisierungshelfer geben.“ Die Spec beschrieb bis dahin keinen Inventurablauf; auf Nachfrage gilt: **Erstaufnahme für Neues, Zähl-Durchgang für Vorhandenes.** Einstieg: Bestand → Symbol „Inventur“. Es gibt **kein neues Datenfeld**; der Helfer nutzt die vorhandenen Buchungen (`purchase` über Charge, `adjust`).

- **Erstaufnahme:** Produkt wählen (oder „Neues Produkt anlegen“, das danach gewählt ist), Menge, optional MHD, „Charge erfassen“. Das Produkt bleibt gewählt, MHD-Einstellung bleibt, die Menge wird geleert: mehrere Chargen am Stück ohne Umweg über die Liste. Unter „Gerade erfasst“ steht, was in dieser Sitzung gebucht wurde. Jede Charge ist eine normale Zugangsbuchung wie bei „Charge hinzufügen“.
- **Zählen:** Pro Produkt mit mindestens einer Charge: erwarteter Bestand (Summe der Buchungen), Feld „Gezählt“, Anzeige der Differenz. Leere Felder bleiben unberührt. „Differenzen buchen“ (mit Bestätigung) bucht **nur die Differenz** als `adjust` mit der Notiz „Inventur“, in einem Schritt. Danach eine Zusammenfassung (angepasst / ohne Abweichung / nicht gezählt). Rückgängig nur per Storno oder Korrektur wie jede Buchung. Produkte ohne Charge erscheinen nicht: Bestand legt man mit der Erstaufnahme an.
- **Verteilung der Differenz auf Chargen** (Annahmen, Core `InventoryCount`, getestet):

| Fall | Regel | Begründung |
|---|---|---|
| Mehr gezählt als erwartet | Zugang auf die erste nutzbare Charge in FEFO-Reihenfolge, sonst auf die erste Charge | Kein neuer Posten ohne Angaben; wie die Schnellbuchung +1 |
| Weniger gezählt | Abzug in FEFO-Reihenfolge über Chargen mit Bestand | Welche Charge fehlt, ist unbekannt; die früheste ist die vorsichtige Annahme |
| Abgelaufene Chargen | werden beim Abzug zuletzt angefasst | Sie tragen die Prognose ohnehin nicht (4.2) |
| Chargen mit negativem Bestand | zählen in die Summe, werden nie weiter verringert | Konflikte (TV-8) löst „Korrektur buchen“ |
| Archivierte Chargen | zählen weder im Soll noch bei der Verteilung | wie überall |
| Gleicher Stand | keine Buchung | nichts doppelt |

---

## 5. Datenmodell (fachlich) **[Konkretisierung des Originals]**

> Das Original-Modell (`Product`, `Session`, `Purchase/Consumption Log`) bleibt erhalten und wird so aufgeteilt, dass Chargen, Einheiten und Bestandsbuchungen sauber abgebildet sind. Feldnamen sind fachlich, nicht Code. Alle Entitäten erfüllen die CloudKit-Regeln aus Abschnitt 9.2.

### 5.1 Entitäten im Überblick

```
Product 1───n Batch 1───n StockMovement
   │                         ▲
   │                         └─ referenziert PackListItem / Session (per UUID, nicht per Beziehung, siehe 9.2)
   └──n PackListItem n───1 PackList ──(UUID)── Session
ShoppingListItem ── PurchaseEvaluation (Gedankenspiel / Verlauf)
WeeklyTemplateEntry, Session   (Trainingsdaten, siehe Abschnitt 11: eigene Behandlung)
AppPreferences (Einstellungen)
```

### 5.2 Product (Produkt-Stammdaten)

| Feld | Typ | Pflicht | Bemerkung |
|---|---|---|---|
| `id` | UUID | ja | vom Client erzeugt |
| `name`, `brand` | Text | Name ja | |
| `flavor` | Text? | nein | Geschmack, additiv ergänzt (23.11.); fehlt in alten Daten und Sicherungen = kein Geschmack |
| `hasCaffeine`, `hasLactate` | Bool (Vorgabe false) | nein | Koffein-/Laktatzusatz, additiv ergänzt (23.11.) mit Vorgabewert; fehlt in alten Daten, Sicherungen und Verlauf = nein |
| `category` | Enum `gel · drink · bar · jelly · homemade` | ja | [Original] |
| `baseUnit` | Enum `piece · gram` | ja | Stück (Gel/Riegel/Jelly) oder Gramm (Pulver) |
| `portionAmount` | Zahl > 0, in `baseUnit` | ja | Stück: 1; Pulver: z. B. 40 g je Portion |
| `carbsPerPortionG` | Zahl > 0 (g) | ja | zentrale Metrik [Original] |
| `glucoseFructoseRatio` | Zahl ≥ 0, Fruktose je 1 Glukose (1:0,8 → 0,8) | nein | [Original, optional] |
| `isArchived` | Bool | ja (false) | Soft Delete |
| `createdAt`, `updatedAt` | Datum | ja | |
| *abgeleitet* | `carbsPerBaseUnit = carbsPerPortionG ÷ portionAmount` | – | nicht gespeichert |

**Barcode/EAN** (für V2-Scan) wird **nicht** in V1 angelegt; das Feld kann später additiv ergänzt werden (CloudKit-Schemata dürfen wachsen, siehe 9.2).

### 5.3 Batch (Charge = ein Kauf bzw. eine MHD-Gruppe)

| Feld | Typ | Pflicht | Bemerkung |
|---|---|---|---|
| `id` | UUID | ja | |
| `productId` | Beziehung → Product | ja (technisch optional wegen CloudKit) | |
| `purchaseDate` | Datum (Tag) | ja | |
| `quantityPurchased` | Ganzzahl in `baseUnit` | ja | Stück oder g |
| `totalPriceCents` | Ganzzahl (Cent) | nein | **Gesamtpreis** dieser Charge inkl. Versandanteil/abzgl. Rabatt **❓ O-13** |
| `currency` | Text (ISO) | ja | MVP: EUR **❓ O-13** |
| `expiryDate` | Kalendertag ohne Uhrzeit/Zeitzone | nein | „gilt bis einschließlich“ |
| `source` | Text | nein | Shop/Aktion (z. B. „Black Friday 2026“) |
| `isArchived` | Bool | ja (false) | |
| *abgeleitet* | `quantityRemaining = Σ delta` der zugehörigen Buchungen | – | **nicht gespeichert** |
| *abgeleitet* | `carbsRemainingG`, `pricePer100gCarbs = totalPrice ÷ (quantityPurchased × carbsPerBaseUnit) × 100` | – | |

### 5.4 StockMovement (Bestandsbuchung) – unveränderlich

| Feld | Typ | Bemerkung |
|---|---|---|
| `id` | UUID | |
| `batchId` | Beziehung → Batch | |
| `type` | Enum | `purchase` (+), `consume` (−), `pack` (−), `return` (+), `expire` (−), `discard` (−), `adjust` (±), `reversal` (Gegenbuchung) |
| `delta` | Ganzzahl, vorzeichenbehaftet, in `baseUnit` | Summe je Charge = Bestand |
| `occurredAt` | Datum+Zeit | Wirkdatum (rückdatierbar) |
| `createdAt` | Datum+Zeit | Erfassungszeit, nie änderbar |
| `idempotencyKey` | Text, nullable | deterministisch, z. B. `pack:<itemId>`, `expire:<batchId>`; verhindert Doppelbuchungen bei Sync (9.3) |
| `reversesMovementId` | UUID, nullable | bei `reversal` |
| `referenceId` | UUID, nullable | PackListItem- oder Session-ID (lose Referenz) |
| `deviceId`, `note` | Text, optional | Fehlersuche bei Konflikten |

**Regeln:**
1. Buchungen werden **nie geändert oder gelöscht** (Ausnahme: „Alle Daten löschen“). Korrektur = `reversal` oder `adjust`.
2. **Bestand ist immer abgeleitet.** Es gibt kein überschreibbares Feld „Menge im Bestand“ (das Original-Feld `amountInStock` wird zur Ansicht).
3. Das Original-Ereignisprotokoll (`buy|consume|expire`) entspricht `purchase|consume|expire`; `pack`, `return`, `discard`, `adjust`, `reversal` sind Ergänzungen **[Vorschlag]**, nötig für Packliste, Storno und Inventurkorrektur.
4. Negativer Bestand wird nicht verhindert (offline gleichzeitig auf zwei Geräten möglich), sondern **sichtbar als Konflikt** geführt (9.3).

### 5.5 Session, Wochenvorlage und Carbs/h

**Session** (Original, optional für Bedarfsrechner):

| Feld | Typ | Bemerkung |
|---|---|---|
| `id` | UUID | |
| `startsOn` | Kalendertag (+ optional Uhrzeit) | [Original `date`] |
| `type` | Enum `vo2 · threshold · z2 · long · recovery` | Original `regen` → Annahme Regeneration **❓ O-07** |
| `durationMinutes` | Ganzzahl > 0 | |
| `carbsPerHourOverride` | Ganzzahl, nullable | leer = Typ-Wert |
| `status` | Enum `planned · done · skipped` | |
| `title`, `note` | Text, optional | z. B. „So-Langfahrt“ |
| `source` | Enum `manual` (V1) `· import` (V2) | |

**Bewusst nicht gespeichert:** Herzfrequenz, Leistung/Watt, FTP, Gewicht, Kalorien, Gesundheitszustand, GPS. Begründung: Abschnitt 11.

**WeeklyTemplateEntry [Vorschlag] ❓ O-08:** Wochentag, `type`, `durationMinutes`, optional `carbsPerHourOverride`, `validFrom`, `validUntil`.

**Carbs/h je Typ:** Voreinstellungen leben **im Code** (Tabelle mit Standardwert + Bereich). Nur **Abweichungen des Nutzers** werden gespeichert (`CarbRateOverride`: `type`, `carbsPerHour`, `updatedAt`; additiv mit Vorgabewert, 23.11.), damit nicht auf jedem Gerät ein eigener Standard-Datensatz entsteht (Doppel-Problem, 9.3). Gibt es für eine Art zwei Datensätze, **gewinnt der jüngere** (`updatedAt`); beim nächsten Schreiben bleibt nur er übrig.

### 5.6 PackList / PackListItem

- **PackList:** `id`, `sessionId` (UUID, optional), `title`, `targetCarbsG`, `reservePercent`, `createdAt`, `state` (`draft · packing · done`).
- **PackListItem:** `id`, `packListId`, `productId`, `batchId` (vorgeschlagene FEFO-Charge), `plannedQuantity`, `plannedCarbsG`.
- **„Ist gepackt“ ist abgeleitet:** Ein Posten gilt als gepackt, wenn die Nettosumme der `pack`/`reversal`-Buchungen mit `referenceId = itemId` ≠ 0 ist. Es gibt **keinen** änderbaren Haken-Zustand, der zwischen zwei Geräten kollidieren kann (9.3).

### 5.7 ShoppingListItem / PurchaseEvaluation

- **ShoppingListItem:** `id`, `productId?`, `freeText?`, `plannedQuantity`, `estimatedTotalPriceCents?`, `state (open · bought · dropped)`.
- **PurchaseEvaluation** (Ergebnisverlauf des Kauf-Entscheiders): Eingabe-Snapshot (Produkt, Menge, Preis, MHD, Horizont), Ergebnis (`verdict`, Begründungszeilen als strukturierte Liste), `userDecision` (`bought · skipped · none`, **vom Nutzer gesetzt**), `createdAt`. Dient der Metrik „Überkauf vermieden“ (Abschnitt 16) und der Nachvollziehbarkeit.

### 5.8 AppPreferences

Farbschwellen, Erinnerungsstufen/-uhrzeit, Kaufhorizont, Reserve %, Kategorieanteile, Währung. Ablage entweder als Singleton-Datensatz oder in iCloud-Key-Value-Speicher **❓ O-24** (Empfehlung: Key-Value-Speicher, weil kleine Einstellungen mit „letzter Schreiber gewinnt“ genügen und das CloudKit-Schema schlank bleibt; im Spike S1 prüfen). **Gerätelokale Einstellungen** (z. B. „Erinnerungen auf diesem Gerät“) werden **nicht** synchronisiert.

### 5.9 Datenmodell-Invarianten (Prüfliste für Tests)

1. Bestand jeder Charge = Σ `delta`; kein Code schreibt ihn direkt.
2. `quantityPurchased` = Summe der `purchase`-Buchungen der Charge (Kontrollrechnung).
3. Jede `reversal` verweist auf eine existierende Buchung; ein Storno wird höchstens einmal je Original gezählt.
4. Zwei Buchungen mit gleichem `idempotencyKey` zählen **einmal** (Lesesicht ignoriert die jüngere).
5. Charge und Produkt mit Buchungen werden nur archiviert.
6. Geldwerte in Cent (Ganzzahl), Mengen in Ganzzahl der Basiseinheit; Carbs je Einheit als Dezimalzahl; Ergebnisse werden **erst bei der Anzeige** gerundet.

---

## 6. Nice-to-have (später) **[Original, unverändert, mit Vorbereitungshinweis]**

| Original-Wunsch | Vorbereitung im V1-Modell | Besonderheit |
|---|---|---|
| **Barcode-/Etiketten-Scan** (Foto der Nährwerttabelle → Carbs/Portion automatisch) | optionales Feld `barcode` additiv nachrüstbar | Kamerazugriff mit Zweckerklärung; V2 |
| **Trainingsplan-Import** (aus Bevel/TP/MyWhoosh) | `Session.source = import` | **Datenschutz-relevant**, falls Daten aus HealthKit kommen (Abschnitt 11.4) |
| **Verlauf & Statistik:** Monatlicher Verbrauch, Kosten pro Monat, Cost-per-gramm-Trend | Buchungen + Chargenpreise reichen als Datenbasis | rein lesend aus vorhandenen Daten |
| **Budget-Modus:** Monatliches Carb-Budget, Ausgaben-Tracking | Chargenpreise vorhanden | neue Entität `Budget` additiv |
| **Mehrere Fahrer / Team-Konto** | alle Entitäten ohne feste Nutzerannahme | möglich über CloudKit-Freigaben; Trainingsdaten anderer Personen sind sensibler (Abschnitt 11) |
| **Selbstgemacht-Rezepte** (Drink-Mixer mit Ziel-Carbs) | Kategorie `homemade` | Rezept erzeugt Charge mit kurzem MHD **❓ O-14** |

---

## 7. Fachliche Regeln und Algorithmen **[Konkretisierung]**

### 7.1 Stichtag, Zeit, Rundung
- „Heute“ und alle MHD-Vergleiche gelten in **Kalendertagen der lokalen Zeitzone**; MHD sind Tage ohne Uhrzeit (kein Zeitzonenfehler beim Reisen).
- Die Uhr wird in der Domänenlogik **eingespeist** (testbar); keine Zugriffe auf die Systemzeit im Rechenkern.
- Angezeigte Reichweite wird **abgerundet** (konservativ), Preise kaufmännisch auf Cent.

### 7.2 Prognose und Reichweite (Verfahren)
1. Tagesbedarf-Reihe ab heute: explizite Sessions des Tages, sonst Wochenvorlage (falls aktiv), sonst „unbekannt“ (Reihe endet).
2. Nutzbare Chargen = nicht archiviert, Restmenge > 0, MHD ≥ Tag (oder bewusst „trotzdem nutzen“).
3. Je Tag: Bedarf nach **FEFO** aus Chargen entnehmen; Chargen mit MHD < Tag werden vorher entfernt (Rest = Verfallsmenge).
4. Ausgabe: Wochen-/Tagesreichweite, Datum, Verfallsmenge je Charge, erste Versorgungslücke.
5. Ist der Bedarf eines Tages unbekannt, endet die Simulation dort; Aussage lautet „mindestens bis …“.

### 7.3 Kauf-Urteil (Regeln in Reihenfolge)
Eingabe: Angebot (Menge `q`, Gesamtpreis `P`, Carbs je Einheit `c`, MHD `e`), Horizont `H` (Vorgabe 84 Tage), Bestand, Bedarfsreihe.

- **R1 Datenlage:** Ist der Bedarf für `H` nicht vollständig bekannt (7.2) → Urteil `nicht beurteilbar`, Begründung „Bedarf nur bis [Datum] bekannt“; Preiskennzahlen werden trotzdem gezeigt.
- **R2 Fehlmenge:** `F = max(0, Bedarf(H) − nutzbarer Bestand(H))` in g Carbs.
- **R3 Gedeckt:** `F = 0` → `nicht kaufen`, Begründung mit Reichweite („Bestand deckt ≈ 15,5 Wochen, Horizont 12 Wochen“). Ausnahme: Schnäppchenregel (O-05), sofern aktiviert.
- **R4 Bedarf vorhanden:** `F > 0` → nützliche Menge `q* = ⌈F ÷ c⌉`. Ist `q ≤ q*` → `kaufen`; ist `q > q*` → `teilweise kaufen (q*)`.
- **R5 Haltbarkeit des Angebots:** Simulation (7.2) mit hinzugefügter Charge. Verfällt dabei mehr als **10 %** der Angebotsmenge unverbraucht **[Annahme, Schwelle O-05]** → Menge senken oder `nicht kaufen`; Begründung nennt die Verfallsmenge.
- **R6 Preis (verändert nie das Bedarfsurteil, nur die Begründung):** Referenzpreis wie 4.4; Zeile „x % günstiger/teurer als dein Median“. Liegt der Preis > 15 % über Referenz **[Annahme]**, wird „nur bei akutem Bedarf“ ergänzt.

### 7.4 Packlisten-Verfahren
1. `Ziel = Bedarf × (1 + Reserve)`.
2. Idealwert je Kategorie = Anteil × Ziel.
3. Stückzahl je Kategorie = Idealwert ÷ Carbs je Stück, **kaufmännisch gerundet**.
4. Solange Summe < Ziel: eine Einheit zur Kategorie mit dem **größten Rest (Ideal − Ist)** hinzufügen (nur bei vorhandenem Bestand).
5. Je Einheit die Charge nach FEFO wählen (bei zu kleiner Charge auf zwei Posten aufteilen).
6. Reicht der Bestand nicht: Fehlbetrag in g Carbs anzeigen, Rest auf andere Kategorien verteilen, soweit möglich.

### 7.5 Rechenbeispiele (Testvektoren für die Domänenlogik)

| ID | Eingabe | Erwartung |
|---|---|---|
| TV-1 | Longride 240 min, 80 g/h | Bedarf **320 g** |
| TV-2 | Bestand 14 000 g Carbs, Bedarf 1 800 g je 2 Wochen (= 900 g/Woche) | Reichweite 15,55 Wochen → angezeigt **15,5 Wochen = 108 Tage** |
| TV-3 | 60 Gele à 0,50 €, 25 g Carbs je Gel | 30,00 € ÷ 1 500 g = **2,00 € je 100 g Carbs** |
| TV-4 | TV-2 + TV-3, Horizont 12 Wochen (Bedarf 10 800 g) | `F = 0` → **nicht kaufen** |
| TV-5 | Chargen A (MHD 01.03.2027, 10 Stück), B (01.09.2027, 10 Stück); Abgang 12 | A: −10, B: −2 (FEFO) |
| TV-6 | 20 Gele à 25 g (500 g), MHD in 14 Tagen, Bedarf 100 g/Woche, sonst kein Bestand | Verbrauch 200 g, **Verfallsmenge 300 g (12 Gele)** |
| TV-7 | Packliste: Ziel 320 g (ohne Reserve), Anteile Gel 50 / Drink 30 / Riegel 20; Gel 25 g, Drink-Portion 40 g, Riegel 30 g | Runden: 6 Gele (150), 2 Drink (80), 2 Riegel (60) = 290 < 320 → größter Rest = Drink (96 − 80 = 16) → +1 Drink: **6 Gele + 3 Drink + 2 Riegel = 330 g** |
| TV-8 | Zwei Geräte buchen gleichzeitig je −1 Gel bei Bestand 1 | nach Sync Bestand **−1**, sichtbarer Konflikt-Hinweis (9.3) |

### 7.6 Duplikate externer Aktivitäten: Grenzen (Entscheidung 23.11.)
Quelle der Grundregel: `docs/TRAININGSQUELLEN.md` AC-X3 (Start ≤ 5 min, Überlappung ≥ 80 %, vereinbare Sportart). Die folgenden Grenzen stehen dort **nicht** und sind eine Entscheidung der Hauptsession (Begründung im Board, Karte „Review-Nacharbeit“); sie sind in `ExternalActivityTests` festgehalten:

| Grenze | Wert | Begründung |
|---|---|---|
| „Vielleicht doppelt“, Überlappung | ab **60 %** (bei Start ≤ 5 min) | AC-X3 nennt „knapp verfehlt“ ohne Zahl; 60 % ist die engste Marke, bei der der Nutzer eine Rückfrage noch als sinnvoll erlebt. Darunter sind es sicher zwei Fahrten. |
| „Vielleicht doppelt“, Startabstand | bis **15 min** (bei Überlappung ≥ 80 %) | Uhr und Radcomputer starten oft Minuten versetzt; mehr als 15 min mit fast gleichem Fenster ist unplausibel für zwei Fahrten, aber ein Zeitzonen- oder Uhrenfehler ist denkbar, daher Rückfrage statt Zusammenführen. |
| Überlappung gegen | das **längere** der beiden Fenster | Gegen das kürzere gemessen würde eine kurze Fahrt mitten in einer langen als „dieselbe“ gelten und fiele still aus der Zählung. Der strengere Maßstab schützt vor verlorenen Fahrten. |
| Dauer 0 | **nie** doppelt, nie „vielleicht“ | Ein Eintrag ohne Dauer hat kein Fenster; ihn mit einer echten Fahrt zusammenzulegen wäre Raten. Er bleibt getrennt sichtbar. |

Grundsatz bleibt: Nichts wird gelöscht; im Zweifel zählen beide, bis der Nutzer entscheidet (AC-X4). Die Werte sind Konstanten im Core (`ActivityMatcher`) und lassen sich ohne Datenänderung anpassen.

---

## 8. Lokale Benachrichtigungen **[Konkretisierung des „Haltbarkeits-Push“]**

**Grundentscheidung:** „Push“ bedeutet hier **lokale Benachrichtigungen** (`UserNotifications`, vom Gerät geplant). Ein Server-Push (APNs) setzt ein Backend voraus, das es nicht gibt. Ein Ablaufdatum ist ohnehin zeitgesteuert, nicht datengesteuert. **[Beleg]** Lokale Zeitplanung per Kalender-Trigger ist offiziell dokumentiert (Quelle 9).

### 8.1 Benachrichtigungsarten
| Art | Auslöser | Status |
|---|---|---|
| **Ablauf-Erinnerung** | Charge mit Restmenge > 0 nähert sich dem MHD | [Original] |
| **Engpass-Warnung** | Reichweite unter Schwelle (z. B. < 4 Wochen bei bekanntem Bedarf) | [Vorschlag] ❓ O-11 |

### 8.2 Regeln der Ablauf-Erinnerung
- **Stufen:** Original „<1–2 Monaten“. Arbeitsannahme: **60 Tage und 30 Tage vor MHD**; am MHD-Tag selbst optional **❓ O-11**.
- **Sammelmeldung:** Pro Auslösetag **eine** Benachrichtigung mit Anzahl und den ersten drei Produkten („3 Chargen laufen bald ab: Gel X, Riegel Y …“), nicht eine je Charge. Tippen öffnet die Verbrauch-zuerst-Liste.
- **Uhrzeit:** Vorgabe 09:00 lokale Zeit, einstellbar.
- **Ohne MHD / Restmenge 0 / archiviert:** keine Erinnerung.
- **Bewusst keine** inhaltlichen Gesundheits- oder Ernährungsempfehlungen in der Meldung.

### 8.3 Planung und Neuplanung
- Benachrichtigungen sind **pro Gerät** (lokal). Jedes Gerät plant sich seine eigenen aus den synchronisierten Daten.
- **Neuaufbau (idempotent):** alte App-Erinnerungen entfernen, aus dem aktuellen Stand neu planen. Auslöser: App-Start, Rückkehr in den Vordergrund, nach einem Sync-Import, nach Änderung von Charge/Buchung/Einstellung, Änderung der Berechtigung.
- **Fenster:** Es wird nur eine begrenzte Zahl der **nächsten** Termine geplant (Vorgabe ≤ 50). **[Nicht belegt]** In Entwicklerforen wird für lokale Benachrichtigungen ein Limit von 64 ausstehenden Anfragen genannt; in Apples Dokumentation, die ich abgerufen habe, steht diese Zahl nicht. Das Fenster ist deshalb eine Vorsichtsmaßnahme; das tatsächliche Verhalten wird auf einem Gerät im Spike S3 geprüft.
- **Kein Hintergrundlauf nötig:** Fehlt zwischendurch ein Sync-Import, kommt die Erinnerung zum zuletzt bekannten Stand; die Neuplanung erfolgt beim nächsten Öffnen. **Grenze:** Wird eine Charge auf dem Gerät A verbraucht und Gerät B ist lange nicht geöffnet, kann B noch eine veraltete Erinnerung auslösen. Deshalb sagt die Meldung „Chargen prüfen“, nicht „X ist noch da“.

### 8.4 Berechtigung und Verweigerung
- Die Berechtigung wird **erst bei Aktivierung der Erinnerungen** erfragt (nicht beim ersten Start).
- **[Beleg]** Die App-Review-Regel 5.1.2(i) verlangt, dass Apps nicht erzwingen, Systemfunktionen wie Push-Benachrichtigungen zu aktivieren, um Funktionen nutzen zu können. Folge: Bei „Nicht erlaubt“ bleibt alles nutzbar; die In-App-Anzeige „Läuft bald ab“ ist die Rückfalllösung, und die Einstellungen zeigen eine Anleitung zu den Systemeinstellungen.
- **Mehrere Geräte:** iPhone und iPad würden doppelt erinnern. Geräteschalter „Erinnerungen auf diesem Gerät“ (lokal, nicht synchronisiert), Vorgabe an auf dem ersten Gerät **❓ O-11**.
- **Aktionen an der Meldung** (z. B. „Morgen erinnern“): [Vorschlag], nicht im MVP.

---

## 9. Offline und iCloud-Synchronisation **[Konkretisierung]**

### 9.1 Architektur
- Lokale Datenbank = **Wahrheitsquelle**; die App funktioniert ohne Netz vollständig.
- **[Beleg]** SwiftData synchronisiert über die Core-Data-Klasse `NSPersistentCloudKitContainer` mit dem **privaten CloudKit-Bereich** des Nutzers; nötig sind die Capabilities **iCloud (CloudKit)** und **Background Modes → Remote notifications**, damit CloudKit stille Änderungsmeldungen zustellt (Quellen 5, 6).
- Es gibt **nur den privaten Bereich**; keinen öffentlichen CloudKit-Bereich und keine Server des Entwicklers. Der Entwickler betreibt dafür keinen Server. **[Nicht belegt]** Ob und wie der Entwickler über das CloudKit-Dashboard auf Nutzerdaten im privaten Bereich zugreifen kann, habe ich nicht geprüft (relevant für die Datenschutzangaben, 10.2).

### 9.2 Schema-Regeln für CloudKit-Tauglichkeit **[Beleg: Quelle 5, 7]**
1. **Keine Unique-Constraints.** Eindeutigkeit (z. B. „ein Produkt je Name“) lässt sich nicht erzwingen; Duplikate sind möglich und werden in der App behandelt (9.3).
2. **Alle Beziehungen optional**, mit **Gegenbeziehung**; die Lösch-Regel „Deny“ gibt es nicht. CloudKit speichert Beziehungsänderungen nicht zwingend atomar.
3. **Keine Beziehungen zwischen Entitäten verschiedener Konfigurationen** (relevant für 11.5: Trainingsdaten, falls lokal-only, referenzieren Chargen/Packlisten nur per UUID).
4. **Schema nur additiv:** Nach der Veröffentlichung (Promotion Entwicklung → Produktion) können Satztypen und Felder weder umbenannt noch gelöscht werden. Neue Felder/Typen sind erlaubt. Folge: Feldnamen sorgfältig wählen; Versionsfeld (`schemaVersion`) von Anfang an; keine „vorsorglichen“ Felder.
5. **Entwicklungs-Schema muss vor dem Release in die Produktion überführt werden** (CloudKit-Dashboard). Das ist ein bewusster Freigabeschritt (Abschnitt 17, M7), kein Nebenbei.

### 9.3 Konflikte: Strategie **[Konkretisierung, fachlich]**
**Was belegt und was nicht:** Für rohe CloudKit-Speicherungen ist ein Konfliktfehler (`serverRecordChanged`) mit lokaler, Server- und Ursprungsversion dokumentiert (Quelle 8). **Wie die Spiegelung (`NSPersistentCloudKitContainer`) Konflikte feldweise oder satzweise auflöst, steht in den von mir geprüften Apple-Seiten nicht (auch nicht in TN3163, Quelle 10).** **[Nicht belegt]** Deshalb baut das Modell nicht auf eine bestimmte Auflösungsart, sondern **vermeidet Konflikte durch Entwurf**:

| Problem | Maßnahme |
|---|---|
| Zwei Geräte ändern denselben Bestand | **Append-only Buchungen**: zwei neue Buchungen kommen beide an und addieren sich (kommutativ). Kein „überschriebener Zähler“. |
| Gleiche Buchung wird auf zwei Geräten erzeugt (z. B. „abgelaufen“ buchen, Haken beim Packen) | **`idempotencyKey`**: Lesesicht zählt je Schlüssel nur die älteste Buchung. |
| Haken „gepackt“ kollidiert | Zustand **abgeleitet** aus Buchungen (5.6), kein änderbares Flag. |
| Bestand wird negativ (zwei Geräte buchen den letzten Gel ab) | Anzeige „Bestand −1 (Konflikt)“, Hinweis mit Vorschlag „Korrektur buchen“; nie stilles Abschneiden auf 0. |
| Produkt/Charge-Stammdaten (Name, Carbs, MHD) werden gleichzeitig bearbeitet | selten; „letzter Schreiber gewinnt“ wird akzeptiert. Änderungen an **Carbs je Portion** und **MHD** zeigen im Verlauf `updatedAt`; Warnhinweis, wenn sich beide Werte nach einem Sync unerwartet ändern, ist [Vorschlag]. |
| Doppelt angelegte Produkte (zwei Geräte, kein Unique-Constraint) | **Zusammenführen** durch den Nutzer (Hinweis bei gleichem Namen+Marke+Geschmack+Zusätzen); Buchungen wandern auf das Zielprodukt. |
| Standardwerte doppelt angelegt | **Nicht synchronisiert anlegen**: Standard-Carbs/h liegen im Code, nur Nutzer-Abweichungen sind Datensätze (5.5). |
| Löschen auf Gerät A, Bearbeiten auf Gerät B | Soft-Delete (`isArchived`), kein hartes Löschen; Archivierung gewinnt und ist umkehrbar. |

### 9.4 Löschen
Archivieren statt Löschen für Produkt und Charge; Buchungen werden nie einzeln gelöscht. „Alle Daten löschen“ (Abschnitt 11.6) löscht lokal und in iCloud.

### 9.5 Betrieb, Fehlerfälle, Zustände
| Situation | Verhalten (Soll) |
|---|---|
| Kein iCloud-Konto / eingeschränkt | App läuft **rein lokal** weiter, sichtbarer Hinweis „Nicht synchronisiert – iCloud nicht verfügbar“, Anleitung zur Anmeldung; keine Fehlschleife |
| Konto gewechselt/abgemeldet | **[Nicht belegt]** Verhalten des Speichers bei Kontowechsel wird im Spike S1 getestet; Soll: keine Vermischung zweier Konten, klare Meldung; Export-Empfehlung vor dem Wechsel |
| iCloud-Speicher voll | **[Beleg Quelle 8]** `quotaExceeded` im privaten Bereich: Der Nutzer hat nicht genug iCloud-Speicher; die App weist auf die iCloud-Speicherverwaltung hin und arbeitet lokal weiter |
| Kein Netz | alles lokal; Änderungen werden nachgeliefert |
| Erstes Einrichten eines zweiten Geräts | Erstimport kann dauern; Hinweis „Daten werden geladen“; keine Standarddaten anlegen, solange der Erstimport läuft |
| Neues App-Schema in älterer App-Version | Versionsfeld verhindert, dass ältere Versionen unbekannte Daten falsch lesen; Hinweis „Bitte App aktualisieren“ |
| Sync-Status in der Oberfläche | Umfang hängt vom gewählten Framework ab **❓ O-03**; Mindestanforderung: „iCloud verfügbar ja/nein“ und Zeit der letzten bekannten Änderung |

### 9.6 Sicherung unabhängig von iCloud **[Vorschlag] ❓ O-17**
**Export/Import (JSON, plus CSV der Buchungen)** als manuelle Sicherung und Ausweg bei Sync-Problemen. Original Abschnitt 6 hält „Lokal + Import/Export“ selbst für ausreichend. Import ist idempotent (gleiche IDs werden nicht verdoppelt). Empfehlung: in V1.

### 9.7 Risiken des iCloud-Wegs (ehrlich)
- Sync-Fehler lassen sich ohne eigenes Backend nur eingeschränkt beobachten (kein Server-Log); Fehlersuche über CloudKit-Dashboard/Konsole und Geräte-Logs.
- Schema ist nach Produktionsfreigabe nicht mehr umbaubar (9.2) → Datenmodell vor Release gründlich testen.
- Konfliktverhalten der Spiegelung ist nicht dokumentiert (9.3) → Entwurf vermeidet Abhängigkeit; Spike S1 prüft es praktisch.

---

## 10. Datenschutz **[Konkretisierung]**

### 10.1 Datenbestand und Einstufung
| Daten | Gesundheitsbezug | Wohin |
|---|---|---|
| Produkte, Chargen, Preise, MHD, Einkaufsliste | **keiner** | lokal + iCloud |
| Bestandsbuchungen | gering (zeigt, was gepackt/verbraucht wurde) | lokal + iCloud |
| Sessions (Datum, Typ, Dauer, g/h), Wochenvorlage | **Grauzone** (Fitness-Planung) | **❓ O-01** |
| Packlisten (Bezug zu Sessions) | Grauzone, weil sie Sessionzeitpunkte spiegeln | wie O-01 |
| Einstellungen | keiner | lokal/iCloud |
| HealthKit/Bewegungsdaten | **ja** | ab M9c **nur gelesen**: Radfahrten (Beginn, Dauer), lokal im Store „Imports“, nie iCloud/Export/Backup; Regeln in 11.4 und `docs/TRAININGSQUELLEN.md` |

### 10.2 Grundsätze
- **Keine** Telemetrie, kein Analytics, keine Werbung, kein Tracking, keine Drittanbieter-SDKs (Konsequenz: kein App-Tracking-Transparency-Dialog nötig).
- **Datensparsamkeit:** Es werden keine Gewichts-, Puls-, Leistungs-, Gesundheits-, Standort- oder Kontaktdaten erfasst. **[Beleg]** App-Review-Regel 5.1.1(iii): nur Zugriff auf Daten, die für die Kernfunktion relevant sind.
- **Datenschutzerklärung:** **[Beleg]** Regel 5.1.1(i): Jede App braucht einen Link zur Datenschutzerklärung in den App-Store-Connect-Metadaten **und** in der App. Inhalt: welche Daten, wo gespeichert (Gerät, iCloud des Nutzers), keine Weitergabe, Aufbewahrung/Löschung, wie man Daten löscht (Abschnitt 11.6).
- **Impressum/Händlerstatus** bei öffentlicher Veröffentlichung: vor der Veröffentlichung zu klären; **hier nicht geprüft**, keine Rechtsberatung.
- **Datenschutz-Etikett (App Privacy):** **[Beleg]** Apple definiert „Erheben“ als Übertragen von Daten vom Gerät so, dass Entwickler oder Drittpartner darauf zugreifen können; nur auf dem Gerät verarbeitete Daten sind nicht anzugeben (Quelle 3). Da der Entwickler weder Server noch Zugriff auf den privaten iCloud-Bereich nutzt, ist „Data Not Collected“ nach dieser Definition **wahrscheinlich** zutreffend. Die verbindliche Antwort gibt Lino in App Store Connect nach erneuter Prüfung der Definition; **ich habe nicht belegt**, dass Apple den privaten iCloud-Bereich ausdrücklich so einstuft. Zudem führt Apples Etikett „Health“ und „Fitness“ als **getrennte** Datenkategorien (Quelle 3); wie Planungsdaten zu Sessions einzustufen wären, ist offen (O-01).
- **Benachrichtigungen:** freiwillig, kontextuell erfragt (8.4).
- **Haftungshinweis:** Carbs/h-Werte sind Planungs-Voreinstellungen, **keine medizinische oder ernährungsberatende Empfehlung**; Hinweis in den Einstellungen/Über-Seite. Die App gibt keine Dosierungsempfehlung als Gesundheitsaussage.
- **Keine Schreibzugriffe auf HealthKit** in V1 und V2 ohne neue Prüfung. **[Beleg]** Regel 5.1.3(ii): keine falschen oder ungenauen Daten in HealthKit schreiben. Ein Haken beim Packen ist kein Verzehr; eine Ernährungsbuchung daraus wäre ungenau.

---

## 11. Apple-Vorgaben: Gesundheitsdaten und iCloud **[Beleg-geprüft, 2026-11-21]**

### 11.1 Was die offiziellen Texte wörtlich sagen
1. **App Review Guidelines 5.1.3 (ii) [Beleg Quelle 1]:** „Apps must not write false or inaccurate data into HealthKit or any other medical research or health management apps, **and may not store personal health information in iCloud**.“ Der Satz nennt keine Ausnahme, auch keine für Verschlüsselung.
2. **App Review Guidelines 5.1.3 (i) [Beleg Quelle 1]:** Daten aus dem Gesundheits-, Fitness- und Medizinforschungsbereich (u. a. HealthKit, Motion & Fitness) dürfen nicht für Werbung, Marketing oder sonstiges nutzungsbasiertes Data-Mining verwendet oder an Dritte weitergegeben werden, außer zur Verbesserung des Gesundheitsmanagements oder für Gesundheitsforschung und dann nur mit Erlaubnis; die konkret erhobenen Gesundheitsdaten sind offenzulegen.
3. **Developer Program License Agreement, Abschnitt 3.3.3 (D) [Beleg Quelle 2]:** Sofern Apple es nicht ausdrücklich schriftlich erlaubt, darf man Apple-Software oder -Dienste „(including iCloud, the iCloud Storage APIs, CloudKit APIs …)“ **nicht** nutzen, um „**sensitive, individually-identifiable health information**, including ‚protected health information‘ (45 C.F.R § 160.103)“ zu erstellen, zu empfangen, zu speichern oder zu übertragen. Der Vertrag enthält also eine Möglichkeit der **schriftlichen Ausnahme durch Apple**.
4. **DPLA 3.3.3 (H) [Beleg Quelle 2]:** HealthKit- und Motion-&-Fitness-Daten nur für Gesundheits-/Bewegungs-/Fitnessleistungen verwenden, nicht für Werbung, nicht an Dritte ohne ausdrückliche Zustimmung.

### 11.2 Was die Texte **nicht** sagen (Grenzen der Aussage)
- Keine der Quellen **definiert „personal health information“** für Fitness- oder Ernährungsplanung. Die Review-Regel nennt Gesundheit **und** Fitness im Abschnittstitel und in 5.1.3(i), in 5.1.3(ii) aber nur „personal health information“. Der Vertrag verwendet „sensitive, individually-identifiable health information“ mit Verweis auf die US-Definition geschützter Gesundheitsdaten.
- Ich habe **keine Quelle gefunden, die iCloud für Fitness- oder Trainingsdaten pauschal verbietet**, und **keine, die sie für Trainingsdaten ausdrücklich erlaubt**. Eine pauschale Ablehnung („kein iCloud bei Fitness-Apps“) ist durch die Texte **nicht gedeckt**; eine pauschale Freigabe ebenso wenig.
- Apple kennzeichnet CloudKit-**verschlüsselte Felder** (Quelle 11) als zusätzlichen Schutz für sensible Daten. **Ob Apple sie als Ausnahme von 5.1.3(ii) wertet, steht nirgends** → nicht als Lösung annehmen.
- Im Nachschlagen fand ich eine Forendiskussion, ob private CloudKit-Bereiche ausgenommen sind; es gibt dort keine verbindliche Antwort von Apple. Das ist **keine Quelle**.

### 11.3 Anwendung auf diese App (Einstufung)
| Datenart | Einstufung nach den Texten | Konsequenz |
|---|---|---|
| Produkte, Chargen, Preise, MHD, Einkaufsliste | **keine Gesundheitsdaten** | Sync unkritisch |
| Bestandsbuchungen (verbraucht/gepackt) | nach meiner Auslegung **keine Gesundheitsdaten**; geben aber Hinweis auf Trainingsverhalten | Sync vorgesehen, in O-01 mit entschieden |
| Session-Planung (Datum, Typ, Dauer, g/h) | **unklar**: Fitness-nah, aber keine Messdaten, keine Diagnose, kein Körperbezug | **❓ O-01** |
| Körper-/Medizindaten (Gewicht, Puls, Blutzucker, Diagnosen), HealthKit-Daten | **eindeutig Gesundheitsdaten** | **nicht in iCloud** (Regel 5.1.3(ii)); im Produkt **nicht erfassen** |

### 11.4 Folgen für V2-Importe (Trainingsplan-Import)
- Stammen Trainingsdaten aus **HealthKit** (z. B. über eine Gesundheits-App-Anbindung): nur lokal speichern, **nie** in den CloudKit-gespiegelten Speicher, nicht an Dritte, nicht für Marketing (5.1.2(vi), 5.1.3(i), DPLA H). Nutzungszweck muss im Marketingtext und in der Oberfläche ersichtlich sein (DPLA H).
- Stammen sie aus **Plattform-APIs/Dateien** (TrainingPeaks, MyWhoosh): Datenschutz der jeweiligen Anbieter und deren Nutzungsbedingungen **separat prüfen**; **hier nicht geprüft**.
- Aus Gesundheitsdaten **abgeleitete** Werte (z. B. Wochenbedarf) bleiben im Zweifel ebenfalls lokal, bis O-01 geklärt ist.

### 11.5 Optionen für Sessions-Sync (Grundlage von O-01)
| Option | Inhalt | Chancen | Risiken |
|---|---|---|---|
| **A** Alles synchronisieren | Sessions, Wochenvorlage, Buchungen in iCloud | volle Mehrgeräte-Funktion | möglicher Konflikt mit 5.1.3(ii)/DPLA 3.3.3(D), da Einstufung unklar; Ablehnungs- oder Vertragsrisiko |
| **B** Trainingsdaten nur lokal | Sessions/Wochenvorlage in **eigener lokaler Konfiguration** (kein CloudKit); Bestand, Chargen, Packlisten per iCloud | Rechtsrisiko minimal; Inventar-Sync voll nutzbar | Sessions erscheinen nicht auf dem zweiten Gerät; Prognose dort nur mit lokal eingetragenen Sessions; Beziehungen zwischen den Konfigurationen nur per UUID (Regel 9.2.3) |
| **C** Apple schriftlich fragen | Anfrage an Apple (Developer Support / App Review) zur Einstufung von Trainings-Planungsdaten | Klarheit, ggf. schriftliche Ausnahme (Vertrag sieht diese Möglichkeit vor) | Dauer; Antwort kann „nicht erlaubt“ sein |

**Empfehlung (nicht festgelegt):** **B als Startzustand**, **C parallel** (Anfragetext als Entwurf in Anhang C, **nicht gesendet**), Wechsel auf A nur nach schriftlicher Klärung. Die Architektur trennt Trainingsdaten von Anfang an so, dass der Wechsel eine Konfigurationsänderung statt eines Umbaus ist (die Trennung muss **vor** Veröffentlichung entschieden sein, weil das Schema danach nicht mehr verkleinert werden kann, 9.2.4: einmal in Produktion promotete Satztypen bleiben bestehen).

### 11.6 Löschung und Betroffenenrechte
- **Daten löschen in der App:** Funktion „Alle Daten löschen“ löscht lokal **und** in iCloud (technischer Weg im Spike S1 zu prüfen; erwartet über die Löschfunktionen des CloudKit-Containers). **[Beleg]** Regel 5.1.1(v) verlangt In-App-Kontolöschung, wenn die App **Konten** anlegt; hier gibt es keine App-Konten (iCloud ist das Systemkonto), die Funktion ist dennoch für Datenschutzerklärung und Vertrauen vorgesehen.
- **Export** der eigenen Daten (9.6) dient auch der Datenportabilität.

### 11.7 Veröffentlichung: Hinweise aus den Review-Regeln
- App-Name höchstens 30 Zeichen **[Beleg Regel 2.3.7]**; kein Preis/Marken im Namen.
- Metadaten, einschließlich der Datenschutzangaben, müssen den tatsächlichen Funktionen entsprechen **[Beleg Regel 2.3]**.
- Berechtigungstexte (`Info.plist`-Zwecktexte) klar formulieren **[Beleg Regel 5.1.1(ii)]**.
- Ob die App öffentlich im App Store erscheint oder nur privat per TestFlight/Xcode läuft, ist **❓ O-18** und bestimmt den Umfang von Review-, Impressum- und Datenschutzpflichten.

---

## 12. MVP-Abgrenzung (was NICHT in V1) **[Original, mit Anpassung]**

- Keine Zahlungs-/Shop-Integration.
- Keine OCR/Barcode-Erkennung (V2).
- Keine komplexe Multi-User-Rechte.
- ~~Keine Offline-Multi-Geräte-Sync-Komplexität (reicht simple Cloud oder Lokal + Import/Export).~~ **Geändert:** Auf Vorgabe von Lino ist **iCloud-Sync über CloudKit im MVP**. Die Komplexität wird durch den buchungsbasierten Entwurf (9.3) klein gehalten; ein eigenes Sync-System wird **nicht** gebaut. Export/Import bleibt als Rückfall (9.6).
- **[Vorschlag, zur Bestätigung]** Ebenfalls nicht in V1: Android, Web, Apple Watch, Widgets, Siri/Kurzbefehle, Mac, Team-Freigaben.
- **HealthKit (Stand 23.11., ersetzt „nicht in V1“):** Ab M9c liest die App Radfahrten aus Apple Health, **nur lesen** (Beginn, Dauer, Sportart), lokal im Store „Imports“, nie in iCloud, Sicherung oder Export (Abschnitte 10, 11.3, 11.4). Geschrieben wird weiter **nichts** in HealthKit (AC-D6). Strava bleibt nachrangig (M9b, `docs/TRAININGSQUELLEN.md`).

---

## 13. Quellen (abgerufen 2026-11-21)

Offiziell (Apple):
1. App Review Guidelines (5.1.1, 5.1.2, 5.1.3, 2.3, 2.3.7) – https://developer.apple.com/app-store/review/guidelines/
2. Apple Developer Program License Agreement (Abschnitt 3.3.3 D und H; Stand der abgerufenen Seite, Versionsdatum nicht ermittelt) – https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
3. App Privacy Details (Definition „Collect“, Kategorien Health und Fitness getrennt) – https://developer.apple.com/app-store/app-privacy-details/
4. Health and fitness apps (Übersicht) – https://developer.apple.com/health-fitness/
5. SwiftData: Syncing model data across a person’s devices – https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
6. Core Data: Setting up Core Data with CloudKit – https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit
7. Core Data: Creating a Core Data model for CloudKit (Schema-Einschränkungen, additive Schemata) – https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit
8. CloudKit: `CKError.serverRecordChanged` und `quotaExceeded` – https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged · https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded
9. UserNotifications: Scheduling a notification locally from your app – https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
10. TN3163: Understanding the synchronization of NSPersistentCloudKitContainer – https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer
11. CloudKit: Encrypting user data – https://developer.apple.com/documentation/cloudkit/encrypting-user-data

Inoffiziell (nur als Hinweis, **nicht belegend**): Entwicklerforen zum Limit von 64 ausstehenden lokalen Benachrichtigungen, z. B. https://developer.apple.com/forums/thread/811171 und https://developer.apple.com/forums/thread/682509.

**Nicht geprüft:** deutsches Recht (Impressum, DSGVO-Bewertung), Datenschutzbedingungen von TrainingPeaks/MyWhoosh/Bevel, US-Gesundheitsrecht (HIPAA) im Detail, Steuer-/Gewerbefragen, ob Lino persönlich oder gewerblich veröffentlicht.

---

## 14. Beispiel-Szenario (aus dem echten Use-Case) **[Original, mit Rechenprobe]**

**Original:**
> **Status:** Vorrat = 100 Gele, 8–10 kg Pulver, 30–40 Riegel ≈ 14 kg Carbs. Bedarf 2 Wochen ≈ 1,8 kg.
> **App-Aussage:** „Reicht für ~8 Monate. Es droht KEIN Engpass. Kauf nicht nötig.“
> **Black-Friday-Input:** „60 Gele à 0,50 €, MHD 2028.“
> **App-Urteil:** „Kauf überflüssig – Bestand deckt den Bedarf; kein Haltbarkeits-Risiko. Nur sinnvoll, wenn du ein anderes Verhältnis testen willst.“

**Rechenprobe (Befund):**
- 14 kg ÷ 1,8 kg je 2 Wochen = 7,8 Zwei-Wochen-Blöcke ≈ **15,6 Wochen ≈ 3,6 Monate**, nicht „~8 Monate“. Für 8 Monate (~35 Wochen) müsste der Bedarf bei etwa 0,4 kg/Woche (0,8 kg je 2 Wochen) liegen.
- Plausibilität des Vorrats: 8–10 kg **Pulver** sind Masse, nicht Carbs; bei ca. 90 % Carbs-Anteil sind es 7–9 kg Carbs, dazu 100 Gele (≈ 2–4 kg) und 30–40 Riegel (≈ 0,8–1,8 kg): zusammen 10–15 kg. „≈ 14 kg“ liegt am oberen Ende. Die App rechnet aus den erfassten Produktdaten, nicht aus Schätzungen.
- Der Bedarf 1,8 kg/2 Wochen passt zur Persona (z. B. 12 h/Woche × 75 g/h ≈ 0,9 kg/Woche).

**Folgerungen:**
- Mit den **genannten Zahlen** gilt: Reichweite ≈ **15,5 Wochen**. Mit Kaufhorizont **12 Wochen** (O-05) ergibt sich „**kein Fehlbedarf → Kauf nicht nötig**“ (Testvektoren TV-2 bis TV-4). Die Schlussaussage des Autors bleibt damit erhalten; nur die Begründung „8 Monate“ nicht.
- Mit Kaufhorizont **26 Wochen** (6 Monate) würde dasselbe Angebot als „teilweise sinnvoll“ gelten (Fehlbedarf ≈ 9,4 kg) – der Horizont entscheidet also über das Urteil und ist deshalb eine echte Produktentscheidung (O-05).
- Das Angebot (60 Gele × 25 g = 1,5 kg Carbs für 30 €, **2,00 € je 100 g Carbs**) ist im Verhältnis zum Bedarf ≈ 1,7 Wochen Training.
- Die Bemerkung „Nur sinnvoll, wenn du ein anderes Verhältnis testen willst“ verlangt, dass die App das Glucose/Fructose-Verhältnis des Angebots mit dem Bestand vergleichen kann (Feld ist optional, 5.2) → Zusatzzeile im Urteil, wenn beide Verhältnisse bekannt sind **[Vorschlag]**.
- **❓ O-06:** Lino bestätigt die tatsächlichen Werte (Bedarf je Woche, Vorrat), damit das Beispiel als Abnahmefall taugt.

---

## 15. Akzeptanzkriterien (Abnahme)

Format: **Gegeben / Wenn / Dann**. Zahlen entsprechen den Testvektoren (7.5). „Gerät“ = echtes iPhone/iPad mit iCloud-Konto, soweit nichts anderes steht.

### 15.1 Bestand (F-BEST)
- **AC-B1** Gegeben ein Pulverprodukt (Portion 40 g, 36 g Carbs), wenn 1 000 g als Charge für 25,00 € erfasst werden, dann zeigt die App Carbs gesamt 900 g und 2,78 € je 100 g Carbs (25 € ÷ 900 g ≈ 0,0278 €/g).
- **AC-B2** Gegeben zwei Chargen desselben Produkts mit unterschiedlichem MHD, dann erscheinen beide getrennt in der Detailansicht; die Summe stimmt mit der Listenzahl überein.
- **AC-B3** Wenn ich „−1“ am Produkt tippe, wird die Charge mit dem **frühesten** MHD belastet (TV-5).
- **AC-B4** Wenn ich ein Produkt mit Buchungen „lösche“, wird es archiviert; Buchungen bleiben; es erscheint nicht in Listen, ist aber über „Archiv“ wiederherstellbar.
- **AC-B5** Suche nach „gel“ findet Name und Marke unabhängig von Groß-/Kleinschreibung; Filter Kategorie und „läuft in ≤ 60 Tagen ab“ liefern die erwarteten Treffer.
- **AC-B6** Ohne Preis erscheint keine €-Kennzahl; ohne MHD zeigt die Charge „ohne MHD“ (grau).
- **AC-B7** Zwei Geräte, Bestand 1, beide buchen offline −1, dann nach Sync Bestand −1 mit sichtbarem Konflikt-Hinweis und Korrekturvorschlag (TV-8).

### 15.2 Haltbarkeit (F-MHD)
- **AC-H1** MHD in 7 Monaten → grün; in 5 Monaten → gelb; in 2 Monaten → rot; gestern → abgelaufen. Jeder Status hat zusätzlich Symbol und Text.
- **AC-H2** Am MHD-Tag selbst gilt die Charge noch als nicht abgelaufen („letzter Tag“).
- **AC-H3** „Verbrauch zuerst“ sortiert abgelaufen → früheste MHD → ohne MHD; Chargen mit Restmenge 0 erscheinen nicht.
- **AC-H4** Abgelaufene Charge zählt nicht zum Prognosebestand; „trotzdem nutzen“ macht sie wieder zählbar; „Entsorgen“ erzeugt eine `expire`-Buchung mit Restmenge.
- **AC-H5** Reiseszenario: Zeitzonenwechsel ändert die Restlaufzeit **nicht** um einen Tag (MHD ist Kalendertag).

### 15.3 Benachrichtigungen (Abschnitt 8)
- **AC-N1** Berechtigung wird nicht beim Start, sondern beim Einschalten der Erinnerungen erfragt.
- **AC-N2** Bei „Nicht erlaubt“ funktioniert die App unverändert; „Läuft bald ab“ ist in der App sichtbar; Einstellungen zeigen den Weg zu den Systemeinstellungen.
- **AC-N3** Bei MHD in 60 bzw. 30 Tagen werden Erinnerungen zur eingestellten Uhrzeit geplant; mehrere Chargen am selben Tag ergeben **eine** Sammelmeldung.
- **AC-N4** Wird die letzte Einheit einer Charge verbraucht, entfällt deren Erinnerung nach der nächsten Neuplanung; archivierte oder abgelaufene Chargen lösen keine neue Erinnerung aus.
- **AC-N5** Nach einem Sync-Import und beim App-Start werden die Erinnerungen vollständig neu geplant (keine Dubletten, kein Verlust).
- **AC-N6** Es sind nie mehr als N Erinnerungen gleichzeitig geplant (Spike S3 bestimmt N und belegt das Verhalten auf dem Gerät).
- **AC-N7** Der Geräteschalter „Erinnerungen auf diesem Gerät“ wird nicht synchronisiert.

### 15.4 Bedarf und Prognose (F-BEDARF)
- **AC-P1** Longride 240 min mit 80 g/h ergibt 320 g (TV-1); Überschreiben des Werts in der Session gilt nur für diese Session.
- **AC-P2** Prognosefenster 7/28/84 Tage zeigen Bedarf, nutzbaren Bestand, Differenz und Ampel; Summen stimmen mit den Sessions und der Wochenvorlage überein.
- **AC-P3** Bei Bestand 14 000 g und Bedarf 900 g/Woche lautet die Aussage „reicht ≈ 15,5 Wochen (bis [Datum = heute + 108 Tage])“ (TV-2).
- **AC-P4** Ohne Sessions und ohne Wochenvorlage zeigt die App **keine** Reichweite, sondern „Bedarf unbekannt – bitte Sessions oder Wochenvorlage eintragen“.
- **AC-P5** Fehlt der Bedarf ab einem Datum, lautet die Aussage „mindestens bis …“.
- **AC-P6** Bei 500 g Gelen mit MHD in 14 Tagen und 100 g/Woche Bedarf zeigt die App ein Verfallsrisiko von 300 g (12 Gele) (TV-6).
- **AC-P7** Die Versorgungslücke wird benannt, wenn nutzbarer Bestand vor dem Bedarfsende endet, weil Ware ablief.

### 15.5 Kauf-Entscheider (F-KAUF)
- **AC-K1** TV-4: Bestand 14 000 g, Bedarf 900 g/Woche, Horizont 12 Wochen → Urteil „nicht kaufen“, Begründung mit Reichweite und Regel R3.
- **AC-K2** Bei Fehlbedarf 1 000 g und Angebot über 3 000 g Carbs → „teilweise kaufen (Menge für ≈ 1 000 g)“.
- **AC-K3** Ohne Bedarfsdaten → „nicht beurteilbar“; Preiskennzahl (€/100 g Carbs) wird trotzdem angezeigt.
- **AC-K4** Mit Referenzpreis (≥ 2 Käufe desselben Produkts) zeigt die Begründung den Abstand in Prozent zum Median; ohne Referenz erscheint keine Prozentangabe.
- **AC-K5** Das Urteil ändert keinen Bestand und erzeugt keine Charge, bis „Gekauft“ bestätigt ist; „Gekauft“ erzeugt Charge + Kaufbuchung.
- **AC-K6** Bei Angebots-MHD, dessen Verbrauch zu mehr als 10 % Verfall führt, wird Menge gesenkt oder „nicht kaufen“ mit Angabe der Verfallsmenge.
- **AC-K7** Jede Begründung enthält Zahlen und Regelnummer; Wiederholen der gleichen Eingabe ergibt dasselbe Ergebnis (Determinismus).

### 15.6 Packliste (F-PACK)
- **AC-L1** TV-7: gleiche Eingaben liefern „6 Gele + 3 Drink + 2 Riegel (330 g)“.
- **AC-L2** Das Abhaken eines Postens erzeugt genau **eine** Buchung (`pack`); Entfernen des Hakens erzeugt genau **eine** Gegenbuchung; mehrfaches Umschalten hinterlässt eine nachvollziehbare Reihenfolge, der Bestand stimmt am Ende.
- **AC-L3** Wird dieselbe Packliste auf zwei Geräten abgehakt, entsteht dank `idempotencyKey` keine Doppelbuchung.
- **AC-L4** Reicht der Bestand nicht, nennt die App den Fehlbetrag in g Carbs und verteilt auf andere Kategorien, wenn möglich.
- **AC-L5** FEFO: Der Posten verweist auf die Charge mit dem frühesten MHD; reicht diese nicht, wird auf zwei Posten aufgeteilt.
- **AC-L6** „Rest zurücklegen“ erzeugt `return`-Buchungen; die Statistik „Verbrauch“ rechnet netto.

### 15.7 Synchronisation und Offline (Abschnitt 9)
- **AC-S1** Ohne Netz sind alle Funktionen nutzbar; nach Rückkehr des Netzes erscheinen die Änderungen auf dem zweiten Gerät (Zeitgrenze im Spike S1 ermitteln, kein fester Wert zugesichert).
- **AC-S2** Ohne iCloud-Konto läuft die App lokal; ein Hinweis erklärt den Zustand; nach Anmeldung werden lokale Daten **nicht verworfen**.
- **AC-S3** Zwei gleichzeitige Buchungen auf zwei Geräten summieren sich (kein verlorenes Update).
- **AC-S4** Doppelt angelegte Produkte (Name+Marke) werden erkannt und lassen sich zusammenführen; Buchungen bleiben erhalten.
- **AC-S5** Auf einem frisch eingerichteten zweiten Gerät erscheint nach dem Erstimport der vollständige Bestand; es werden keine Standarddatensätze doppelt erzeugt.
- **AC-S6** Bei vollem iCloud-Speicher meldet die App verständlich, dass nicht gespeichert werden kann, und arbeitet lokal weiter.
- **AC-S7** Export → App löschen → Import stellt Produkte, Chargen, Buchungen und Einstellungen identisch wieder her; ein zweiter Import verdoppelt nichts.

### 15.8 Datenschutz (Abschnitt 10, 11)
- **AC-D1** Prüfung des Netzwerkverkehrs bei normalem Gebrauch: **keine** Verbindung außer Apple-CloudKit (kein Drittanbieter, keine Telemetrie).
- **AC-D2** Die Datenschutzerklärung ist in der App und in App Store Connect verlinkt und nennt Datenarten, Speicherorte, Aufbewahrung und Löschweg.
- **AC-D3** „Alle Daten löschen“ entfernt lokale Daten **und** die iCloud-Kopie (im Spike belegt); ein zweites Gerät zeigt danach leeren Bestand.
- **AC-D4** In den synchronisierten Datensätzen kommen **keine** Gewichts-, Puls-, Leistungs-, Medizin-, Standort- oder HealthKit-Felder vor (Schema-Review).
- **AC-D5** Je nach Entscheidung O-01: Option B – Sessions und Wochenvorlage liegen in einer Konfiguration **ohne** CloudKit-Spiegelung; Option A – schriftliche Klärung liegt vor.
- **AC-D6** Die App schreibt nichts in HealthKit.

### 15.9 Allgemein
- **AC-G1** Dynamic Type bis zur größten Stufe, VoiceOver-Beschriftungen für Status, Charts und Ampeln, Farbe nie alleiniger Informationsträger.
- **AC-G2** Hell- und Dunkelmodus, iPhone (kleinste unterstützte Größe) ohne abgeschnittene Kernkennzahlen.
- **AC-G3** Zahlen- und Datumsformate folgen der Region (Komma/Punkt); intern keine Rundungsfehler (Ganzzahl-Cent, Ganzzahl-Mengen).
- **AC-G4** Rechenkern hat Unit-Tests für alle Testvektoren TV-1 bis TV-8 und für die Randfälle Bestand 0, kein MHD, MHD gestern, Bedarf 0, negativer Bestand.

---

## 16. Erfolgsmetriken (was macht die App gut?) **[Original, messbar gemacht]**

Ohne Backend gibt es **keine Telemetrie** (Datenschutzprinzip). Die Metriken werden **auf dem Gerät** berechnet und dem Nutzer in einer Statistikansicht gezeigt **❓ O-15**.

1. **Überkauf vermieden:** % der Kaufvorgänge, die die App als „nicht nötig“ bewertet. *Messung:* Anteil `PurchaseEvaluation.verdict = nicht kaufen`. *Einschränkung:* misst das Urteil, nicht das Verhalten; Ergänzung `userDecision` (gekauft/nicht gekauft) macht „tatsächlich vermiedene Käufe“ messbar **[Vorschlag]**.
2. **Ablauferkennung:** Kein Produkt verfällt ungenutzt (Ablaufereignisse ≈ 0). *Messung:* Anzahl und Carbs-Menge der `expire`-Buchungen je Quartal.
3. **Bedarfstreffer:** Bestand deckt ≥ 90 % der geplanten Trainingswochen ohne Engpass. *Messung:* Anteil der Wochen mit nutzbarem Bestand ≥ Wochenbedarf (nur Wochen mit bekanntem Bedarf).
4. **Nutzung:** „Packlisten-Challenge“ wird regelmäßig abgehakt. **Im Original nicht erklärt (Gamification? Serie? Ziel?)** → **❓ O-15**. Übergangsmessung: Anteil der abgeschlossenen Sessions mit abgehakter Packliste.

---

## 17. Umsetzungsplan (ohne Implementierung)

Aufwände sind **grobe Schätzungen in Personentagen (PT)** ohne Gewähr; sie sind für die Reihenfolge, nicht für Zusagen gedacht. Jeder Schritt endet mit grünen Tests und einem lauffähigen Stand.

| Stufe | Inhalt | Ergebnis / Abnahme | ca. PT |
|---|---|---|---|
| **M0 Entscheidungen** | Register (Abschnitt 18) bis P1 klären: O-01, O-03, O-04, O-05, O-06, O-07, O-08 | Freigabe der Spec durch Lino | 0,5 |
| **S1 Spike Sync** (vor Datenmodell-Festschreibung) | Minimal-App mit Product/Batch/StockMovement auf **zwei echten Geräten** mit iCloud: Konfliktfälle TV-8, Doppelbuchung, Erstimport, Kontowechsel, Löschen; **O-03 und O-24 entscheiden**; Verhalten ohne Konto | Befunde in die Spec zurückgeschrieben (9.3, 9.5) | 3–4 |
| **S2 Spike Konfiguration** | Zwei Speicher-Konfigurationen (CloudKit/lokal) und UUID-Verweise; Wechsel A↔B | Machbarkeit von O-01 Option B belegt | 1–2 |
| **S3 Spike Benachrichtigungen** | Kalender-Trigger, Neuaufbau, Limit-Test auf Gerät, Zeitzone | N und Verhalten belegt (8.3) | 1 |
| **C Anfrage an Apple (Lino)** | Entwurf Anhang C; Absenden nur durch Lino | Antwort in Spec ergänzen (O-01) | – |
| **M1 Rechenkern** | Swift-Package: Einheiten, Buchungen, FEFO, Prognose, Kauf-Urteil, Packliste, Zeitlogik; Testvektoren TV-1…TV-8 + Randfälle | AC-G4 grün, deterministisch | 6–8 |
| **M2 Bestand** | Datenmodell mit CloudKit-Regeln, Produkt/Charge/Buchung-UI, Suche/Filter, +/−, Archiv | AC-B1…B7 (ohne Sync) | 6–8 |
| **M3 Haltbarkeit + Erinnerungen** | Status/Farben, Verbrauch-zuerst, Benachrichtigungen, In-App-Hinweis | AC-H*, AC-N* | 4–5 |
| **M4 Training und Prognose** | Sessions, Typen/Carbs/h, Wochenvorlage (nach O-08), Prognose, Reichweite, Verfallsrisiko | AC-P* | 6–8 |
| **M5 Einkauf** | Einkaufsliste, Kauf-Entscheider, Verlauf, „Gekauft“ → Charge | AC-K* | 4–5 |
| **M6 Packliste** | Algorithmus, Abhaken/Storno/Rückbuchung, Idempotenz | AC-L* | 4–5 |
| **M7 iCloud-Härtung** | Fehlerzustände, Zusammenführen, Konfliktanzeige, Export/Import, „Alle Daten löschen“, Schema-Review, **Promotion Entwicklung→Produktion** als bewusster Schritt | AC-S*, AC-D* | 5–6 |
| **M8 Politur/Veröffentlichung** | Barrierefreiheit, Datenschutzerklärung, App-Privacy-Angaben, App-Icon/Name (≤ 30 Zeichen), TestFlight | AC-G*, Abschnitt 11.7 | 4–5 |

Summe: ca. 45–60 PT (grobe Schätzung; größte Unsicherheit = S1/M7).

**Abhängigkeiten:** S1 → (Persistenzentscheidung, Schemafreigabe) → M2. O-01 → M4. O-08 → M4. Ohne Antwort zu O-01 wird Option B umgesetzt, damit nichts blockiert.

**Test-Strategie:** Rechenkern per Unit-Tests (kein Simulator nötig); UI-Tests für die Kernpfade; **Sync nur auf echten Geräten** (Simulator genügt nicht für zuverlässige iCloud-Aussagen **[Nicht belegt]**, im Spike bestätigen); CloudKit-Dashboard zur Kontrolle der Satztypen; manuelle Szenarien aus Abschnitt 14.

**Zuständigkeit:** Bauen und Tests macht der Agent; **Apple-Anfrage, App-Store-Veröffentlichung, Schema-Promotion in Produktion und Datenschutz-Angaben in App Store Connect bleiben bei Lino** (Projektregel: Eingriffe an Live-Systemen und Veröffentlichungen nicht ohne Freigabe).

---

## 18. Entscheidungsregister (offene Fragen)

Priorität **P1** = blockiert den Start, **P2** = blockiert ein Feature, **P3** = kann später. „Arbeitsannahme“ = was gilt, bis entschieden ist.

| ID | Frage | Optionen / Empfehlung | Arbeitsannahme | Prio |
|---|---|---|---|---|
| **O-01** | Dürfen Session-Planungsdaten (Datum, Typ, Dauer, g/h), Wochenvorlage und Packlisten nach iCloud? | A alles sync · **B Sessions lokal, Inventar per iCloud (Empfehlung)** · C zusätzlich Apple fragen (Entwurf Anhang C) | B | P1 |
| **O-02** | V2-Import aus Bevel/TrainingPeaks/MyWhoosh: welche Quelle, welche Daten? | nur lokal speichern, nie in CloudKit-Speicher (11.4) | nicht in V1 | P3 |
| **O-03** | SwiftData oder Core Data? | **SwiftData, Entscheidung nach Spike S1**; Rückfall Core Data bei Sync-Problemen | SwiftData | P1 |
| **O-04** | Mindest-iOS-Version, iPad? | zu entscheiden; aktuelle Hauptversion minus eine, iPhone zuerst, iPad nur wenn ohne Mehraufwand | iPhone | P1 |
| **O-05** | Kaufhorizont, Schnäppchenregel, Verfallsschwelle, Preisabweichung | Horizont **12 Wochen**, Schnäppchenregel **aus**, 10 % Verfall, 15 % Preisabweichung | wie genannt | P2 |
| **O-06** | Beispielwerte aus Abschnitt 14 (8 Monate vs. 15,6 Wochen) bestätigen | Lino nennt echten Wochenbedarf und Vorrat | Beispiel mit korrigierter Rechnung | P2 |
| **O-07** | Bedeutung von „regen“ (Regeneration?), Carbs/h für Z2, Vorbelegung als Zahl oder Bereich | Regeneration; Z2 **60** als Platzhalter; Zahl + Bereichsanzeige | wie genannt | P1 |
| **O-08** | Wochenvorlage für 4-/12-Wochen-Prognose einführen? | **ja, sonst keine Aussage jenseits eingetragener Sessions** | ja (Vorschlag) | P1 |
| **O-09** | Ablauf buchen: automatisch oder nach Bestätigung? | **bestätigen lassen**, nichts automatisch buchen | bestätigen | P2 |
| **O-10** | Packliste: Reserve %, Kategorieanteile je Session-Typ, „Rest zurücklegen“, Buchung beim Haken (Original) | Reserve 10 %, Anteile einstellbar, Rückbuchung ja | wie genannt | P2 |
| **O-11** | Erinnerungen: Stufen, Uhrzeit, Engpass-Warnung, Geräteschalter | 60/30 Tage, 09:00, Engpass-Warnung **aus**, Gerätetoggle | wie genannt | P2 |
| **O-12** | Farbschwellen (6/3 Monate) fest oder einstellbar; Verhalten ohne MHD | **einstellbar**, ohne MHD grau | fest 6/3 | P3 |
| **O-13** | Preismodell: Versand, Rabatt, Währung, Preis je Stück oder gesamt | Gesamtpreis je Charge inkl. Versandanteil, nur EUR | wie genannt | P2 |
| **O-14** | Selbstgemacht: nur Produkt (V1) oder Rezeptfunktion? | V1 nur Produkt, Rezepte V2 | nur Produkt | P3 |
| **O-15** | Metriken auf dem Gerät; Bedeutung „Packlisten-Challenge“ | lokal, keine Telemetrie; Challenge von Lino definieren oder streichen | Übergangsmessung | P3 |
| **O-16** | Web-Admin-Tool und Android entfallen? | **ja** (passt nicht zu „kein Backend“) | entfallen | P2 |
| **O-17** | Export/Import (JSON/CSV) in V1? | **ja** | ja | P2 |
| **O-18** | Veröffentlichung: nur privat (Xcode/TestFlight) oder öffentlich im App Store? App-Name, Bundle- und Container-ID | zu entscheiden; beeinflusst Impressum, Review, Datenschutzangaben | privat bis Entscheidung | P1 |
| **O-19** | Bedarf je Kategorie (Gel/Drink/Riegel) oder nur Gesamt-Carbs? | MVP **Gesamt**, Anzeige nach Kategorie | Gesamt | P3 |
| **O-20** | Mehrere Fahrer: Freigaben später? | später; Datenmodell bleibt nutzerneutral | nicht in V1 | P3 |
| **O-21** | Sprachen/Einheiten | nur Deutsch, metrisch, EUR | Deutsch | P3 |
| **O-22** | „Verkaufen“ im Original = Abgang (verbrauchen/verschenken)? | Abgangsgründe: verbraucht, verschenkt/verkauft, entsorgt, Korrektur | wie genannt | P3 |
| **O-23** | Prognose mit Bandbreite (min–max g/h)? | später; MVP Mittelwert | Mittelwert | P3 |
| **O-24** | Einstellungen als Datensatz oder iCloud-Key-Value-Speicher? | **Key-Value** (im Spike S1 bestätigen) | Key-Value | P2 |

---

## 19. Offene Fragen aus dem Original (Stand)

- **Mobile-first (iOS/Android) oder Web?** → Original: „primär mobil, Web als Admin-Tool“. **Stand:** Lino fordert native iOS ohne Backend → Android/Web entfallen (O-16 zur Bestätigung).
- **Trainingsdaten manuell oder API-Import?** → MVP manuell, API später (unverändert, O-02 für V2).
- **Eine Person oder Haushalt/Team?** → MVP Einzelperson (mit mehreren eigenen Geräten, Abschnitt 2); Team später (O-20).

---

## Anhang A: Rückverfolgbarkeit der Original-Features

| Original (Abschnitt) | Umgesetzt in | Hinweis |
|---|---|---|
| 3.1 Produkt anlegen (Name/Marke, Carbs, Menge, Preis, MHD, Kategorie, Verhältnis) | 4.1, 5.2, 5.3 | Menge/Preis/MHD wandern in die Charge |
| 3.1 Carbs pro € automatisch | 4.1, 5.3 | Formel präzisiert (Kaufmenge statt Bestand) |
| 3.1 Bestand ändern +/- | 4.1, 5.4 | als Buchung |
| 3.1 Suche, Filter | 4.1 | |
| 3.2 Farblegende | 4.2 | Schwellen O-12 |
| 3.2 „Verbrauch zuerst“-Liste | 4.2 | FEFO |
| 3.2 Push-/In-App-Erinnerung | 4.2, 8 | lokale Benachrichtigungen |
| 3.3 Sessions Dauer + Typ | 4.3, 5.5 | Z2/regen offen |
| 3.3 Carbs/h je Typ editierbar | 4.3, 5.5 | |
| 3.3 Prognose 1/4/12 Wochen | 4.3, 7.2 | Wochenvorlage O-08 |
| 3.3 Projektion „reicht bis“, MHD-Lücke | 4.3, 7.2 | in zwei Warnungen präzisiert |
| 3.4 Kaufen-oder-nicht-Urteil | 4.4, 7.3 | dritter Zustand „nicht beurteilbar“ |
| 3.4 Black-Friday-Szenario | 4.4, 14 | |
| 3.5 Packliste | 4.5, 7.4 | |
| 3.5 Abhaken reduziert Bestand | 4.5, 5.6 | mit Storno und Rückbuchung |
| 4 Barcode/Etikett-Scan, Trainingsplan-Import, Verlauf/Statistik, Budget, Mehrere Fahrer, Rezepte | 6 | unverändert V2 |
| 5 Datenmodell Product/Session/Log | 5 | Charge und Buchung ergänzt |
| 6 MVP-Abgrenzung | 12 | Sync-Punkt geändert (begründet) |
| 7 Erfolgsmetriken (4 Stück) | 16 | lokal messbar; 4 offen |
| 8 Beispiel-Szenario | 14 | Rechenfehler markiert |
| 9 Offene Fragen | 19, 18 | |

## Anhang B: Begriffe

- **Charge:** ein Kauf bzw. eine Menge mit gleichem MHD.
- **FEFO:** *first expired, first out* – früheste Haltbarkeit zuerst verbrauchen.
- **MHD:** Mindesthaltbarkeitsdatum, hier als Kalendertag „gilt bis einschließlich“.
- **Buchung (StockMovement):** unveränderlicher Zu- oder Abgang einer Charge.
- **Idempotenzschlüssel:** deterministische Kennung, die verhindert, dass dieselbe Buchung zweimal zählt.
- **Reichweite:** Zeit, bis der nutzbare Bestand den Bedarf nicht mehr deckt.
- **Verfallsrisiko:** Menge, die vor dem MHD voraussichtlich nicht verbraucht wird.
- **Privater CloudKit-Bereich:** vom Nutzer-iCloud-Konto verwalteter Speicher der App; der Entwickler betreibt dafür keinen Server.

## Anhang C: Entwurf einer Anfrage an Apple **(nicht gesendet; Absenden nur durch Lino)**

> **Hinweis 23.11.:** Der Entwurf stammt aus der Zeit vor M9c und sagt „lesen kein HealthKit“. Vor einem Absenden anpassen: Die App liest seit M9c Radfahrten aus Apple Health (nur lesen, lokal).

> Wir entwickeln eine iOS-App zur Verwaltung von Sport-Ernährungsvorräten (Gele, Riegel, Pulver). Die App synchronisiert Produkte, Chargen, Preise und Ablaufdaten über den privaten CloudKit-Bereich des Nutzers. Zusätzlich möchten wir optional **manuell eingegebene Trainings-Planungsdaten** (geplantes Datum, Trainingstyp, Dauer in Minuten, Ziel-Kohlenhydrate pro Stunde) in demselben privaten Bereich ablegen, um den Vorratsbedarf auf mehreren Geräten desselben Nutzers zu berechnen. Wir erfassen **keine** Körper-, Vital-, Leistungs- oder Gesundheitsdaten und lesen **kein** HealthKit.
> Frage: Fallen diese Planungsdaten unter „personal health information“ (App Review Guideline 5.1.3(ii)) bzw. „sensitive, individually-identifiable health information“ (DPLA 3.3.3(D)), sodass sie nicht in iCloud/CloudKit gespeichert werden dürfen? Falls ja: Gibt es eine schriftliche Ausnahme oder ein empfohlenes Vorgehen?
