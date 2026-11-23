import Foundation
import Testing
@testable import CarbStockCore

/// Zähl-Durchgang: aus „gezählt“ gegen „Soll“ werden nur Differenz-Korrekturen (Spec 4.6).
@Suite struct InventoryCountTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let today = CalendarDay(year: 2026, month: 11, day: 21)
    let product = UUID()

    func batch(_ expiry: CalendarDay?, archived: Bool = false, anyway: Bool = false, bought: Int = 1) -> BatchInfo {
        BatchInfo(productID: product, purchaseDate: CalendarDay(year: 2026, month: 1, day: bought), quantityPurchased: 10,
                  expiryDate: expiry, useDespiteExpiry: anyway, isArchived: archived)
    }

    func ledger(_ stock: [(BatchInfo, Int)]) -> Ledger {
        Ledger(stock.map { Movement(batchID: $0.0.id, type: .purchase, delta: $0.1, occurredAt: t0) })
    }

    func plan(_ counted: Int, _ stock: [(BatchInfo, Int)]) -> [CountAdjustment] {
        InventoryCount.plan(counted: counted, batches: stock.map(\.0), ledger: ledger(stock), today: today)
    }

    @Test func sameCountBooksNothing() {
        let a = batch(CalendarDay(year: 2027, month: 1, day: 1))
        #expect(plan(8, [(a, 8)]).isEmpty)
    }

    @Test func moreThanExpectedAddsToFirstUsableBatchInFEFOOrder() {
        let late = batch(CalendarDay(year: 2027, month: 6, day: 1))
        let soon = batch(CalendarDay(year: 2027, month: 1, day: 1))
        #expect(plan(9, [(late, 3), (soon, 4)]) == [CountAdjustment(batchID: soon.id, delta: 2)])
    }

    @Test func moreThanExpectedSkipsExpiredBatchButFallsBackToIt() {
        let expired = batch(CalendarDay(year: 2026, month: 10, day: 1))
        let fresh = batch(CalendarDay(year: 2027, month: 1, day: 1))
        #expect(plan(6, [(expired, 2), (fresh, 3)]) == [CountAdjustment(batchID: fresh.id, delta: 1)])
        #expect(plan(6, [(expired, 5)]) == [CountAdjustment(batchID: expired.id, delta: 1)])
    }

    @Test func fewerThanExpectedRemovesInFEFOOrderAcrossBatches() {
        let soon = batch(CalendarDay(year: 2027, month: 1, day: 1))
        let late = batch(CalendarDay(year: 2027, month: 6, day: 1))
        let none = batch(nil)
        let result = plan(4, [(none, 5), (late, 3), (soon, 2)])
        #expect(result == [CountAdjustment(batchID: soon.id, delta: -2), CountAdjustment(batchID: late.id, delta: -3),
                           CountAdjustment(batchID: none.id, delta: -1)])
    }

    @Test func expiredBatchesAreReducedLastBecauseTheyDoNotCountForTheForecast() {
        let expired = batch(CalendarDay(year: 2026, month: 10, day: 1))
        let fresh = batch(CalendarDay(year: 2027, month: 1, day: 1))
        #expect(plan(3, [(expired, 2), (fresh, 4)]) == [CountAdjustment(batchID: fresh.id, delta: -3)])
        #expect(plan(1, [(expired, 2), (fresh, 4)]) == [CountAdjustment(batchID: fresh.id, delta: -4),
                                                         CountAdjustment(batchID: expired.id, delta: -1)])
    }

    @Test func countedZeroEmptiesEverything() {
        let a = batch(nil), b = batch(CalendarDay(year: 2027, month: 1, day: 1))
        let sum = plan(0, [(a, 2), (b, 3)]).reduce(0) { $0 + $1.delta }
        #expect(sum == -5)
    }

    @Test func archivedBatchesAreIgnoredOnBothSides() {
        let archived = batch(nil, archived: true)
        let live = batch(nil)
        #expect(plan(2, [(archived, 7), (live, 2)]).isEmpty)
    }

    @Test func negativeBatchCountsInTheSumButIsNeverReducedFurther() {
        let conflict = batch(nil, bought: 1)
        let ok = batch(CalendarDay(year: 2027, month: 1, day: 1), bought: 2)
        // Soll = 5 + (−2) = 3; gezählt 0 → 3 abziehen, nur von der Charge mit Bestand
        #expect(plan(0, [(ok, 5), (conflict, -2)]) == [CountAdjustment(batchID: ok.id, delta: -3)])
    }

    @Test func noBatchMeansNothingToBook() {
        #expect(plan(4, []).isEmpty)
    }

    @Test func negativeCountIsRejected() {
        let a = batch(nil)
        #expect(plan(-1, [(a, 3)]).isEmpty)
    }
}
