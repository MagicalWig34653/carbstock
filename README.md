# CarbStock

Eine iPhone-App für den Kohlenhydrat-Vorrat im Ausdauertraining. Sie beantwortet drei Fragen: **Reicht mein Vorrat?** · **Was verbrauche ich zuerst?** · **Lohnt sich dieser Kauf?**

- SwiftUI und SwiftData, Bestand optional über das **eigene private iCloud** abgeglichen. **Kein Backend, kein Konto, kein Tracking, keine Drittanbieter-SDKs.**
- Alle Planungswerte (Kohlenhydrate pro Stunde, Bedarf, Kaufhorizont) sind frei einstellbare Voreinstellungen und keine Ernährungsberatung.
- Trainingsdaten bleiben auf dem Gerät.
- Oberfläche auf Deutsch.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Packages/CarbStockCore` | reine Rechenlogik (Bestand, Haltbarkeit, Prognose, Kauf-Urteil, Packliste), ohne UI und ohne Systemuhr |
| `App/` | SwiftUI-App und SwiftData-Speicher |
| `AppTests/` | App-Tests |
| `docs/` | Spezifikation, Konzept, Status, Planung der Trainingsquellen |

## Bauen und testen

Voraussetzungen: Xcode mit Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/test.sh core    # Rechenkern, läuft auf dem Mac
scripts/test.sh app     # App-Tests im Simulator „CarbStock iPhone“ (oder CARBSTOCK_DEST setzen)
```

Unsignierte Builds laufen ohne iCloud (`CARBSTOCK_CLOUDKIT=NO`). Für eine eigene signierte Version musst du Bundle-ID, Team und iCloud-Container in `project.yml` und `App/CarbStock.entitlements` durch eigene ersetzen.

## Datenschutz

Es werden keine Gesundheits-, Standort- oder Kontaktdaten erfasst. Der Bestand liegt auf dem Gerät und, wenn aktiviert, in deiner privaten iCloud (CloudKit). Der Entwickler hat darauf keinen Zugriff.

## Lizenz

[GNU Affero General Public License v3.0 oder später](LICENSE) (`AGPL-3.0-or-later`).

Hinweis: Der Rechteinhaber vertreibt die App selbst über TestFlight und den App Store. Beiträge Dritter werden nur mit einer Beitragsvereinbarung übernommen, die das erlaubt.
