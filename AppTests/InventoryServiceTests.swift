import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

@MainActor
@Suite struct InventoryServiceTests {
    let today = CalendarDay(year: 2026, month: 11, day: 21)
    let container: ModelContainer // keep alive: the context does not retain it
    let context: ModelContext
    let service: InventoryService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        let day = CalendarDay(year: 2026, month: 11, day: 21)
        service = InventoryService(context: context, today: { day })
    }

    func gel(_ name: String = "Gel") throws -> Product {
        var d = ProductDraft()
        d.name = name; d.category = .gel; d.carbsPerPortionG = 25
        return try service.createProduct(d)
    }

    // AC-B1
    @Test func powderBatchCarbsAndPrice() throws {
        var d = ProductDraft()
        d.name = "Pulver"; d.category = .drink; d.baseUnit = .gram
        d.portionAmount = 40; d.carbsPerPortionG = 36
        d.quantity = 1000; d.totalPriceCents = 2500
        let p = try service.createProduct(d)
        let batch = try #require(p.batches?.first)
        #expect(p.batches?.count == 1)
        #expect(batch.movements?.count == 1)
        #expect(batch.movements?.first?.typeRaw == MovementType.purchase.rawValue)
        #expect(service.stock(of: batch) == 1000)
        #expect(abs(service.summary(of: p).carbsTotalG - 900) < 1e-9)
        let info = try #require(batch.info)
        let eur = try #require(PriceMetrics.pricePer100gCarbs(batch: info, product: p.info))
        #expect(String(format: "%.2f", eur) == "2.78")
    }

    // AC-B2
    @Test func batchesStaySeparateAndSumMatches() throws {
        let p = try gel()
        try service.addBatch(to: p, quantity: 10, expiry: CalendarDay(year: 2027, month: 3, day: 1))
        try service.addBatch(to: p, quantity: 5, expiry: CalendarDay(year: 2027, month: 9, day: 1))
        #expect(service.activeBatches(of: p).count == 2)
        #expect(service.activeBatches(of: p).map { service.stock(of: $0) }.sorted() == [5, 10])
        #expect(service.stock(of: p) == 15)
        #expect(service.summary(of: p).stock == 15)
    }

    // AC-B3 / TV-5
    @Test func removalFollowsFEFO() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10, expiry: CalendarDay(year: 2027, month: 9, day: 1))
        let a = try service.addBatch(to: p, quantity: 10, expiry: CalendarDay(year: 2027, month: 3, day: 1))
        try service.removeFEFO(quantity: 12, from: p)
        #expect(service.stock(of: a) == 0)
        #expect(service.stock(of: b) == 8)
        // Per batch: A −10, B −2.
        let aDeltas = (a.movements ?? []).filter { $0.typeRaw == "consume" }.map(\.delta)
        let bDeltas = (b.movements ?? []).filter { $0.typeRaw == "consume" }.map(\.delta)
        #expect(aDeltas == [-10] && bDeltas == [-2])
    }

    @Test func quickBookHitsEarliestNonExpiredBatch() throws {
        let p = try gel()
        let expired = try service.addBatch(to: p, quantity: 3, expiry: CalendarDay(year: 2026, month: 10, day: 1))
        let none = try service.addBatch(to: p, quantity: 3)
        let late = try service.addBatch(to: p, quantity: 3, expiry: CalendarDay(year: 2027, month: 6, day: 1))
        let early = try service.addBatch(to: p, quantity: 3, expiry: CalendarDay(year: 2027, month: 1, day: 1))
        try service.quickBook(-1, on: p)
        #expect(service.stock(of: early) == 2)
        try service.quickBook(+1, on: p)
        #expect(service.stock(of: early) == 3)
        #expect([expired, none, late].allSatisfy { service.stock(of: $0) == 3 })
        // Without any dated usable batch: the one without best-before date.
        let q = try gel("Q")
        let ex = try service.addBatch(to: q, quantity: 2, expiry: CalendarDay(year: 2026, month: 1, day: 1))
        let nd = try service.addBatch(to: q, quantity: 2)
        try service.quickBook(-1, on: q)
        #expect(service.stock(of: nd) == 1 && service.stock(of: ex) == 2)
    }

    @Test func reasonsAndInflow() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10)
        try service.book(.discard, quantity: 2, on: b)
        try service.book(.consume, quantity: 3, on: b)
        try service.book(.return, quantity: 1, on: b)
        try service.adjust(by: -1, on: b)
        #expect(service.stock(of: b) == 5)
        #expect(throws: InventoryService.Failure.wrongMovementType) { try service.book(.reversal, quantity: 1, on: b) }
        #expect(throws: InventoryService.Failure.quantityNotPositive) { try service.book(.consume, quantity: 0, on: b) }
    }

    @Test func negativeStockIsCorrectedByAdjust() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 1)
        try service.book(.consume, quantity: 1, on: b)
        try service.book(.consume, quantity: 1, on: b)
        #expect(service.stock(of: b) == -1)
        #expect(service.summary(of: p).isConflict)
        try service.correctNegative(b)
        #expect(service.stock(of: b) == 0)
        #expect((b.movements ?? []).count == 4) // history kept, nothing edited
    }

    // AC-B4
    @Test func productWithMovementsIsArchivedAndRestorable() throws {
        let p = try gel()
        try service.addBatch(to: p, quantity: 4)
        #expect(try service.remove(p) == .archived)
        #expect(try context.fetchCount(FetchDescriptor<StockMovement>()) == 1)
        let visible = InventoryList.apply(InventoryFilter(), to: [service.summary(of: p)], today: today)
        #expect(visible.isEmpty)
        let archived = InventoryList.apply(InventoryFilter(mode: .archive), to: [service.summary(of: p)], today: today)
        #expect(archived.count == 1)
        try service.restore(p)
        #expect(!p.isArchived)
        // Never booked: hard delete is fine.
        let empty = try gel("Leer")
        #expect(try service.remove(empty) == .deleted)
    }

    // AC-B6
    @Test func noPriceNoEuroFigure() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10)
        let info = try #require(b.info)
        #expect(PriceMetrics.pricePer100gCarbs(batch: info, product: p.info) == nil)
        #expect(ExpiryBadge.of(nil, today: today).status == .noExpiry)
        #expect(ExpiryBadge.of(nil, today: today).text == "ohne MHD")
    }

    @Test func validation() throws {
        var d = ProductDraft()
        #expect(d.problems == [.nameMissing, .carbsNotPositive])
        d.name = "X"; d.carbsPerPortionG = 20; d.baseUnit = .gram; d.portionAmount = 0
        #expect(d.problems == [.portionNotPositive])
        #expect(throws: InventoryService.Failure.invalid([.portionNotPositive])) { try service.createProduct(d) }
    }

    @Test func expiryBadgeBoundaries() {
        #expect(ExpiryBadge.of(today.adding(days: -1), today: today) == ExpiryBadge(status: .expired, days: -1))
        #expect(ExpiryBadge.of(today.adding(days: -1), today: today).text == "abgelaufen seit 1 Tag")
        #expect(ExpiryBadge.of(today, today: today) == ExpiryBadge(status: .red, days: 0))
        #expect(ExpiryBadge.of(today.adding(months: 3), today: today).status == .yellow)
        #expect(ExpiryBadge.of(today.adding(months: 6), today: today).status == .green)
    }

    // 5.9 Nr. 4: same idempotencyKey counts once (two devices, one business event).
    @Test func duplicateIdempotencyKeyCountsOnce() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10)
        let key = IdempotencyKey.pack(itemID: UUID())
        context.insert(StockMovement(batch: b, type: .pack, delta: -3, idempotencyKey: key))
        context.insert(StockMovement(batch: b, type: .pack, delta: -3, idempotencyKey: key))
        try context.save()
        #expect((b.movements ?? []).count == 3)
        #expect(service.stock(of: b) == 7)
        #expect(service.stock(of: p) == 7)
        #expect(service.summary(of: p).stock == 7)
    }

    @Test func reversalCancelsOriginalOnce() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10)
        let use = try service.book(.consume, quantity: 4, on: b)
        #expect(service.stock(of: b) == 6)
        try service.reverse(use)
        #expect(service.stock(of: b) == 10)
        try service.reverse(use) // second storno of the same original is ignored
        #expect(service.stock(of: b) == 10)
        // A reversal pointing at nothing is ignored.
        context.insert(StockMovement(batch: b, type: .reversal, delta: 99, reversesMovementID: UUID()))
        try context.save()
        #expect(service.stock(of: b) == 10)
    }

    @Test func fefoSkipsExpiredAndRefusesShortfall() throws {
        let p = try gel()
        let expired = try service.addBatch(to: p, quantity: 5, expiry: CalendarDay(year: 2026, month: 10, day: 1))
        let ok = try service.addBatch(to: p, quantity: 2, expiry: CalendarDay(year: 2027, month: 1, day: 1))
        #expect(throws: InventoryService.Failure.insufficientStock(shortfall: 1)) {
            try service.removeFEFO(quantity: 3, from: p)
        }
        #expect(service.stock(of: ok) == 2) // nothing was booked
        try service.setUseDespiteExpiry(true, on: expired)
        try service.removeFEFO(quantity: 3, from: p)
        #expect(service.stock(of: expired) == 2 && service.stock(of: ok) == 2)
    }

    // AC-H3
    @Test func useFirstListOrdersExpiredThenEarliestThenUndated() throws {
        let p = try gel()
        let none = try service.addBatch(to: p, quantity: 1)
        let late = try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 200))
        let soon = try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 10))
        let old = try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: -3))
        let empty = try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 5))
        try service.book(.consume, quantity: 1, on: empty)
        let archived = try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 1))
        try service.setArchived(true, batch: archived)
        let list = service.useFirst()
        #expect(list.map(\.id) == [old.id, soon.id, late.id, none.id])
        #expect(list.first?.status == .expired)
    }

    // AC-H4: disposal is explicit, books the whole rest as `expire`, and only once.
    @Test func disposeBooksRemainingAsExpireOnce() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 10, expiry: today.adding(days: -1))
        try service.book(.consume, quantity: 3, on: b)
        #expect(service.stock(of: b) == 7) // nothing is disposed automatically
        let m = try #require(try service.dispose(b))
        #expect(m.typeRaw == "expire" && m.delta == -7)
        #expect(m.idempotencyKey == IdempotencyKey.expire(batchID: b.id))
        #expect(service.stock(of: b) == 0)
        #expect(try service.dispose(b) == nil) // nothing left, no second booking
        // A second device booking the same disposal does not count twice.
        context.insert(StockMovement(batch: b, type: .expire, delta: -7, idempotencyKey: IdempotencyKey.expire(batchID: b.id)))
        try context.save()
        #expect(service.stock(of: b) == 0)
        #expect(service.useFirst().isEmpty)
    }

    @Test func useDespiteExpiryIsReversible() throws {
        let p = try gel()
        let b = try service.addBatch(to: p, quantity: 4, expiry: today.adding(days: -1))
        try service.setUseDespiteExpiry(true, on: b)
        try service.removeFEFO(quantity: 1, from: p)
        #expect(service.stock(of: b) == 3)
        try service.setUseDespiteExpiry(false, on: b)
        #expect(throws: InventoryService.Failure.insufficientStock(shortfall: 1)) { try service.removeFEFO(quantity: 1, from: p) }
    }

    @Test func useFirstSectionsSeparateExpiredAndSoon() throws {
        let p = try gel()
        try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: -1))
        try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 60))
        try service.addBatch(to: p, quantity: 1, expiry: today.adding(days: 61))
        try service.addBatch(to: p, quantity: 1)
        let s = UseFirstSections(service.useFirst())
        #expect(s.expired.count == 1 && s.soon.count == 1 && s.rest.count == 2)
        #expect(s.attentionCount == 2)
    }

    @Test func setFlavorTrimsClearsAndKeepsStock() throws {
        let p = try gel()
        let before = service.stock(of: p)
        try service.setFlavor("  Zitrone ", on: p)
        #expect(p.flavor == "Zitrone" && p.displayName.hasSuffix(" · Zitrone") && service.stock(of: p) == before)
        try service.setFlavor("   ", on: p)
        #expect(p.flavor == nil && p.displayName == p.name)
    }

    // Koffein- und Laktatzusatz (Geloption)
    @Test func setAdditivesKeepsStockAndShowsInName() throws {
        let p = try gel()
        let before = service.stock(of: p)
        #expect(!p.hasCaffeine && !p.hasLactate)
        try service.setAdditives(caffeine: true, lactate: false, on: p)
        #expect(p.hasCaffeine && !p.hasLactate && p.displayName.hasSuffix(" · mit Koffein") && service.stock(of: p) == before)
        try service.setAdditives(caffeine: true, lactate: true, on: p)
        #expect(p.displayName.hasSuffix(" · mit Koffein · mit Laktat"))
        try service.setAdditives(caffeine: false, lactate: false, on: p)
        #expect(p.displayName == p.name)
    }

    @Test func createProductTakesAdditivesFromDraft() throws {
        var d = ProductDraft()
        d.name = "Gel"; d.carbsPerPortionG = 25; d.quantity = 2; d.hasCaffeine = true; d.hasLactate = true
        let p = try service.createProduct(d)
        #expect(p.hasCaffeine && p.hasLactate)
    }
}
