import Foundation
import Testing
@testable import CarbStockCore

@Suite struct ReminderPlannerTests {
    let today = CalendarDay(year: 2026, month: 11, day: 21)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func product(_ name: String) -> ProductInfo {
        ProductInfo(name: name, category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
    }

    /// A batch with `qty` in stock expiring `days` from today.
    func batch(_ p: ProductInfo, days: Int?, qty: Int = 5, archived: Bool = false) -> (BatchInfo, Movement) {
        let b = BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: qty,
                          expiryDate: days.map { today.adding(days: $0) }, isArchived: archived)
        return (b, Movement(batchID: b.id, type: .purchase, delta: qty, occurredAt: t0))
    }

    func plan(_ ps: [ProductInfo], _ bs: [(BatchInfo, Movement)], extra: [Movement] = [],
              minuteOfDay: Int = 8 * 60, hour: Int = 9, minute: Int = 0, limit: Int = 50) -> [ReminderPlan] {
        ReminderPlanner.plan(products: ps, batches: bs.map(\.0), ledger: Ledger(bs.map(\.1) + extra), today: today,
                             minuteOfDay: minuteOfDay, hour: hour, minute: minute, limit: limit)
    }

    /// AC-N3
    @Test func schedulesSixtyAndThirtyDaysBeforeAtTheSetTime() {
        let p = product("Gel X")
        let r = plan([p], [batch(p, days: 100)], hour: 7, minute: 30)
        #expect(r.map(\.fireDay) == [today.adding(days: 40), today.adding(days: 70)])
        #expect(r.allSatisfy { $0.hour == 7 && $0.minute == 30 })
        #expect(r[0].id != r[1].id)
    }

    /// AC-N3: several batches on the same day yield one collective notification, max. three names.
    @Test func oneCollectiveNotificationPerDay() {
        let ps = ["A", "B", "C", "D"].map(product)
        let r = plan(ps, ps.map { batch($0, days: 100) })
        #expect(r.count == 2)
        #expect(r[0].batchCount == 4)
        #expect(r[0].body == "4 Chargen laufen bald ab: A, B, C … Chargen prüfen.")
        let single = plan([ps[0]], [batch(ps[0], days: 100)])
        #expect(single[0].body == "1 Charge läuft bald ab: A. Chargen prüfen.")
    }

    @Test func sameProductNamedOnce() {
        let p = product("Gel")
        let r = plan([p], [batch(p, days: 100), batch(p, days: 100)])
        #expect(r[0].batchCount == 2)
        #expect(r[0].body == "2 Chargen laufen bald ab: Gel. Chargen prüfen.")
    }

    /// AC-N4
    @Test func emptyArchivedExpiredAndUndatedBatchesGetNoReminder() {
        let p = product("P")
        let used = batch(p, days: 100)
        let consume = Movement(batchID: used.0.id, type: .consume, delta: -5, occurredAt: t0, createdAt: t0.addingTimeInterval(1))
        let archivedBatch = batch(p, days: 100, archived: true)
        let expired = batch(p, days: -1)
        let undated = batch(p, days: nil)
        let all = [used, archivedBatch, expired, undated]
        #expect(plan([p], all, extra: [consume]).isEmpty)
        var archivedProduct = p
        archivedProduct.isArchived = true
        #expect(plan([archivedProduct], [batch(archivedProduct, days: 100)]).isEmpty)
        // Without the consumption the first batch is planned again.
        #expect(plan([p], [used]).count == 2)
    }

    @Test func onlyFutureTimes() {
        let p = product("P")
        // Expires in 60 days: the 60-day reminder is today at 09:00.
        #expect(plan([p], [batch(p, days: 60)], minuteOfDay: 8 * 60).count == 2)
        #expect(plan([p], [batch(p, days: 60)], minuteOfDay: 9 * 60).count == 1) // 09:00 is no longer in the future
        #expect(plan([p], [batch(p, days: 59)]).count == 1)
        #expect(plan([p], [batch(p, days: 30)], minuteOfDay: 10 * 60).isEmpty)
    }

    /// AC-N6 / limit: at most 50, earliest first.
    @Test func limitsToFiftyEarliestFirst() {
        let p = product("P")
        let bs = (0..<30).map { batch(p, days: 70 + $0 * 61) } // 60 distinct fire days
        let r = plan([p], bs)
        #expect(r.count == 50)
        #expect(r.map(\.fireDay) == r.map(\.fireDay).sorted())
        #expect(r.first?.fireDay == today.adding(days: 10))
        #expect(plan([p], bs, limit: 3).count == 3)
        #expect(plan([p], bs, limit: 0).isEmpty)
        #expect(plan([p], Array(bs.prefix(25))).count == 50) // exactly at the limit
    }

    @Test func textHasNoNutritionAdvice() {
        let p = product("P")
        let r = plan([p], [batch(p, days: 100)])
        #expect(r[0].title == "Läuft bald ab")
        #expect(r[0].body.contains("Chargen prüfen"))
    }
}
