# CarbStock – Status und Übergabe

**Stand:** 24.11.2026
Diese Datei ist die Quelle der Wahrheit für den Arbeitsstand. Bei jeder Änderung des Stands mitpflegen.

## Was steht (main)
| Bereich | Stand | Nachweis |
|---|---|---|
| Grundgerüst | XcodeGen-Projekt, iOS 26+, nur iPhone, Bundle `de.linolaske.carbstock`, Entitlements iCloud/CloudKit + Push + KVS, PrivacyInfo | `scripts/test.sh` grün |
| Speicher | SwiftData, zwei Konfigurationen: „Inventory“ → privates CloudKit, „Training“ → lokal (O-01 B). Ohne Berechtigung (`CARBSTOCK_CLOUDKIT=NO`) rein lokal | `StoresTests`, `SchemaRulesTests` |
| M1 Rechenkern | Ledger (Σ delta, Idempotenz, Storno, Konflikte), FEFO, Expiry, Verbrauch-zuerst, Bedarf/Prognose/Reichweite/Verfall/Versorgungslücke, Kauf-Urteil R1–R6, Packlisten-Planer, ReminderPlanner | 69 Core-Tests (TV-1…TV-8, AC-G4) |
| M2 Bestand | Liste, Suche/Filter, ±-Schnellbuchung (FEFO), Formular Produkt+Charge, Detail mit Chargen, Archiv, Konfliktanzeige; 5 Tabs, Einstellungen per Zahnrad | App-Tests |
| M3 Haltbarkeit | App rechnet nur noch über `CarbStockCore`; Tab „Zuerst“ (Entsorgen nach Bestätigung, Trotzdem nutzen, Badge); lokale Erinnerungen (Sammelmeldung 60/30 Tage, ≤ 50, Schalter je Gerät, Berechtigung erst beim Einschalten) | 31 App-Tests gesamt |

| M4 Training und Prognose | Sessions, Wochenvorlage, Carbs/h-Einstellung, Tab Bedarf (7/28/84 Tage, Reichweite, Ampel, Verfallsrisiko, Versorgungslücke) | App-Tests |
| M5 Einkauf | Tab „Einkauf“: Kauf-Entscheider (Angebot mit Produkt, Menge, Gesamt-/Stückpreis, Versand, Rabatt, MHD, Kaufhorizont, Schnäppchenregel; Urteil R1–R6 mit Begründungszeilen, €/100 g Carbs), Einkaufsliste (aus Urteil oder manuell; „Gekauft“ = Charge + purchase-Buchung nach Bestätigung), Verlauf (`PurchaseEvaluation`-Snapshots; nur nach Sichern, Gekauft oder Verwerfen). Core: `OfferPricing`. Modell nur additiv erweitert (`ShoppingListItem.expiryDay/offerJSON/batchID`, `PurchaseEvaluation.verdictQuantity`) | Core- und App-Tests, AC-K1…K7 |

| M6 Packliste | Planer je Session oder freiem Ziel, Abhaken = eine Buchung, Haken weg = Gegenbuchung, Rest zurücklegen, Fertig = schreibgeschützt | AC-L1…L6 |
| M7 Sicherung (Teil) | Export/Import JSON (idempotent), doppelte Produkte zusammenführen, Alle Daten löschen, iCloud-Status | App-Tests |

| M8 (Teil) Erster TestFlight-Build | App-Icon (Platzhalter, `scripts/make-icon.swift`), signiertes Release-Archiv, Upload **0.1.0 (1)** am 23.11. über Xcode, in App Store Connect verarbeitet (VALID, Verteilung „intern“). Distribution-Signierung geprüft: `aps-environment=production`, iCloud-Umgebung Production, `get-task-allow=false` | Archiv + IPA-Prüfung, Core 92 Tests, App-Tests grün |

