# CarbStock – Konzept (Stand 21.11.2026)

Ergänzt `docs/SPEC.md` um die technische Umsetzung und die Arbeitsentscheidungen der Projektleitung.
Alles hier ist umkehrbar, solange das CloudKit-Schema nicht nach Production promotet ist (das macht nur Lino).

## 1. Ziel in einem Satz
Drei Fragen auf dem Gerät beantworten – *reicht mein Vorrat?*, *was zuerst verbrauchen?*, *lohnt sich der Kauf?* – nachvollziehbar, offline, ohne Backend, mit iCloud-Abgleich zwischen Linos eigenen Geräten.

## 2. Architektur

```
┌──────────────── App (SwiftUI, iOS 26+) ────────────────┐
│ Features: Bestand · Zuerst · Bedarf · Einkauf · Training│
│      │ liest @Query, schreibt nur über Services         │
│ Services (@MainActor): InventoryService, …              │
│      │ mappt Records → Werttypen                        │
│ SwiftData ModelContainer                                │
│   ├─ Konfiguration „Inventory“ → privates CloudKit      │
│   │    Product, Batch, StockMovement,                   │
│   │    ShoppingListItem, PurchaseEvaluation             │
│   └─ Konfiguration „Training“  → nur lokal (O-01 B)     │
│        TrainingSession, WeeklyTemplateRecord,           │
│        CarbRateOverride, PackList, PackListItem         │
│ NSUbiquitousKeyValueStore: kleine Einstellungen (O-24)  │
│ UserNotifications: lokale Ablauf-Erinnerungen           │
└──────────────┬──────────────────────────────────────────┘
               │ reine Werttypen, „heute“ als CalendarDay
┌──────────────▼── CarbStockCore (Swift-Package) ─────────┐
│ CalendarDay · Ledger (Σ delta, Idempotenz, Storno, FEFO)│
│ Expiry · Forecast (Tagessimulation) · PurchaseAdvisor   │
│ PackListPlanner        – keine UI, keine Persistenz     │
└─────────────────────────────────────────────────────────┘
```

- **Rechenkern getrennt**: Alle Zahlen, die die App behauptet, kommen aus `CarbStockCore` und sind per `swift test` ohne Simulator geprüft (Testvektoren TV-1…TV-8).
- **Buchungen statt Zähler**: Bestand = Σ unveränderlicher `StockMovement`. Zwei Geräte, die gleichzeitig buchen, addieren sich (kommutativ); Doppelungen fängt der `idempotencyKey`, den „gepackt“-Haken gibt es nur abgeleitet. Damit hängt nichts davon ab, wie `NSPersistentCloudKitContainer` Konflikte auflöst (nicht dokumentiert, Spec 9.3).
- **Zwei Konfigurationen von Anfang an**: Trainingsdaten liegen getrennt. Wechsel auf „alles synchronisieren“ (O-01 A) = `cloudKitDatabase` der Training-Konfiguration umstellen, kein Datenumbau. Verweise zwischen den Konfigurationen nur per UUID.
- **CloudKit-Schema-Disziplin** (Spec 9.2): keine Unique-Constraints, alles optional/mit Standard, Beziehungen optional mit Inverse, `schemaVersion` je Record, Enums als String, Kalendertage als `yyyy-MM-dd`. `SchemaRulesTests` hält das fest.
- **Ausfallsicher starten**: Ohne iCloud-Konto läuft der Spiegel-Speicher lokal und gleicht nach Anmeldung ab. Builds ohne iCloud-Berechtigung (unsigniert, Tests) schalten CloudKit über `CARBSTOCK_CLOUDKIT=NO` ab – sonst bricht CloudKit den Start hart ab (im Simulator nachgewiesen).
- **Keine Drittanbieter**, kein Analytics, kein eigenes Netzwerk. Einzige Verbindung: Apple CloudKit.

## 3. Arbeitsentscheidungen (umkehrbar, ohne Rückfrage getroffen)

