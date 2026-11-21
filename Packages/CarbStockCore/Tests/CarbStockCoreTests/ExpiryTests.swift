import Foundation
import Testing
@testable import CarbStockCore

@Suite struct ExpiryTests {
    let today = CalendarDay(year: 2026, month: 11, day: 21)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// AC-H1
    @Test func statusByMonths() {
        #expect(Expiry.status(expiry: today.adding(months: 7), today: today) == .green)
        #expect(Expiry.status(expiry: today.adding(months: 5), today: today) == .yellow)
        #expect(Expiry.status(expiry: today.adding(months: 2), today: today) == .red)
        #expect(Expiry.status(expiry: today.adding(days: -1), today: today) == .expired)
        #expect(Expiry.status(expiry: nil, today: today) == .noExpiry)
    }

    @Test func boundaries() {
        #expect(Expiry.status(expiry: today.adding(months: 6), today: today) == .green)
        #expect(Expiry.status(expiry: today.adding(months: 6).adding(days: -1), today: today) == .yellow)
        #expect(Expiry.status(expiry: today.adding(months: 3), today: today) == .yellow)
        #expect(Expiry.status(expiry: today.adding(months: 3).adding(days: -1), today: today) == .red)
    }

    /// AC-H2
    @Test func lastDayIsNotExpired() {
        #expect(Expiry.status(expiry: today, today: today) == .red)
        #expect(Expiry.remainingDays(expiry: today, today: today) == 0)
        #expect(Expiry.remainingDays(expiry: today.adding(days: 74), today: today) == 74)
        #expect(Expiry.remainingDays(expiry: today.adding(days: -1), today: today) == -1)
        #expect(Expiry.remainingDays(expiry: nil, today: today) == nil)
    }

    @Test func configurableThresholds() {
        let t = ExpiryThresholds(greenMonths: 12, redMonths: 6)
        #expect(Expiry.status(expiry: today.adding(months: 7), today: today, thresholds: t) == .yellow)
        #expect(Expiry.status(expiry: today.adding(months: 5), today: today, thresholds: t) == .red)
    }

    /// AC-H5: status depends only on calendar days, never on a time of day.
    @Test func statusIsPureCalendarDays() {
        let berlin = CalendarDay(Date(timeIntervalSince1970: 1_795_300_000), in: TimeZone(identifier: "Europe/Berlin")!)
        #expect(Expiry.remainingDays(expiry: berlin.adding(days: 10), today: berlin) == 10)
    }

    @Test func recommendedRate() {
        // 14 units, 13 days left -> 14 days available -> 7/week
        #expect(Expiry.recommendedRatePerWeek(remainingQuantity: 14, expiry: today.adding(days: 13), today: today) == 7)
        #expect(Expiry.recommendedRatePerWeek(remainingQuantity: 14, expiry: today.adding(days: -1), today: today) == nil)
        #expect(Expiry.recommendedRatePerWeek(remainingQuantity: 14, expiry: nil, today: today) == nil)
        #expect(Expiry.recommendedRatePerWeek(remainingQuantity: 0, expiry: today, today: today) == nil)
        #expect(Expiry.recommendedRatePerWeek(remainingQuantity: 3, expiry: today, today: today) == 21) // last day
    }

    /// AC-H3
    @Test func useFirstOrderAndFiltering() {
        let p = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        func batch(_ expiry: CalendarDay?, archived: Bool = false) -> BatchInfo {
            BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 4, expiryDate: expiry, isArchived: archived)
        }
        let none = batch(nil), later = batch(today.adding(months: 8)), soon = batch(today.adding(days: 20))
        let expired = batch(today.adding(days: -3)), empty = batch(today.adding(days: 5)), arch = batch(today.adding(days: 6), archived: true)
        let all = [none, later, soon, expired, empty, arch]
        let ledger = Ledger(all.map { Movement(batchID: $0.id, type: .purchase, delta: $0 .id == empty.id ? 0 : 4, occurredAt: t0) }
                            + [Movement(batchID: empty.id, type: .purchase, delta: 2, occurredAt: t0),
                               Movement(batchID: empty.id, type: .consume, delta: -2, occurredAt: t0)])
        let list = UseFirstList.build(products: [p], batches: all, ledger: ledger, today: today)
        #expect(list.map(\.batch.id) == [expired.id, soon.id, later.id, none.id])
        #expect(list.map(\.status) == [.expired, .red, .green, .noExpiry])
        #expect(list[1].carbsG == 100 && list[1].remainingQuantity == 4 && list[1].remainingDays == 20)
        #expect(list[0].recommendedRatePerWeek == nil)
    }

    @Test func useFirstIgnoresNegativeStockAndEmptyList() {
        let p = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        let b = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: 1)
        let neg = Ledger([Movement(batchID: b.id, type: .consume, delta: -1, occurredAt: t0)])
        #expect(UseFirstList.build(products: [p], batches: [b], ledger: neg, today: today).isEmpty)
        #expect(UseFirstList.build(products: [], batches: [], ledger: Ledger([]), today: today).isEmpty)
    }
}