| M4b Allgemein nutzbar (Teil) | Ersteinrichtung der Carbs/h je Art beim ersten Start (Sheet, überspringbar, nur Abweichungen vom Vorschlag werden gespeichert, Gerät merkt „erledigt“). Keine festen persönlichen Werte. Nicht im Test-/Beispieldaten-Start | 4 App-Tests `RateSetupTests`; Sheet im Simulator gesehen (23.11.) |
| M4b Leerzustand (24.11.) | Frischer Start ohne Daten: alle fünf Tabs zeigen einen neutralen Leerzustand, Bedarf ohne Vorrat und ohne Bedarf zeigt nur „Bedarf unbekannt“ statt Zeilen aus Nullen (`DemandScreen.showsForecast`). Keine Vorbelegung außer den ausdrücklich als „Vorschlag“ gekennzeichneten Carbs/h der Ersteinrichtung. UI-Test `EmptyStateUITests` (hell, dunkel, größte Schrift, Ersteinrichtung; Startargument `-CarbStockShowSetup`) | `EmptyStateTests` (3), 6 UI-Tests; Bilder in runtime/nachweise/carbstock-m4b |
| M4b Leerzustand verschwindet (24.11.) | UI-Test `EmptyStateGoesAwayUITests` (hell, dunkel): Bestand, Training und Bedarf zeigen den Leerzustand am Anfang, nach dem ersten Eintrag (Produkt über das Formular, Session über „Session anlegen“) ist er weg; Produkt entfernen (ohne Buchungen) und Session löschen bringen ihn zurück. Gegenprobe: mit erzwungenem Leerzustand schlagen alle 6 Tests fehl. Hinweis: Ein Produkt mit Buchungen wird beim „Archivieren“ nur archiviert und liegt im Filter „Archiv“; das ist bewusst kein Leerzustand | `AppUITests/EmptyStateGoesAwayUITests`; Bilder vorher/während/nachher als Anhänge des Testlaufs |
| M6 Packliste, UI-Test (24.11.) | `PackListUITests` (hell, dunkel): Packliste aus der Session anlegen, Haken setzen (Bestand sinkt), Haken entfernen (Bestand wie vorher), erneut abhaken und Rest zurücklegen („1 zurückgelegt · verbraucht 3“). Sichtprüfung der Bilder erledigt | `AppUITests/PackListUITests` |
| Geschmack (Lino 23.11.) | Optionales Feld „Geschmack“ am Produkt: Formular, Liste, Suche, Detail (nachträglich änderbar), Einkauf (Entscheider, Liste, Gekauft), Packliste, Zuerst, Bedarf. Sicherung/Import mit `flavor` (fehlt in alten Dateien = keiner, Version bleibt 1). Doppelerkennung berücksichtigt den Geschmack. Schema: ein neues optionales Feld `Product.flavor`, additiv | Core 122, App 127 Tests (vor den Zusätzen); Karte „Geschmacksrichtungen tracken“ |
| Koffein-/Laktatzusatz (Lino 23.11.) | Zwei Ja/Nein-Optionen „Mit Koffein“ / „Mit Laktat“ als Geloption am Produkt (nur Kategorie Gel): Formular, Einkauf (Neues Produkt), Detail (nachträglich änderbar), Liste, Titel in allen Auswahlen. Sicherung/Import und Einkaufsverlauf mit `hasCaffeine`/`hasLactate` (fehlen in alten Dateien = nein, Version bleibt 1). Doppelerkennung berücksichtigt die Zusätze. Ohne Mengen, Grenzwerte, Hinweise. Schema: zwei neue Felder `Product.hasCaffeine`/`hasLactate` mit Vorgabewert false, additiv, gemeinsame Migration mit `flavor` | Core 128, App 134 Tests; Karte „Geschmacksrichtungen tracken“ |
| Review-Nacharbeit (23.11.) | Ersteinrichtung und „Carbs pro Stunde“ bei größter Schrift: Name und Wert vollständig lesbar (`RateStepperRow`, bei großer Schrift zweizeilig). Orange auf Weiß lag bei 2,9:1: Akzent, Warnton und Knopffläche jetzt ≥ 4,5:1 in hell und dunkel, per `ContrastTests` gemessen. `CarbRateOverride.updatedAt` additiv, jüngster Eintrag gewinnt. Spec: 7.6 (Dublettengrenzen 60 % / 15 min / längeres Fenster / Dauer 0), Abschnitt 12 (HealthKit) | Core 132, App 140 Tests; Karte „Review-Nacharbeit“ |
| Listenzeile bei größter Schrift (23.11.) | Bestandsliste: Bei Bedienungshilfen-Schriftgrößen rutschen die Knöpfe −/+ unter den Text, der Name bricht an Wortgrenzen um statt Buchstabe für Buchstabe zu zerfallen (`ProductRowView.stacksControls`). Vorher/Nachher im Simulator gesehen | 1 App-Test; Brain-Entscheidung (Qualitätsmangel) |
| Inventarisierungshelfer (Lino 23.11.) | Bestand → „Inventur“: **Erstaufnahme** (Produkt, Menge, MHD, mehrere Chargen am Stück, Neues Produkt) und **Zählen** (gezählt gegen erwartet, bucht nur die Differenz als `adjust` mit Notiz „Inventur“, Bestätigung, Zusammenfassung). Core `InventoryCount` verteilt die Differenz auf Chargen (Spec 4.6). Kein neues Datenfeld, kein Schema-Eingriff. Hell, dunkel, größte Schrift im Simulator gesehen | Core 142 (+10), App +5 Tests; Karte „Inventarisierungshelfer“ |
| M9a Externe Aktivitäten (Core) | `ExternalActivity`, idempotenter Import, Duplikatregel (≤ 5 min, ≥ 80 %, Sportart; „Vielleicht doppelt“), Nutzerentscheidungen, Zählung einmal, Vorschlag „erledigt“ | 26 Core-Tests (AC-X1…X5), Core gesamt 118 |
| M9c Apple Health (Lesen) | Tab Training → „Fahrten aus Apple Health“: einlesen (nur Radfahrten, 90 Tage, Beginn und Dauer), Duplikate zusammengefasst, Vorschlag „Session als erledigt markieren“ (bucht nichts), Ausblenden, Löschen. Store „Imports“ lokal, vom Geräte-Backup ausgenommen, nicht im Export; „Alle Daten löschen“ räumt ihn. HealthKit-Entitlement + Nutzungstext gesetzt. Quelle hinter Protokoll (`WorkoutSource`), Tests mit Attrappe | 10 App-Tests `ActivityServiceTests`, Schema-Test Imports; App gesamt 117 grün |

