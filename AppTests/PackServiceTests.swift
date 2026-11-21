import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

@MainActor
@Suite struct PackServiceTests {
    let today = CalendarDay(year: 2026, month: 11, day: 23)
    let container: ModelContainer
    let context: ModelContext
    let inventory: InventoryService
    let pack: PackService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        let day = CalendarDay(year: 2026, month: 11, day: 23)
        inventory = InventoryService(context: context, today: { day })
        pack = PackService(context: context, today: { day })
    }

    @discardableResult
    func product(_ name: String, _ category: ProductCategory, carbs: Double, qty: Int, portion: Double = 1,
                 unit: BaseUnit = .piece, expiry: CalendarDay? = nil) throws -> Product {
        var d = ProductDraft()
        d.name = name; d.category = category; d.baseUnit = unit; d.portionAmount = portion
        d.carbsPerPortionG = carbs; d.quantity = qty; d.expiry = expiry
        return try inventory.createProduct(d)
    }

    func tv7Stock() throws {
        try product("Gel", .gel, carbs: 25, qty: 50)
        try product("Drink", .drink, carbs: 40, qty: 1000, portion: 50, unit: .gram)
        try product("Riegel", .bar, carbs: 30, qty: 20)
    }

    func tv7Draft() -> PackListDraft {
        var d = PackListDraft()
        d.title = "So-Langfahrt"; d.demandG = 320; d.reservePercent = 0
        d.useShares = true; d.sharesPercent = [.gel: 50, .drink: 30, .bar: 20]
        return d
    }

    func item(_ list: PackList, _ category: ProductCategory) throws -> PackListItem {
        let products = try context.fetch(FetchDescriptor<Product>())
        let ids = Set(products.filter { $0.category == category }.map(\.id))
        return try #require(pack.items(of: list).first { $0.productID.map(ids.contains) ?? false })
    }

    func stock(_ name: String) throws -> Int {
        let p = try #require(try context.fetch(FetchDescriptor<Product>()).first { $0.name == name })
        return inventory.stock(of: p)
    }

    // AC-L1 (TV-7) über die App
    @Test func listFollowsTV7() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        let items = pack.items(of: list)
        #expect(items.count == 3)
        #expect(items.reduce(0) { $0 + $1.plannedCarbsG } == 330)
        #expect(try item(list, .gel).plannedQuantity == 6)
        #expect(try item(list, .drink).plannedQuantity == 150) // 3 Portionen à 50 g Pulver
        #expect(try item(list, .bar).plannedQuantity == 2)
        #expect(list.stateRaw == "draft" && pack.shortfallG(of: list) == 0)
        #expect(try stock("Gel") == 50, "Planen bucht nichts")
    }

    // AC-L2: ein Haken = genau eine Buchung, Haken weg = genau eine Gegenbuchung, am Ende stimmt der Bestand
    @Test func tickingBooksExactlyOneMovementPerChange() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        let gel = try item(list, .gel)
        let m1 = try #require(try pack.setPacked(true, item: gel))
        #expect(m1.typeRaw == MovementType.pack.rawValue && m1.delta == -6 && m1.referenceID == gel.id)
        #expect(try stock("Gel") == 44 && list.stateRaw == "packing")
        #expect(try pack.setPacked(true, item: gel) == nil, "schon gepackt: keine zweite Buchung")
        #expect(try stock("Gel") == 44)
        let m2 = try #require(try pack.setPacked(false, item: gel))
        #expect(m2.typeRaw == MovementType.reversal.rawValue && m2.delta == 6 && m2.reversesMovementID == m1.id)
        #expect(try stock("Gel") == 50)
        #expect(try pack.setPacked(false, item: gel) == nil)
        // wieder setzen und wieder entfernen: der Ledger zählt jede Buchung genau einmal
        _ = try pack.setPacked(true, item: gel)
        #expect(try stock("Gel") == 44)
        _ = try pack.setPacked(false, item: gel)
        #expect(try stock("Gel") == 50)
        let all = try context.fetch(FetchDescriptor<StockMovement>()).filter { $0.referenceID == gel.id }
        #expect(all.count == 4)
        #expect(Set(all.compactMap(\.idempotencyKey)).count == 2, "zwei verschiedene Schlüssel für zwei Pack-Runden")
        #expect(pack.state(of: gel).isPacked == false)
    }

    // AC-L3: zweites Gerät bucht denselben Haken → Ledger zählt einmal
    @Test func sameTickFromTwoDevicesCountsOnce() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        let gel = try item(list, .gel)
        let first = try #require(try pack.setPacked(true, item: gel))
        // Die Buchung des anderen Geräts: gleicher Schlüssel, später synchronisiert
        let twin = StockMovement(batch: try #require(first.batch), type: .pack, delta: -6,
                                 idempotencyKey: first.idempotencyKey, referenceID: gel.id)
        context.insert(twin)
        try context.save()
        #expect(try stock("Gel") == 44)
        #expect(inventory.ledger().ignoredMovementIDs.count == 1)
    }

    // AC-L4: Fehlbetrag
    @Test func shortfallIsReported() throws {
        try product("Gel", .gel, carbs: 25, qty: 4) // 100 g
        var d = PackListDraft()
        d.title = "Zu wenig"; d.demandG = 300; d.reservePercent = 0
        let list = try pack.create(d)
        #expect(pack.items(of: list).reduce(0) { $0 + $1.plannedCarbsG } == 100)
        #expect(abs(pack.shortfallG(of: list) - 200) < 1e-9)
    }

    // AC-L5: FEFO über zwei Chargen
    @Test func fefoSplitsAcrossBatches() throws {
        let gel = try product("Gel", .gel, carbs: 25, qty: 3, expiry: today.adding(days: 30))
        _ = try inventory.addBatch(to: gel, quantity: 10, expiry: today.adding(days: 200))
        var d = PackListDraft()
        d.title = "FEFO"; d.demandG = 125; d.reservePercent = 0 // 5 Gele
        let list = try pack.create(d)
        let items = pack.items(of: list)
        #expect(items.count == 2)
        let early = try #require(items.first { $0.plannedQuantity == 3 })
        let late = try #require(items.first { $0.plannedQuantity == 2 })
        let earlyBatch = try #require(gel.batches?.first { $0.expiryDay == today.adding(days: 30).isoString })
        #expect(early.batchID == earlyBatch.id && late.batchID != earlyBatch.id)
    }

    // AC-L6: Rest zurücklegen, netto
    @Test func putBackIsNet() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        let gel = try item(list, .gel)
        #expect(throws: PackService.Failure.nothingToReturn) { try pack.putBack(1, item: gel) }
        try pack.setPacked(true, item: gel)
        #expect(throws: PackService.Failure.returnTooMuch) { try pack.putBack(7, item: gel) }
        let ret = try pack.putBack(2, item: gel)
        #expect(ret.typeRaw == MovementType.return.rawValue && ret.delta == 2)
        #expect(try stock("Gel") == 46)
        let s = pack.state(of: gel)
        #expect(s.packedQuantity == 6 && s.returnedQuantity == 2 && s.netConsumed == 4 && s.returnable == 4)
    }

    @Test func finishedListIsReadOnly() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        let gel = try item(list, .gel)
        try pack.setPacked(true, item: gel)
        try pack.finish(list)
        #expect(list.stateRaw == "done")
        #expect(throws: PackService.Failure.listFinished) { try pack.setPacked(false, item: gel) }
        #expect(throws: PackService.Failure.listFinished) { try pack.putBack(1, item: gel) }
        try pack.delete(list) // fertige Liste darf weg, die Buchungen bleiben
        #expect(try stock("Gel") == 44)
    }

    @Test func openListWithTicksCannotBeDeleted() throws {
        try tv7Stock()
        let list = try pack.create(tv7Draft())
        try pack.setPacked(true, item: try item(list, .gel))
        #expect(throws: PackService.Failure.hasPackedItems) { try pack.delete(list) }
        try pack.setPacked(false, item: try item(list, .gel))
        try pack.delete(list)
        #expect(pack.lists().isEmpty)
    }

    @Test func tickFailsWhenBatchWasEmptiedMeanwhile() throws {
        let gel = try product("Gel", .gel, carbs: 25, qty: 6)
        var d = PackListDraft()
        d.title = "Test"; d.demandG = 150; d.reservePercent = 0
        let list = try pack.create(d)
        try inventory.removeFEFO(quantity: 3, from: gel) // jemand isst zu Hause drei Gele
        #expect(throws: PackService.Failure.insufficientStock(shortfall: 3)) { try pack.setPacked(true, item: try #require(pack.items(of: list).first)) }
        #expect(try stock("Gel") == 3 && list.stateRaw == "draft")
    }

    @Test func recalculateOnlyInDraft() throws {
        let gel = try product("Gel", .gel, carbs: 25, qty: 6)
        var d = PackListDraft()
        d.title = "Test"; d.demandG = 100; d.reservePercent = 0
        let list = try pack.create(d)
        #expect(pack.items(of: list).first?.plannedQuantity == 4)
        try inventory.removeFEFO(quantity: 3, from: gel)
        try pack.recalculate(list, demandG: 100)
        #expect(pack.items(of: list).first?.plannedQuantity == 3 && abs(pack.shortfallG(of: list) - 25) < 1e-9)
        try pack.setPacked(true, item: try #require(pack.items(of: list).first))
        #expect(throws: PackService.Failure.listFinished) { try pack.recalculate(list, demandG: 100) }
    }

    @Test func draftValidation() {
        var d = PackListDraft()
        #expect(d.problems == [.titleEmpty, .targetNotPositive])
        d.title = "x"; d.demandG = 10; d.reservePercent = 120; d.useShares = true; d.sharesPercent = [:]
        #expect(d.problems == [.reserveOutOfRange, .sharesEmpty])
        d.reservePercent = 10; d.sharesPercent = [.gel: 100]
        #expect(d.problems.isEmpty && abs(d.targetG - 11) < 1e-9 && d.effectiveShares == [.gel: 100])
        d.useShares = false
        #expect(d.effectiveShares.isEmpty)
    }
}
