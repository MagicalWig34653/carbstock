# Gate G1: Schema-Review vor der CloudKit-Production-Promotion

**Stand:** 25.11.2026. Grundlage: Spec 9.2, `App/Models/*.swift`, `App/Persistence/Stores.swift`.
**Es wurde nichts promotet, nichts hochgeladen und nichts an CloudKit geändert.**

## Ergebnis
- **Alle 12 `@Model`-Typen erfüllen die CloudKit-Regeln. Kein Verstoß, keine Änderung an den Modellen nötig.**
- Ein Fund in der Sicherung (Export verlor Freitextfelder) ist behoben, ohne Schema-Eingriff.
- Das Schema ist aus Sicht des Quelltexts **bereit zum Einfrieren**. Vor der Promotion fehlt noch ein Schritt: Das Development-Schema in CloudKit muss vollständig sein (siehe „Vor der Promotion“).

## Geprüfte Regeln
| Nr. | Regel | Prüfung im Core-Paket (`swift test`) | Prüfung am echten Schema (App-Target) |
|---|---|---|---|
| R1 | Jedes Attribut ist optional oder hat einen Vorgabewert | `ModelSourceRulesTests` | `everyAttributeIsOptionalOrHasDefaultAndIsPlain` |
| R2 | Kein `.unique` / `#Unique` | ja | `noUniqueConstraints` |
| R3 | Beziehungen optional, mit Gegenbeziehung, nie `.deny` | ja | `relationshipsAreOptionalWithInverseAndNotDeny` |
| R4 | Keine geordneten Beziehungen | ja (`.ordered` wird abgelehnt) | `relationshipsHaveNoOptions`; SwiftData kennt als Beziehungsoption nur `.unique` |
| R5 | Enums und strukturierte Werte nicht als eigene Typen: nur `String`, `Int`, `Double`, `Bool`, `Date`, `UUID`, `Data`; nichts Transformierbares oder Zusammengesetztes | ja (auch Arrays und eigene Typen werden abgelehnt) | `everyAttributeIsOptionalOrHasDefaultAndIsPlain` |
| R6 | `var` mit Typangabe, keine reservierten Namen | ja | – |
| R7 | Keine Beziehung zwischen Konfigurationen | – | `trainingTypesAreNotInInventoryConfiguration`, `importTypesAreSeparateAndStoreOnlyAllowedFields` |
| R8 | Keine Gesundheits-/Standortfelder (AC-D4) | – | `noForbiddenFieldNames` |

Der Prüfer im Core-Paket liest den Quelltext und läuft ohne Simulator, also auch in der CI. Er schlägt auch an, wenn ein `@Model` außerhalb von `App/Models` liegt oder die Zahl der Modelle sich ändert (dann bewusst anpassen). Grenze: Er ist eine Textprüfung im Stil dieses Projekts, kein Swift-Parser. Die zweite, unabhängige Prüfung am echten Schema sind die App-Tests.

**Rot-Nachweis:** Tests zuerst gegen einen leeren Prüfer (8 Fehlschläge). Zusätzlich wurden probeweise Verstöße in die echten Modelldateien eingebaut (fehlender Vorgabewert, `.unique`, nicht optionale Beziehung, Array-Attribut, `private var` ohne Typangabe): jeder wurde gemeldet, danach wurden die Dateien zurückgesetzt.

## Je Modell
„✓“ = R1–R6 erfüllt.

| Modell | Konfiguration | Attribute | Beziehungen (Inverse, Löschregel) | Ergebnis |
|---|---|---|---|---|
| `Product` | Inventory (CloudKit) | 15 | `batches` → `Batch.product`, cascade | ✓ |
| `Batch` | Inventory (CloudKit) | 12 | `product` ↔ `Product.batches`; `movements` → `StockMovement.batch`, cascade | ✓ |
| `StockMovement` | Inventory (CloudKit) | 11 | `batch` ↔ `Batch.movements` | ✓ |
| `ShoppingListItem` | Inventory (CloudKit) | 11 | keine (UUIDs) | ✓ |
| `PurchaseEvaluation` | Inventory (CloudKit) | 8 | keine | ✓ |
| `TrainingSession` | Training (lokal) | 12 | keine | ✓ |
| `WeeklyTemplateRecord` | Training (lokal) | 8 | keine | ✓ |
| `CarbRateOverride` | Training (lokal) | 4 | keine | ✓ |
| `PackList` | Training (lokal) | 8 | `items` → `PackListItem.packList`, cascade | ✓ |
| `PackListItem` | Training (lokal) | 6 | `packList` ↔ `PackList.items` | ✓ |
| `ImportedActivity` | Imports (lokal, kein Backup) | 14 | keine | ✓ |
| `ActivityPairDecision` | Imports (lokal, kein Backup) | 5 | keine | ✓ |