Bekannte Verhaltensdetails: ±-Schnellbuchung bucht nicht, wenn nur abgelaufener Bestand da ist (Meldung in der Liste); Abgang über mehrere Chargen meldet `insufficientStock` statt negativ zu buchen. Negativer Bestand entsteht damit nur noch durch Sync-Überschneidung (TV-8) und wird als Konflikt angezeigt.
Nicht geprüft: Erinnerungen auf einem echten Gerät (Spike S3), Tippen auf Meldung → Tab „Zuerst“ ohne UI-Test.

## Zum Build 0.1.0 (1): was nur Lino tun kann
- **Internen Tester anlegen** (App Store Connect → TestFlight → interne Gruppe, Lino als Tester): Schreibaktion im Konto, daher nicht durch Agenten.
- **CloudKit-Schema nach Production promoten** (CloudKit-Konsole, Container `iCloud.de.linolaske.carbstock`, bewusster Schritt nach Schema-Review G1). TestFlight-Builds nutzen Production; ohne Promotion läuft die App lokal, synchronisiert aber nicht.
- Build-Nummer vor jedem weiteren Upload erhöhen (`CURRENT_PROJECT_VERSION` in `project.yml`).
- Export-Hinweis: Mit Homebrew-rsync im PATH scheitert Xcodes IPA-Export („--extended-attributes unknown option“). Abhilfe: `PATH=/usr/bin:/bin:/usr/sbin:/sbin:… xcodebuild -exportArchive …`.

