import Foundation
import Testing
@testable import CarbStockCore

@Suite struct LedgerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let today = CalendarDay(year: 2026, month: 11, day: 21)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func gel() -> ProductInfo { ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25) }

    @Test func stockIsSumOfDeltas() {
        let b = UUID()
        let l = Ledger([Movement(batchID: b, type: .purchase, delta: 10, occurredAt: t0),
                        Movement(batchID: b, type: .consume, delta: -3, occurredAt: t0)])
        #expect(l.quantity(ofBatch: b) == 7)
        #expect(l.quantity(ofBatch: UUID()) == 0) // Bestand 0 / unbekannte Charge
    }

    @Test func duplicateIdempotencyKeyCountsOldestOnly() {
        let b = UUID(); let item = UUID()
        let key = IdempotencyKey.pack(itemID: item)
        let young = Movement(batchID: b, type: .pack, delta: -1, occurredAt: t0, createdAt: at(10), idempotencyKey: key)
        let old = Movement(batchID: b, type: .pack, delta: -1, occurredAt: t0, createdAt: at(1), idempotencyKey: key)
        let l = Ledger([young, old])
        #expect(l.quantity(ofBatch: b) == -1)
        #expect(l.ignoredMovementIDs == [young.id])
    }

    @Test func idempotencyTieBreaksOnID() {
        let b = UUID()
        let m1 = Movement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, batchID: b, type: .consume, delta: -1, occurredAt: t0, idempotencyKey: "k")
        let m2 = Movement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, batchID: b, type: .consume, delta: -1, occurredAt: t0, idempotencyKey: "k")
        #expect(Ledger([m2, m1]).ignoredMovementIDs == [m2.id])
    }

    @Test func idempotencyKeyHelpers() {
        let id = UUID()
        #expect(IdempotencyKey.pack(itemID: id) == "pack:\(id.uuidString)")
        #expect(IdempotencyKey.expire(batchID: id) == "expire:\(id.uuidString)")
        #expect(IdempotencyKey.purchase(batchID: id) == "purchase:\(id.uuidString)")
    }

    @Test func reversalCountsOncePerOriginalAndNeedsOriginal() {
        let b = UUID()
        let buy = Movement(batchID: b, type: .purchase, delta: 10, occurredAt: t0)
        let use = Movement(batchID: b, type: .consume, delta: -4, occurredAt: t0, createdAt: at(1))
        let r1 = Movement(batchID: b, type: .reversal, delta: 4, occurredAt: t0, createdAt: at(2), reversesMovementID: use.id)
        let r2 = Movement(batchID: b, type: .reversal, delta: 4, occurredAt: t0, createdAt: at(3), reversesMovementID: use.id)
        let orphan = Movement(batchID: b, type: .reversal, delta: 99, occurredAt: t0, createdAt: at(4), reversesMovementID: UUID())
        let none = Movement(batchID: b, type: .reversal, delta: 99, occurredAt: t0, createdAt: at(5))
        let l = Ledger([buy, use, r1, r2, orphan, none])
        #expect(l.quantity(ofBatch: b) == 10)
        #expect(l.ignoredMovementIDs == [r2.id, orphan.id, none.id])
    }

    /// TV-8: two devices each book -1 at stock 1.
    @Test func negativeStockIsReportedNotClamped() {
        let b = UUID()
        let l = Ledger([Movement(batchID: b, type: .purchase, delta: 1, occurredAt: t0),
                        Movement(batchID: b, type: .consume, delta: -1, occurredAt: at(1), idempotencyKey: "dev1"),
                        Movement(batchID: b, type: .consume, delta: -1, occurredAt: at(1), idempotencyKey: "dev2")])
        #expect(l.quantity(ofBatch: b) == -1)
        #expect(l.conflicts() == [StockConflict(batchID: b, quantity: -1)])
        #expect(l.conflicts()[0].suggestedCorrection == 1)
    }

    @Test func packStatusIsDerivedFromNetSum() {
        let b = UUID(); let item = UUID()
        let pack = Movement(batchID: b, type: .pack, delta: -2, occurredAt: t0, createdAt: at(1), idempotencyKey: IdempotencyKey.pack(itemID: item), referenceID: item)
        #expect(Ledger([pack]).isPacked(itemID: item))
        #expect(Ledger([pack]).packedQuantity(itemID: item) == 2)
        let rev = Movement(batchID: b, type: .reversal, delta: 2, occurredAt: t0, createdAt: at(2), reversesMovementID: pack.id, referenceID: item)
        #expect(!Ledger([pack, rev]).isPacked(itemID: item))
        let rev2 = Movement(batchID: b, type: .reversal, delta: 2, occurredAt: t0, createdAt: at(2), reversesMovementID: pack.id) // inherits reference
        #expect(!Ledger([pack, rev2]).isPacked(itemID: item))
        #expect(!Ledger([]).isPacked(itemID: item))
    }

    /// TV-5
    @Test func fefoSplitsAcrossBatches() {
        let p = gel()
        let a = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 10, expiryDate: CalendarDay(year: 2027, month: 3, day: 1))
        let bb = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 10, expiryDate: CalendarDay(year: 2027, month: 9, day: 1))
        let ledger = Ledger([Movement(batchID: a.id, type: .purchase, delta: 10, occurredAt: t0),
                             Movement(batchID: bb.id, type: .purchase, delta: 10, occurredAt: t0)])
        let r = FEFO.allocate(quantity: 12, productID: p.id, batches: [bb, a], ledger: ledger, today: today, occurredAt: t0)
        #expect(r.movements.map(\.batchID) == [a.id, bb.id])
        #expect(r.movements.map(\.delta) == [-10, -2])
        #expect(r.shortfall == 0 && r.allocatedQuantity == 12)
    }

    @Test func fefoSkipsExpiredUnlessUsedAnywayAndNoExpiryLast() {
        let p = gel()
        let expired = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 5, expiryDate: today.adding(days: -1)) // MHD gestern
        let lastDay = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 5, expiryDate: today) // MHD-Tag = nicht abgelaufen
        let none = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 5)
        let ledger = Ledger([expired, lastDay, none].map { Movement(batchID: $0.id, type: .purchase, delta: 5, occurredAt: t0) })
        let r = FEFO.allocate(quantity: 8, productID: p.id, batches: [none, expired, lastDay], ledger: ledger, today: today, occurredAt: t0)
        #expect(r.movements.map(\.batchID) == [lastDay.id, none.id])
        #expect(r.movements.map(\.delta) == [-5, -3])
        var used = expired; used.useDespiteExpiry = true
        let r2 = FEFO.allocate(quantity: 8, productID: p.id, batches: [none, used, lastDay], ledger: ledger, today: today, occurredAt: t0)
        #expect(r2.movements.map(\.batchID) == [used.id, lastDay.id])
    }

    @Test func fefoShortfallAndEdgeCases() {
        let p = gel()
        let a = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 3)
        let ledger = Ledger([Movement(batchID: a.id, type: .purchase, delta: 3, occurredAt: t0)])
        let r = FEFO.allocate(quantity: 5, productID: p.id, batches: [a], ledger: ledger, today: today, occurredAt: t0)
        #expect(r.shortfall == 2 && r.allocatedQuantity == 3)
        #expect(FEFO.allocate(quantity: 0, productID: p.id, batches: [a], ledger: ledger, today: today, occurredAt: t0).movements.isEmpty)
        // Bestand 0 und negativer Bestand liefern nichts
        let neg = Ledger([Movement(batchID: a.id, type: .consume, delta: -1, occurredAt: t0)])
        let r2 = FEFO.allocate(quantity: 1, productID: p.id, batches: [a], ledger: neg, today: today, occurredAt: t0)
        #expect(r2.movements.isEmpty && r2.shortfall == 1)
        var archived = a; archived.isArchived = true
        #expect(FEFO.allocate(quantity: 1, productID: p.id, batches: [archived], ledger: ledger, today: today, occurredAt: t0).shortfall == 1)
    }

    /// AC-B1: powder 40 g portion / 36 g carbs, 1000 g for 25 EUR.
    @Test func priceMetrics() {
        let powder = ProductInfo(name: "Pulver", category: .drink, baseUnit: .gram, portionAmount: 40, carbsPerPortionG: 36)
        let batch = BatchInfo(productID: powder.id, purchaseDate: today, quantityPurchased: 1000, totalPriceCents: 2500)
        #expect(PriceMetrics.totalCarbsG(batch: batch, product: powder) == 900)
        #expect(abs(PriceMetrics.pricePer100gCarbs(batch: batch, product: powder)! - 2.7778) < 0.001)
        #expect(abs(PriceMetrics.carbsPerEuro(batch: batch, product: powder)! - 36) < 1e-9)
        // TV-3
        let g = gel()
        let sixty = BatchInfo(productID: g.id, purchaseDate: today, quantityPurchased: 60, totalPriceCents: 3000)
        #expect(abs(PriceMetrics.pricePer100gCarbs(batch: sixty, product: g)! - 2.0) < 1e-9)
        // AC-B6: ohne Preis nil
        let free = BatchInfo(productID: g.id, purchaseDate: today, quantityPurchased: 60)
        #expect(PriceMetrics.pricePer100gCarbs(batch: free, product: g) == nil)
    }
}
