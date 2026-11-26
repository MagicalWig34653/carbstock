import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// A ModelContext does not keep its container alive; tests hold the containers until the process ends.
@MainActor private var retainedContainers: [ModelContainer] = []

/// Sicherung vollständig: Einkaufsliste, Einkaufsverlauf, Packlisten und Anlege-/Änderungszeitpunkte (AC-S7).
@MainActor
@Suite struct BackupCompletenessTests {
    let day = CalendarDay(year: 2026, month: 11, day: 23)

    func make() -> (ModelContext, BackupService) {
        let container = Stores.make(inMemory: true).container
        retainedContainers.append(container)
        return (container.mainContext, BackupService(context: container.mainContext))
    }

    private func stamp(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 3600.25) }

    /// Erfundene Daten in allen Bereichen, mit Zeitpunkten, die sicher nicht „jetzt“ sind.
    func seed(_ context: ModelContext) throws {
        let day = self.day
        let inventory = InventoryService(context: context, today: { day })
        let training = TrainingService(context: context, today: { day })
        let purchase = PurchaseService(context: context, today: { day })
        let packing = PackService(context: context, today: { day })

        var gel = ProductDraft()
        gel.name = "Testgel"; gel.brand = "Erfunden"; gel.category = .gel; gel.carbsPerPortionG = 25; gel.quantity = 20
        let product = try inventory.createProduct(gel)
        var sessionDraft = SessionDraft(day: day.adding(days: 2)); sessionDraft.type = .long; sessionDraft.durationMinutes = 180
        _ = try training.addSession(sessionDraft)
        try training.setRate(85, for: .long)

        // Einkaufsliste: ein offener Freitext, ein gekaufter Eintrag aus einem Urteil, ein verworfener.
        var free = ShoppingEntryDraft(); free.freeText = "Salztabletten"; free.quantity = 2; free.estimatedPriceEuro = 7.5
        try purchase.addManually(free)
        var offer = OfferDraft(); offer.existingProductID = product.id; offer.quantity = 10; offer.priceEuro = 15
        offer.expiry = day.adding(days: 300)
        let assessed = try purchase.assess(offer)
        let item = ShoppingListItem(productID: product.id, freeText: "Testgel", plannedQuantity: 4, estimatedTotalPriceCents: 600)
        item.offerJSON = try JSONEncoder().encode(assessed.saved)
        item.expiryDay = day.adding(days: 300).isoString
        context.insert(item)
        try context.save()
        try purchase.markBought(item, with: BoughtDraft(item: item))
        var gone = ShoppingEntryDraft(); gone.productID = product.id; gone.quantity = 1
        try purchase.drop(try purchase.addManually(gone))
        // Verlauf: zusätzlich eine „teilweise kaufen“-Bewertung ohne Listeneintrag.
        let evaluation = try purchase.saveEvaluation(assessed)
        evaluation.verdictRaw = "buyPartially"; evaluation.verdictQuantity = 3

        // Packlisten: eine mit gesetztem Haken zur Session, eine fertige ohne Session.
        var list = PackListDraft(); list.title = "Lange Ausfahrt"; list.demandG = 100
        list.sessionID = training.sessions().first?.id
        let packed = try packing.create(list)
        try packing.setPacked(true, item: try #require(packing.items(of: packed).first))
        var other = PackListDraft(); other.title = "Feierabendrunde"; other.demandG = 50; other.reservePercent = 0
        try packing.finish(try packing.create(other))

        // Anlege-/Änderungszeitpunkte
        for p in try context.fetch(FetchDescriptor<Product>()) { p.createdAt = stamp(1); p.updatedAt = stamp(2) }
        for (i, b) in try context.fetch(FetchDescriptor<Batch>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
            b.createdAt = stamp(3 + i); b.updatedAt = stamp(13 + i)
        }
        for s in try context.fetch(FetchDescriptor<TrainingSession>()) { s.createdAt = stamp(20) }
        for r in try context.fetch(FetchDescriptor<CarbRateOverride>()) { r.updatedAt = stamp(21) }
        for (i, s) in try context.fetch(FetchDescriptor<ShoppingListItem>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
            s.createdAt = stamp(30 + i)
        }
        for (i, e) in try context.fetch(FetchDescriptor<PurchaseEvaluation>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
            e.createdAt = stamp(40 + i)
        }
        for (i, l) in try context.fetch(FetchDescriptor<PackList>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
            l.createdAt = stamp(50 + i)
        }
        try context.save()
    }

    /// Jedes gespeicherte Feld (außer `schemaVersion`) als Zeile: was hier gleich ist, ist vollständig wiederhergestellt.
    func dump(_ context: ModelContext) throws -> [String: [String]] {
        func s(_ v: Any?) -> String {
            switch v {
            case nil: "nil"
            case let d as Date: String(d.timeIntervalSinceReferenceDate)
            case let d as Data: d.base64EncodedString()
            case let v?: "\(v)"
            }
        }
        func rows<T: PersistentModel>(_: T.Type, _ fields: (T) -> [Any?]) throws -> [String] {
            try context.fetch(FetchDescriptor<T>()).map { fields($0).map(s).joined(separator: "|") }.sorted()
        }
        return [
            "Product": try rows(Product.self) { [$0.id, $0.name, $0.brand, $0.createdAt, $0.updatedAt] },
            "Batch": try rows(Batch.self) { [$0.id, $0.product?.id, $0.quantityPurchased, $0.source, $0.createdAt, $0.updatedAt] },
            "StockMovement": try rows(StockMovement.self) { [$0.id, $0.batch?.id, $0.typeRaw, $0.delta, $0.referenceID, $0.createdAt] },
            "TrainingSession": try rows(TrainingSession.self) { [$0.id, $0.day, $0.durationMinutes, $0.createdAt] },
            "CarbRateOverride": try rows(CarbRateOverride.self) { [$0.typeRaw, $0.carbsPerHour, $0.updatedAt] },
            "ShoppingListItem": try rows(ShoppingListItem.self) {
                [$0.id, $0.productID, $0.freeText, $0.plannedQuantity, $0.estimatedTotalPriceCents, $0.stateRaw, $0.createdAt,
                 $0.expiryDay, $0.offerJSON, $0.batchID]
            },
            "PurchaseEvaluation": try rows(PurchaseEvaluation.self) {
                [$0.id, $0.inputJSON, $0.verdictRaw, $0.reasonsJSON, $0.userDecisionRaw, $0.createdAt, $0.verdictQuantity]
            },
            "PackList": try rows(PackList.self) {
                [$0.id, $0.sessionID, $0.title, $0.targetCarbsG, $0.reservePercent, $0.stateRaw, $0.createdAt]
            },
            "PackListItem": try rows(PackListItem.self) {
                [$0.id, $0.packList?.id, $0.productID, $0.batchID, $0.plannedQuantity, $0.plannedCarbsG]
            },
        ]
    }

    @Test func roundTripIntoEmptyStoreRestoresEveryField() throws {
        let (source, backup) = make()
        try seed(source)
        let expected = try dump(source)
        for (type, rows) in expected { #expect(!rows.isEmpty, "Testdaten für \(type) fehlen") }

        let (target, backup2) = make()
        try backup2.importBackup(try backup.exportData())
        let actual = try dump(target)
        for type in expected.keys.sorted() { #expect(actual[type] == expected[type], "\(type) unvollständig") }
    }

    /// Der Haken in der Packliste hängt an der Buchung (referenceID = Posten-ID) und übersteht die Wiederherstellung.
    @Test func packedTickSurvivesRestore() throws {
        let (source, backup) = make()
        try seed(source)
        let (target, backup2) = make()
        try backup2.importBackup(try backup.exportData())
        let packing = PackService(context: target)
        let list = try #require(packing.lists().first { $0.title == "Lange Ausfahrt" })
        #expect(packing.items(of: list).filter { packing.state(of: $0).isPacked }.count == 1)
    }

    @Test func secondImportCreatesNoDuplicates() throws {
        let (source, backup) = make()
        try seed(source)
        let data = try backup.exportData()
        let (target, backup2) = make()
        try backup2.importBackup(data)
        let first = try dump(target)
        #expect(backup2.preview(data) == .ok(newItems: 0))
        #expect(try backup2.importBackup(data).total == 0)
        #expect(try dump(target) == first)
        // Auch auf dem Gerät, von dem die Sicherung stammt
        let before = try dump(source)
        #expect(try backup.importBackup(data).total == 0)
        #expect(try dump(source) == before)
    }

    /// Eine nach der Sicherung neu berechnete Packliste bekommt beim Import nicht die alten Posten dazu.
    @Test func knownPackListKeepsItsCurrentItems() throws {
        let (source, backup) = make()
        try seed(source)
        let data = try backup.exportData()
        let list = try #require(try source.fetch(FetchDescriptor<PackList>()).first { $0.title == "Lange Ausfahrt" })
        for item in list.items ?? [] { source.delete(item) }
        try source.save()
        try backup.importBackup(data)
        #expect(try source.fetch(FetchDescriptor<PackListItem>()).allSatisfy { $0.packList?.title == "Feierabendrunde" })
    }

    /// Alte Sicherung (vor dieser Änderung geschrieben): die neuen Felder fehlen ganz.
    @Test func oldBackupWithoutNewFieldsStillImports() throws {
        let (source, backup) = make()
        try seed(source)
        var json = try #require(try JSONSerialization.jsonObject(with: try backup.exportData()) as? [String: Any])
        for key in ["shoppingItems", "purchaseEvaluations", "packLists", "recordTimes", "carbRateTimes"] { json[key] = nil }
        let old = try JSONSerialization.data(withJSONObject: json)

        let (target, backup2) = make()
        let start = Date.now
        let result = try backup2.importBackup(old)
        #expect(result.products == 1 && result.sessions == 1 && result.rates == 1)
        let restored = try dump(target)
        #expect(restored["Product"]?.count == 1 && restored["StockMovement"]?.isEmpty == false)
        #expect(restored["ShoppingListItem"] == [] && restored["PurchaseEvaluation"] == [] && restored["PackList"] == [])
        // Ohne Zeitpunkte gilt wie bisher der Zeitpunkt des Imports.
        #expect(try target.fetch(FetchDescriptor<Product>()).allSatisfy { $0.createdAt >= start })
        #expect(try backup2.importBackup(old).total == 0)
    }
}
