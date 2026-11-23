# CarbStock

Native iOS-App (SwiftUI, SwiftData, iCloud/CloudKit privat, **kein Backend**) für den Kohlenhydrat-Vorrat im Radtraining.
Bundle-ID `de.linolaske.carbstock`, iCloud-Container `iCloud.de.linolaske.carbstock`. Sprache: Deutsch.

## Zuerst lesen
1. `docs/STATUS.md` – aktueller Stand, nächste Schritte, offene Fragen (Quelle der Wahrheit)
2. `docs/KONZEPT.md` – Architektur, Datenschutz-Einstufung, getroffene Arbeitsentscheidungen
3. `docs/SPEC.md` – fachliche Spezifikation (Testvektoren TV-1…TV-8 in 7.5, Akzeptanzkriterien in 15, Entscheidungsregister in 18)
4. `docs/APP-STORE-CONNECT.md` – was Lino in App Store Connect / im Developer-Portal anlegt

## Aufbau
- `Packages/CarbStockCore` – reiner Rechenkern (keine UI, keine Persistenz, keine Systemuhr; "heute" wird als `CalendarDay` übergeben). Tests: `swift test`.
- `App/` – SwiftUI-App. `App/Models` SwiftData-Modelle, `App/Persistence/Stores.swift` Container mit zwei Konfigurationen.
- `AppTests/` – App-Tests (Swift Testing), laufen mit `-CarbStockInMemory`.
- `project.yml` – XcodeGen. Das `.xcodeproj` ist nicht eingecheckt: `xcodegen generate`.

## Bauen und testen
- `scripts/test.sh` (beides), `scripts/test.sh core`, `scripts/test.sh app`.
- Simulator: „CarbStock iPhone“ (iOS 27.0, selbst anlegen) oder `CARBSTOCK_DEST` setzen.
- Lange Builds optional über einen Wrapper (`CARBSTOCK_WRAPPER`, siehe `scripts/test.sh`). DerivedData liegt in `build/` (gitignored).
- Unsignierte Builds brauchen `CARBSTOCK_CLOUDKIT=NO`, sonst stürzt CloudKit beim Start ab (fehlende Berechtigung).

## Harte Regeln
- **CloudKit-Schema nur additiv** (Spec 9.2): keine `@Attribute(.unique)`, alle Attribute mit Standardwert oder optional, alle Beziehungen optional mit Gegenbeziehung. Gespeicherte Eigenschaften nie umbenennen oder löschen. `SchemaRulesTests` prüft das.
- **Training bleibt lokal** (O-01 Option B): `TrainingSession`, `WeeklyTemplateRecord`, `CarbRateOverride`, `PackList`, `PackListItem` liegen in der Konfiguration „Training“ ohne CloudKit. Keine Beziehungen zwischen den Konfigurationen, nur UUIDs.
- **Keine Gesundheitsdaten** (Gewicht, Puls, Leistung, Kalorien, Standort) erfassen oder synchronisieren. **Einzige Ausnahme (Maintainer-Entscheidung 21.11.2026): Apple Health nur lesen** – ausschließlich Radfahrten (`HKWorkout`, Typ cycling) mit Beginn und Dauer, nichts schreiben, nichts nach iCloud, in Export oder Geräte-Backup (Store „Imports“, lokal, vom Backup ausgenommen). Keine Drittanbieter-SDKs, kein Analytics/Tracking, keine Netzwerkzugriffe außer CloudKit.
- **Buchungen sind unveränderlich.** Bestand ist immer Σ delta. Korrektur = `reversal`/`adjust`.
- Geld in Cent (Int), Mengen in Int der Basiseinheit, Carbs als Double; Rundung nur in der Anzeige.
- Rechenlogik gehört in `CarbStockCore` und wird dort test-first geschrieben (Testvektoren der Spec als Tests).
- Keine Deploys, keine App-Store-Veröffentlichung, keine CloudKit-Schema-Promotion nach Production, keine Nachricht an Apple: das macht der Maintainer. TestFlight-Uploads sind nach bestandenen Prüfungen erlaubt; externe Gruppen zuordnen und zur Beta-Prüfung einreichen bleibt beim Maintainer.
- Userdaten und Secrets nie in Logs, Commits oder externe Dienste.

## Lizenz
AGPL-3.0-or-later, siehe `LICENSE`. Interne Arbeitsregeln des Maintainers liegen in `CLAUDE.local.md` (nicht im Repo).