Speicherung: Enums als Rohwert-String (`categoryRaw`, `typeRaw`, `verdictRaw` …), Kalendertage als `yyyy-MM-dd`-String, strukturierte Schnappschüsse als JSON in `Data?` (`offerJSON`, `inputJSON`, `reasonsJSON`). Unbekannte Rohwerte führen beim Lesen zu einem Ersatzwert oder zum Überspringen des Satzes, nicht zum Absturz.

## Felder, die mit der Promotion endgültig werden (nur Inventory)
Nach der Promotion lassen sich diese Satztypen und Felder weder umbenennen noch löschen.

- **Product:** `id`, `name`, `brand`, `flavor`, `hasCaffeine`, `hasLactate`, `categoryRaw`, `baseUnitRaw`, `portionAmount`, `carbsPerPortionG`, `glucoseFructoseRatio`, `isArchived`, `createdAt`, `updatedAt`, `schemaVersion`
- **Batch:** `id`, `purchaseDay`, `quantityPurchased`, `totalPriceCents`, `currency`, `expiryDay`, `source`, `useDespiteExpiry`, `isArchived`, `createdAt`, `updatedAt`, `schemaVersion`, Beziehung `product`
- **StockMovement:** `id`, `typeRaw`, `delta`, `occurredAt`, `createdAt`, `idempotencyKey`, `reversesMovementID`, `referenceID`, `deviceID`, `note`, `schemaVersion`, Beziehung `batch`
- **ShoppingListItem:** `id`, `productID`, `freeText`, `plannedQuantity`, `estimatedTotalPriceCents`, `stateRaw`, `createdAt`, `schemaVersion`, `expiryDay`, `offerJSON`, `batchID`
- **PurchaseEvaluation:** `id`, `inputJSON`, `verdictRaw`, `reasonsJSON`, `userDecisionRaw`, `createdAt`, `schemaVersion`, `verdictQuantity`

Anmerkungen:
- `StockMovement.deviceID` wird derzeit nirgends beschrieben. Es bleibt: gespeicherte Eigenschaften werden nicht gelöscht, und ein ungenutzter optionaler String stört nicht.
- `id` ist nicht eindeutig erzwungen (CloudKit kann das nicht). Doppelte Produkte behandelt die App durch Zusammenführen (AC-S4).
- `StockMovement.referenceID` zeigt bei Packbuchungen auf die lokale Packliste. Auf einem zweiten Gerät zeigt die Referenz ins Leere; der Bestand stimmt trotzdem (bekannte Folge von O-01 B).

## Behobener Fund: Sicherung
Der Export (Spec 9.6, AC-S7) verlor beim Wiederherstellen `Batch.source`, `StockMovement.note` sowie Titel, Notiz und Startzeit der Sessions. Jetzt sind sie dabei (`freeTextFieldsSurviveExportImport`, zuerst rot).

**Warum kein Datenverlust und keine Migration:** Kein `@Model` wurde geändert, vorhandene lokale Daten bleiben unberührt. Die Sicherung bekam nur zusätzliche optionale JSON-Felder, die Dateiversion bleibt 1. Alte Sicherungen importieren wie bisher (Felder leer). Eine ältere App-Version ignoriert die neuen Felder.

**Weiterhin nicht in der Sicherung** (ohne Bezug zum CloudKit-Schema, kann jederzeit nachgezogen werden):
- Einkaufsliste, Einkaufsverlauf und Packlisten (`ShoppingListItem`, `PurchaseEvaluation`, `PackList`, `PackListItem`)
- Anlege-/Änderungszeitpunkte von Produkten, Chargen und Sessions, `deviceID`
- Importierte Apple-Health-Fahrten: bewusst ausgeschlossen

## Vor der Promotion (offen)
1. **Development-Schema vervollständigen.** Die Promotion überträgt nur, was im Development-Schema des Containers steht (Stand 25.11.: nur `Users`). Beim Anlegen durch normales Speichern entstehen nur Satztypen und Felder, für die schon ein Wert gespeichert wurde; nie belegte optionale Felder (sicher `deviceID`) fehlen dann. Dafür gibt es jetzt das DEBUG-Werkzeug (`CloudKitSchemaTool`, Schema `CarbStockSchema`).
2. Konsole bzw. `scripts/pruefe-cloudkit-schema.py` prüfen: fünf Satztypen `CD_Product`, `CD_Batch`, `CD_StockMovement`, `CD_ShoppingListItem`, `CD_PurchaseEvaluation` mit allen Feldern oben. Satztypen für Training oder Imports dürfen **nicht** vorkommen.
3. Erst dann „Deploy Schema Changes“ nach Production.

Die genaue Schrittfolge steht in `docs/STATUS.md` → „CloudKit-Schema anlegen“.

## Nicht geprüft
- Kein echter CloudKit-Abgleich und kein Blick in die CloudKit-Konsole (Geräte-Spike S1 offen). Dieses Review belegt die Regeln am Quelltext und am SwiftData-Schema, nicht das Verhalten des Servers.
