import Foundation
import Testing
@testable import CarbStockCore

/// Sicherung als JSON (AC-S7) und Erkennung doppelter Produkte (AC-S4).
@Suite struct BackupTests {
    let day = CalendarDay(year: 2026, month: 11, day: 23)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func sample() -> BackupDocument {
        let p = ProductInfo(name: "Gel", brand: "Maurten", category: .gel, baseUnit: .piece, carbsPerPortionG: 25, glucoseFructoseRatio: 0.8)
        let b = BatchInfo(productID: p.id, purchaseDate: day, quantityPurchased: 12, totalPriceCents: 4200,
                          expiryDate: day.adding(days: 200), useDespiteExpiry: true)
        let m = Movement(batchID: b.id, type: .purchase, delta: 12, occurredAt: t0, createdAt: t0, idempotencyKey: "purchase:x", referenceID: nil)
        let s = PlannedSession(day: day, type: .long, durationMinutes: 240, carbsPerHourOverride: 90, status: .done)
        let w = WeeklyTemplateEntry(weekdayIndex: 6, type: .long, durationMinutes: 240, validFrom: day, validUntil: day.adding(days: 90))
        return BackupDocument(exportedAt: t0, products: [p], batches: [b], movements: [m], sessions: [s], template: [w],
                              carbRates: [.long: 85])
    }

    @Test func roundTripIsIdentical() throws {
        let doc = sample()
        let data = try doc.encoded()
        let back = try BackupDocument.decode(data)
        #expect(back == doc)
        // Stabile Ausgabe: gleiche Eingabe, gleiche Bytes (nachvollziehbar und diff-bar)
        #expect(try doc.encoded() == data)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\""))
    }

    @Test func validationFindsBrokenReferences() throws {
        var doc = sample()
        #expect(doc.problems.isEmpty)
        doc.batches[0].productID = UUID()
        #expect(doc.problems.contains(.batchWithoutProduct(doc.batches[0].id)))
        doc = sample()
        doc.movements.append(Movement(batchID: UUID(), type: .adjust, delta: 1, occurredAt: t0))
        #expect(doc.problems.contains(.movementWithoutBatch(doc.movements[1].id)))
    }

    @Test func newerVersionIsRejected() throws {
        var doc = sample()
        doc.version = BackupDocument.currentVersion + 1
        let data = try doc.encoded()
        #expect(throws: BackupDocument.DecodeFailure.newerVersion(BackupDocument.currentVersion + 1)) { try BackupDocument.decode(data) }
        #expect(throws: BackupDocument.DecodeFailure.notABackup) { try BackupDocument.decode(Data("{}".utf8)) }
    }

    /// Import ist idempotent: bekannte IDs werden nicht noch einmal angelegt.
    @Test func importPlanSkipsKnownIDs() {
        let doc = sample()
        let all = doc.importPlan(knownProducts: [], knownBatches: [], knownMovements: [], knownSessions: [], knownTemplate: [])
        #expect(all.products.count == 1 && all.batches.count == 1 && all.movements.count == 1 && all.sessions.count == 1 && all.template.count == 1)
        let again = doc.importPlan(knownProducts: Set(doc.products.map(\.id)), knownBatches: Set(doc.batches.map(\.id)),
                                   knownMovements: Set(doc.movements.map(\.id)), knownSessions: Set(doc.sessions.map(\.id)),
                                   knownTemplate: Set(doc.template.map(\.id)))
        #expect(again.isEmpty)
    }

    // AC-S4
    @Test func duplicateProductsIgnoreCaseSpacesAndAccents() {
        func p(_ name: String, _ brand: String?, archived: Bool = false) -> ProductInfo {
            ProductInfo(name: name, brand: brand, category: .gel, baseUnit: .piece, carbsPerPortionG: 25, isArchived: archived)
        }
        let a = p("Energy Gel", "Maurten"), b = p("  energy  gel ", "MAURTEN"), c = p("Énergie", nil), d = p("energie", "")
        let other = p("Riegel", "Maurten"), gone = p("Energy Gel", "Maurten", archived: true)
        let groups = DuplicateProducts.groups(in: [a, b, c, d, other, gone])
        #expect(groups.count == 2)
        #expect(Set(groups.map { Set($0.map(\.id)) }) == [[a.id, b.id], [c.id, d.id]])
        #expect(DuplicateProducts.groups(in: [a, other]).isEmpty)
    }