## Zu Apple Health: was nur Lino tun kann / noch offen
- **Capability HealthKit in der App-ID:** Xcode ergänzt sie beim nächsten signierten Archiv automatisch (Portal-Änderung durch Automatic Signing). Erst nach Linos Okay archivieren; der Build 0.1.0 (1) enthält noch kein HealthKit.
- **Datenschutz-Etikett / Review-Text:** Health wird gelesen, nicht erhoben („Collect“ = Übertragung vom Gerät); Etikett und Datenschutzerklärung (M8b) bewertet Lino. Der Nutzungstext steht in `project.yml`.
- **Spike S4 (zwei Geräte, echte Health-Daten):** ungeprüft. Die App nimmt nicht an, dass jede Fahrt auf jedem Gerät liegt; der Abgleich läuft zeitbasiert (AC-X3), nicht über die Health-UUID.
- **Sicht-Prüfung mit Health-Daten** steht aus: Leerzustand von „Fahrten“ im Simulator gesehen (23.11.), aber ohne Fahrten; Listen, Vorschläge und „Vielleicht doppelt“ nur durch Attrappen-Tests belegt.

## Nächste Schritte (Reihenfolge)
1. **M7 Rest:** Einstellungen über iCloud-KVS (O-24) bewusst noch nicht gebaut: es gibt keine synchronisierte Einstellung (Farbschwellen, Horizont, Reserve haben keine Oberfläche; Carbs/h und Erinnerungen sind gerätelokal). Baut man den `SettingsStore` jetzt, hat er keinen Nutzer. Wird mit der ersten solchen Einstellung gebaut; Prüfung am Gerät (Spike S1) liegt bei Lino.
2. **M4b Rest:** Englisch-Frage O-21 vor dem externen TestFlight. (Neutrale Leerzustände: erledigt 24.11., siehe Tabelle.)
3. **M9 Trainingsquellen:** M9a (Core) und M9c (Health lesen) stehen; Strava (M9b) wartet auf Linos Wahl A/B/C und ist laut Lino nachrangig: `docs/TRAININGSQUELLEN.md`.
4. **M8:** App-Icon, Barrierefreiheit, Datenschutzerklärung, TestFlight (auch extern) nach Freigabe des Maintainers.
5. **Spikes S1/S3/S4–S7** auf echten Geräten.

## Wartet auf Lino (Board-Fragen, nicht blockierend)
- **O-01** Trainingsdaten in iCloud? Gebaut: B (lokal). Apple-Anfrage-Entwurf in `docs/SPEC.md` Anhang C – nur Lino sendet.
- **O-18** Veröffentlichung (TestFlight intern / App Store / privat).
- **O-06/O-07** echte Werte (Z2 g/h, Wochenbedarf).
- **Öffentliches Repo (AGPLv3):** freigegeben; Push erst nach Bereinigung und zweiter Prüfung.
- **App ID + iCloud-Container**: am 21.11. per Xcode-Signierung registriert (siehe `docs/APP-STORE-CONNECT.md`); **App-Store-Connect-Eintrag** weiter offen. Karte „Lino: App-Store-Connect-Eintrag und iCloud-Container anlegen“ – ab sofort möglich.

## Festgestellte Spec-Abweichungen (für die nächste Spec-Fassung)
- **TV-6**: Mit „MHD gilt bis einschließlich“ (AC-H2) ergibt MHD = heute+14 genau 15 Verbrauchstage (≈ 214 g verbraucht, 286 g Verfall). Die Spec-Zahl 300 g passt zu MHD = heute+13. Test nutzt +13 und dokumentiert das.
- **TV-2 mit Wochenvorlage**: 900 g/Woche auf Mo/Mi/Sa verteilt ergibt 107 Tage / 15,3 Wochen statt 108 / 15,5 (Teilwoche). Mit gleichmäßigem Tagesbedarf stimmt TV-2 exakt.
- **Ampel „knapp“**: Spec definiert sie nicht; Core-Annahme: Deckung 100–110 % = knapp, < 100 % = Engpass, keine Ampel bei unvollständigem Bedarf.
- Weitere Core-Annahmen stehen als Kommentare mit Spec-Abschnitt im Code (`Forecast.swift`, `PurchaseAdvisor.swift`, `PackListPlanner.swift`).
