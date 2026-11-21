import Foundation
import Testing
@testable import CarbStockCore

/// Aussage der Reichweite (AC-P3, AC-P4, AC-P5) und Kategorie-Verteilung (4.3, nur Anzeige).
@Suite struct RunwayStatementTests {
    let monday = CalendarDay(year: 2026, month: 11, day: 23)

    func product(_ category: ProductCategory = .gel, carbs: Double = 25) -> ProductInfo {
        ProductInfo(name: "P", category: category, baseUnit: .piece, carbsPerPortionG: carbs)
    }
    func batch(_ p: ProductInfo, qty: Int, expiry: CalendarDay? = nil) -> BatchInfo {
        BatchInfo(productID: p.id, purchaseDate: monday, quantityPurchased: qty, expiryDate: expiry)
    }
    func ledger(_ b: BatchInfo) -> Ledger {
        Ledger([Movement(batchID: b.id, type: .purchase, delta: b.quantityPurchased, occurredAt: Date(timeIntervalSince1970: 0))])
    }

    /// AC-P3 / TV-2: 14 000 g bei 900 g pro Woche (gleichmäßig) = 15,5 Wochen, bis heute + 108 Tage.
    @Test func exhaustedStatesWeeksAndDate() {
        let p = product(carbs: 1)
        let b = batch(p, qty: 14_000)
        let series = DemandSeries(start: monday, dailyG: Array(repeating: 900.0 / 7, count: 730), reachedCap: true)
        let lots = StockLot.lots(products: [p], batches: [b], ledger: ledger(b))
        let sim = Forecast.simulate(lots: lots, series: series, today: monday)
        let statement = RunwayStatement(simulation: sim, series: series)
        #expect(statement == .reaches(weeks: 15.5, until: monday.adding(days: 108)))
    }

    /// AC-P4
    @Test func noDemandIsUnknown() {
        let series = DemandSeries.build(from: monday, maxDays: 90, sessions: [])
        let sim = Forecast.simulate(lots: [], series: series, today: monday)
        #expect(RunwayStatement(simulation: sim, series: series) == .unknown)
    }

    /// AC-P5: Bedarf endet vor dem Bestand → "mindestens bis" (letzter Tag mit bekanntem Bedarf).
    @Test func demandEndedMeansAtLeast() {
        let p = product(carbs: 10)
        let b = batch(p, qty: 1000)
        let sessions = [PlannedSession(day: monday.adding(days: 9), type: .long, durationMinutes: 60)]
        let series = DemandSeries.build(from: monday, maxDays: 90, sessions: sessions)
        let lots = StockLot.lots(products: [p], batches: [b], ledger: ledger(b))
        let sim = Forecast.simulate(lots: lots, series: series, today: monday)
        #expect(RunwayStatement(simulation: sim, series: series) == .atLeast(until: monday.adding(days: 9)))
    }

    /// Bestand reicht nur bis in den Tag hinein: 0 volle Tage, aber eine Aussage.
    @Test func emptyStockStatesZeroWeeks() {
        let sessions = [PlannedSession(day: monday, type: .long, durationMinutes: 60)]
        let series = DemandSeries.build(from: monday, maxDays: 90, sessions: sessions)
        let sim = Forecast.simulate(lots: [], series: series, today: monday)
        #expect(RunwayStatement(simulation: sim, series: series) == .reaches(weeks: 0, until: monday))
    }

    @Test func categoryBreakdownSumsUsableStockOnly() {
        let gel = product(.gel, carbs: 25), drink = product(.drink, carbs: 1)
        let gelBatch = batch(gel, qty: 4), drinkBatch = batch(drink, qty: 500)
        let archived = BatchInfo(productID: gel.id, purchaseDate: monday, quantityPurchased: 10, isArchived: true)
        let l = Ledger(ledger(gelBatch).movements + ledger(drinkBatch).movements + ledger(archived).movements)
        let breakdown = StockBreakdown.carbsByCategory(products: [gel, drink], batches: [gelBatch, drinkBatch, archived], ledger: l)
        #expect(breakdown.count == 2)
        #expect(breakdown[0].category == .drink && breakdown[0].carbsG == 500) // absteigend nach Carbs
        #expect(breakdown[1].category == .gel && breakdown[1].carbsG == 100) // archivierte Charge zählt nicht
    }
}