    @Test func mergeRequiresSameUnitAndCarbs() {
        let a = ProductInfo(name: "Pulver", category: .drink, baseUnit: .gram, portionAmount: 50, carbsPerPortionG: 40)
        let same = ProductInfo(name: "pulver", category: .drink, baseUnit: .gram, portionAmount: 100, carbsPerPortionG: 80) // 0,8 g/g gleich
        let otherCarbs = ProductInfo(name: "pulver", category: .drink, baseUnit: .gram, portionAmount: 50, carbsPerPortionG: 30)
        let otherUnit = ProductInfo(name: "pulver", category: .drink, baseUnit: .piece, carbsPerPortionG: 0.8)
        #expect(DuplicateProducts.canMerge(a, into: same))
        #expect(!DuplicateProducts.canMerge(a, into: otherCarbs))
        #expect(!DuplicateProducts.canMerge(a, into: otherUnit))
        #expect(!DuplicateProducts.canMerge(a, into: a))
    }

    // MARK: Geschmacksrichtungen

    @Test func displayNameShowsFlavorOnlyWhenSet() {
        func p(_ f: String?) -> ProductInfo { ProductInfo(name: "Gel", flavor: f, category: .gel, baseUnit: .piece, carbsPerPortionG: 25) }
        #expect(p("Zitrone").displayName == "Gel · Zitrone")
        #expect(p(nil).displayName == "Gel")
        #expect(p("  ").displayName == "Gel")
    }

    @Test func flavorSurvivesBackupRoundTrip() throws {
        var doc = sample()
        doc.products[0].flavor = "Cola"
        let back = try BackupDocument.decode(try doc.encoded())
        #expect(back.products[0].flavor == "Cola" && back == doc)
    }

    /// Sicherung aus der Version ohne Geschmack (Feld fehlt im JSON) bleibt lesbar.
    @Test func backupWithoutFlavorFieldStillDecodes() throws {
        let doc = sample()
        let json = String(decoding: try doc.encoded(), as: UTF8.self)
        #expect(!json.contains("\"flavor\"")) // nil wird nicht geschrieben: alte und neue Dateien ohne Geschmack sind gleich
        let back = try BackupDocument.decode(Data(json.utf8))
        #expect(back.products[0].flavor == nil)
    }

    @Test func differentFlavorsAreNotDuplicates() {
        func p(_ flavor: String?, archived: Bool = false) -> ProductInfo {
            ProductInfo(name: "Gel", brand: "Maurten", flavor: flavor, category: .gel, baseUnit: .piece, carbsPerPortionG: 25, isArchived: archived)
        }
        let lemon = p("Zitrone"), lemon2 = p("  zitrone "), cola = p("Cola"), plain = p(nil), plain2 = p("")
        let groups = DuplicateProducts.groups(in: [lemon, lemon2, cola, plain, plain2])
        #expect(Set(groups.map { Set($0.map(\.id)) }) == [[lemon.id, lemon2.id], [plain.id, plain2.id]])
    }

    // MARK: Koffein- und Laktatzusatz (Geloption)

    @Test func displayNameShowsCaffeineAndLactateOnlyWhenSet() {
        func p(_ f: String?, _ c: Bool, _ l: Bool) -> ProductInfo {
            ProductInfo(name: "Gel", flavor: f, category: .gel, baseUnit: .piece, carbsPerPortionG: 25, hasCaffeine: c, hasLactate: l)
        }
        #expect(p(nil, false, false).displayName == "Gel")
        #expect(p(nil, true, false).displayName == "Gel · mit Koffein")
        #expect(p(nil, false, true).displayName == "Gel · mit Laktat")
        #expect(p("Zitrone", true, true).displayName == "Gel · Zitrone · mit Koffein · mit Laktat")
    }

    @Test func additivesSurviveBackupRoundTrip() throws {
        var doc = sample()
        doc.products[0].hasCaffeine = true
        doc.products[0].hasLactate = true
        let back = try BackupDocument.decode(try doc.encoded())
        #expect(back.products[0].hasCaffeine && back.products[0].hasLactate && back == doc)
    }

    /// Sicherung aus der Version ohne Zusätze (Felder fehlen im JSON) bleibt lesbar, beide Zusätze gelten dann als „nein“.
    @Test func backupWithoutAdditiveFieldsStillDecodes() throws {
        var doc = sample()
        doc.products[0].hasCaffeine = true
        let json = String(decoding: try doc.encoded(), as: UTF8.self)
        let stripped = json.replacingOccurrences(of: "\"hasCaffeine\"", with: "\"unbekannt\"")
            .replacingOccurrences(of: "\"hasLactate\"", with: "\"unbekannt2\"")
        let back = try BackupDocument.decode(Data(stripped.utf8))
        #expect(!back.products[0].hasCaffeine && !back.products[0].hasLactate)
    }