| Register | Entscheidung | Begründung |
|---|---|---|
| O-01 | **Option B**: Training lokal, Inventar über iCloud | geringstes Regelrisiko; Spec-Empfehlung; Umschalten später billig |
| O-03 | **SwiftData** | Spec-Empfehlung; Core-Data-Rückfall bleibt möglich bis S1 |
| O-04 | **iOS 26.0**, nur iPhone | aktuelle Hauptversion 27 minus eins; iPad später ohne Umbau |
| O-05 | Horizont 12 Wochen, Schnäppchenregel aus, 10 % Verfall, 15 % Preis | Spec-Arbeitsannahmen, als Parameter im Kern |
| O-07 | Regen = Regeneration 40 g/h; Z2 = 60 g/h (Platzhalter) | Spec-Arbeitsannahme, Werte im Code (`CarbRate.builtIn`) |
| O-08 | Wochenvorlage kommt | ohne sie keine 4-/12-Wochen-Prognose |
| O-09 | Ablauf nur nach Bestätigung buchen | nie automatisch Bestand ändern |
| O-10 | Reserve 10 %, Anteile einstellbar, „Rest zurücklegen“ ja | Spec-Empfehlung |
| O-11 | 60/30 Tage, 09:00, Engpass-Warnung aus, Geräteschalter lokal | Spec-Empfehlung |
| O-13 | Gesamtpreis je Charge in Cent, nur EUR | Spec-Empfehlung |
| O-16/O-21 | kein Web/Android; nur Deutsch, metrisch | Vorgabe „native iOS ohne Backend“ |
| O-17 | Export/Import JSON in V1 (M7) | Rückfall bei Sync-Problemen, Datenportabilität |
| O-24 | Einstellungen im iCloud-Key-Value-Speicher | schlankes CloudKit-Schema |
| Name | **CarbStock** (9 Zeichen ≤ 30) | Arbeitsname aus Linos Auftrag; Verfügbarkeit im Store prüft Lino beim Anlegen |
| Kategorie | Health & Fitness | Zielgruppe Ausdauersport; keine Gesundheitsdaten nötig |

## 4. Datenschutz und Apple-Vorgaben – differenziert

**Was sicher ist (Belege in Spec 11/13):**
- Körper-/Vital-/HealthKit-Daten dürfen nicht nach iCloud (Review 5.1.3(ii), DPLA 3.3.3(D)). CarbStock erfasst solche Daten **gar nicht** (Schema-Test AC-D4) und nutzt kein HealthKit.
- Produkte, Chargen, Preise, MHD, Einkaufsliste sind keine Gesundheitsdaten → iCloud unkritisch.
- Benachrichtigungen dürfen nicht erzwungen werden (5.1.2(i)) → Berechtigung erst beim Einschalten, In-App-Hinweis als Rückfall.
- Datenschutzerklärung muss in der App **und** in App Store Connect verlinkt sein (5.1.1(i)).

**Was offen ist und wie wir damit umgehen:**
- *Session-Planung* (Datum, Typ, Dauer, g/h) ist eine Grauzone: Fitness-nah, aber ohne Mess- oder Körperdaten. Keine Quelle verbietet oder erlaubt iCloud dafür ausdrücklich. → Lokal (O-01 B), bis Lino entscheidet oder Apple schriftlich antwortet (Entwurf Spec Anhang C, **nicht gesendet**).
- *Bestandsbuchungen* (verbraucht/gepackt) verraten indirekt Trainingsverhalten, sind aber Vorratsbewegungen → synchronisiert. Buchungen tragen nur eine lose `referenceID` auf Packlisten-Posten, kein Session-Datum, keinen Typ.
- *App-Privacy-Etikett*: Nach Apples Definition („Collect“ = Übertragung so, dass Entwickler/Dritte zugreifen können) ist „Data Not Collected“ **wahrscheinlich** richtig, weil nur der private iCloud-Bereich des Nutzers genutzt wird. Nicht belegt ist, dass Apple den privaten CloudKit-Bereich ausdrücklich so einstuft. Lino entscheidet die Angabe in App Store Connect; `PrivacyInfo.xcprivacy` deklariert bereits: kein Tracking, keine erhobenen Datentypen, UserDefaults-Grund CA92.1.
- *Entwickler-Zugriff*: Über das CloudKit-Dashboard sieht der Entwickler im privaten Bereich keine Nutzerdaten fremder Konten (nur eigene Testkonten) – **im Spike S1 mit dem eigenen Konto prüfen**, bevor das Etikett gesetzt wird.
- *Impressum/DSGVO/Händlerstatus*: nicht geprüft, keine Rechtsberatung; relevant erst bei öffentlicher Veröffentlichung (O-18).

**Grundsätze im Code**: kein Netzwerk außer CloudKit, keine SDKs, „Alle Daten löschen“ lokal + iCloud (M7), Export als Portabilität, Haftungshinweis zu Carbs/h in den Einstellungen.

## 5. Teststrategie
- **Kern**: Swift Testing, jede Regel mit Testvektor/Randfall (AC-G4). Läuft in Sekunden, kein Simulator.
- **App**: Swift Testing mit In-Memory-Container (`-CarbStockInMemory`): Services, Schema-Regeln, Filterlogik. UI-Tests nur für Kernpfade, später.
- **Sync**: nur auf echten Geräten (Spike S1) – braucht registrierte Container-ID und Linos Geräte.

## 6. Fahrplan
M1 Rechenkern → M2 Bestand → M3 Haltbarkeit/Erinnerungen → M4 Training/Prognose → M5 Einkauf → M6 Packliste → M7 iCloud-Härtung/Export/Löschen → M8 Politur/TestFlight. Spikes S1 (Sync) und S3 (Benachrichtigungen) laufen, sobald signierte Gerätebuilds möglich sind (siehe `docs/APP-STORE-CONNECT.md`).
