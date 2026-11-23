# CarbStock – Status und Übergabe

**Stand:** 23.11.2026
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

Bekannte Verhaltensdetails: ±-Schnellbuchung bucht nicht, wenn nur abgelaufener Bestand da ist (Meldung in der Liste); Abgang über mehrere Chargen meldet `insufficientStock` statt negativ zu buchen. Negativer Bestand entsteht damit nur noch durch Sync-Überschneidung (TV-8) und wird als Konflikt angezeigt.
Nicht geprüft: Erinnerungen auf einem echten Gerät (Spike S3), Tippen auf Meldung → Tab „Zuerst“ ohne UI-Test.

## Zum Build 0.1.0 (1): was nur Lino tun kann
- **Internen Tester anlegen** (App Store Connect → TestFlight → interne Gruppe, Lino als Tester): Schreibaktion im Konto, daher nicht durch Agenten.
- **CloudKit-Schema nach Production promoten** (CloudKit-Konsole, Container `iCloud.de.linolaske.carbstock`, bewusster Schritt nach Schema-Review G1). TestFlight-Builds nutzen Production; ohne Promotion läuft die App lokal, synchronisiert aber nicht.
- Build-Nummer vor jedem weiteren Upload erhöhen (`CURRENT_PROJECT_VERSION` in `project.yml`).
- Export-Hinweis: Mit Homebrew-rsync im PATH scheitert Xcodes IPA-Export („--extended-attributes unknown option“). Abhilfe: `PATH=/usr/bin:/bin:/usr/sbin:/sbin:… xcodebuild -exportArchive …`.

## Nächste Schritte (Reihenfolge)
1. **M7 Rest:** Einstellungen über iCloud-KVS (O-24); Prüfung am Gerät (Spike S1).
2. **M4b Allgemein nutzbar:** Ersteinrichtung der Carbs/h-Werte, keine festen persönlichen Werte, neutrale Leerzustände.
3. **M9 Trainingsquellen:** Strava (fest eingeplant) und Apple Health, Duplikate zuerst im Core: `docs/TRAININGSQUELLEN.md`.
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