    // MARK: Einkaufsliste, Verlauf, Packlisten, Zeitpunkte

    func fullSample() -> BackupDocument {
        var doc = sample()
        let product = doc.products[0].id, batch = doc.batches[0].id
        doc.shoppingItems = [BackupShoppingItem(id: UUID(), productID: product, freeText: "Gel", plannedQuantity: 4,
                                                estimatedTotalPriceCents: 600, state: "bought", createdAt: t0,
                                                expiryDay: "2027-09-19", offerJSON: Data("{}".utf8), batchID: batch)]
        doc.purchaseEvaluations = [BackupPurchaseEvaluation(id: UUID(), verdict: "buyPartially", verdictQuantity: 3,
                                                            userDecision: "none", createdAt: t0,
                                                            inputJSON: Data("{}".utf8), reasonsJSON: Data("[]".utf8))]
        doc.packLists = [BackupPackList(id: UUID(), sessionID: doc.sessions[0].id, title: "Runde", targetCarbsG: 110.5,
                                        reservePercent: 10, state: "packing", createdAt: t0,
                                        items: [BackupPackItem(id: UUID(), productID: product, batchID: batch,
                                                               plannedQuantity: 5, plannedCarbsG: 125)])]
        doc.recordTimes = [product: BackupRecordTimes(createdAt: t0, updatedAt: t0.addingTimeInterval(60))]
        doc.carbRateTimes = [.long: t0]
        return doc
    }

    @Test func listsHistoryPackListsAndTimesSurviveBackupRoundTrip() throws {
        let doc = fullSample()
        let data = try doc.encoded()
        #expect(try BackupDocument.decode(data) == doc)
        #expect(try doc.encoded() == data)
    }

    /// Sicherung aus der Version vor Einkaufsliste, Verlauf, Packlisten und Zeitpunkten: die Schlüssel fehlen.
    @Test func backupWithoutListsAndTimesStillDecodes() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: fullSample().encoded()) as? [String: Any])
        for key in ["shoppingItems", "purchaseEvaluations", "packLists", "recordTimes", "carbRateTimes"] {
            #expect(json.removeValue(forKey: key) != nil, "\(key) wird nicht geschrieben")
        }
        let back = try BackupDocument.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(back.shoppingItems.isEmpty && back.purchaseEvaluations.isEmpty && back.packLists.isEmpty)
        #expect(back.recordTimes.isEmpty && back.carbRateTimes.isEmpty && back.products.count == 1)
    }

    @Test func importPlanSkipsKnownListsAndRepeatedIDs() {
        var doc = fullSample()
        // Dieselbe ID zweimal in der Datei (CloudKit erzwingt keine Eindeutigkeit): nur einmal anlegen.
        doc.shoppingItems.append(doc.shoppingItems[0])
        doc.purchaseEvaluations.append(doc.purchaseEvaluations[0])
        doc.packLists.append(doc.packLists[0])
        let all = doc.importPlan(knownProducts: [], knownBatches: [], knownMovements: [], knownSessions: [], knownTemplate: [])
        #expect(all.shoppingItems.count == 1 && all.purchaseEvaluations.count == 1 && all.packLists.count == 1)
        let again = doc.importPlan(knownProducts: Set(doc.products.map(\.id)), knownBatches: Set(doc.batches.map(\.id)),
                                   knownMovements: Set(doc.movements.map(\.id)), knownSessions: Set(doc.sessions.map(\.id)),
                                   knownTemplate: Set(doc.template.map(\.id)),
                                   knownShoppingItems: Set(doc.shoppingItems.map(\.id)),
                                   knownEvaluations: Set(doc.purchaseEvaluations.map(\.id)),
                                   knownPackLists: Set(doc.packLists.map(\.id)))
        #expect(again.isEmpty)
    }

    @Test func differentAdditivesAreNotDuplicates() {
        func p(_ c: Bool, _ l: Bool) -> ProductInfo {
            ProductInfo(name: "Gel", brand: "Maurten", category: .gel, baseUnit: .piece, carbsPerPortionG: 25, hasCaffeine: c, hasLactate: l)
        }
        let plain = p(false, false), plain2 = p(false, false), caf = p(true, false), both = p(true, true), both2 = p(true, true)
        let groups = DuplicateProducts.groups(in: [plain, plain2, caf, both, both2])
        #expect(Set(groups.map { Set($0.map(\.id)) }) == [[plain.id, plain2.id], [both.id, both2.id]])
    }
}
