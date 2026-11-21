import Foundation
import Testing
@testable import CarbStockCore

@Suite struct ForecastTests {
    // 2026-11-23 is a Monday.
    let monday = CalendarDay(year: 2026, month: 11, day: 23)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func uniform(_ perWeek: Double, days: Int) -> DemandSeries {
        DemandSeries(start: monday, dailyG: Array(repeating: perWeek / 7, count: days))
    }
    func lot(_ g: Double, expiry: CalendarDay? = nil, unit: Double = 25, despite: Bool = false) -> StockLot {
        StockLot(batchID: UUID(), productID: UUID(), expiry: expiry, carbsG: g, unitCarbsG: unit, useDespiteExpiry: despite)
    }

    /// TV-1 + Priorität Override > Nutzer > eingebaut
    @Test func sessionDemand() {
        #expect(DemandCalculator.sessionDemandG(durationMinutes: 240, carbsPerHour: 80) == 320)
        let s = PlannedSession(day: monday, type: .long, durationMinutes: 240)
        #expect(DemandCalculator.sessionDemandG(s) == 320)
        #expect(DemandCalculator.sessionDemandG(s, userRates: [.long: 90]) == 360)
        var o = s; o.carbsPerHourOverride = 50
        #expect(DemandCalculator.sessionDemandG(o, userRates: [.long: 90]) == 200)
        #expect(DemandCalculator.carbsPerHour(type: .z2) == 60)
    }

    @Test func seriesExplicitBeatsTemplateAndSkippedCountsZero() {
        let tpl = [WeeklyTemplateEntry(weekdayIndex: 0, type: .long, durationMinutes: 240, validFrom: monday)]
        let explicit = PlannedSession(day: monday, type: .vo2, durationMinutes: 60) // 70 g statt Vorlage 320 g
        let s1 = DemandSeries.build(from: monday, maxDays: 8, sessions: [explicit], template: tpl)
        #expect(s1.dailyG[0] == 70 && s1.dailyG[7] == 320 && s1.dailyG[1] == 0)
        let skipped = PlannedSession(day: monday, type: .vo2, durationMinutes: 60, status: .skipped)
        let s2 = DemandSeries.build(from: monday, maxDays: 8, sessions: [skipped], template: tpl)
        #expect(s2.dailyG[0] == 0 && s2.dailyG[7] == 320) // skipped zählt nicht, Vorlage greift an dem Tag nicht
        #expect(s2.reachedCap)
    }

    /// AC-P4
    @Test func noSessionsNoTemplateMeansUnknown() {
        let s = DemandSeries.build(from: monday, maxDays: 90, sessions: [], template: [])
        #expect(s.knownDays == 0 && s.knownThrough == nil && !s.isKnown(forDays: 7))
        let r = Forecast.simulate(lots: [lot(1000)], series: s, today: monday)
        #expect(r.end == .noDemandData && r.weeks == nil && r.reachDate == nil)
    }

    /// AC-P5: nur Sessions bis Tag 9 bekannt
    @Test func explicitSessionsOnlyGiveKnownUntilLastSession() {
        let ss = [PlannedSession(day: monday, type: .long, durationMinutes: 60),
                  PlannedSession(day: monday.adding(days: 9), type: .long, durationMinutes: 60)]
        let s = DemandSeries.build(from: monday, maxDays: 90, sessions: ss)
        #expect(s.knownDays == 10 && s.knownThrough == monday.adding(days: 9))
        let r = Forecast.simulate(lots: [lot(100_000)], series: s, today: monday)
        #expect(r.end == .demandEnded && r.coveredDays == 10)
        #expect(r.reachDate == monday.adding(days: 10) && r.lastFullyCoveredDay == monday.adding(days: 9))
        // Sessions in der Vergangenheit: nichts bekannt
        let past = DemandSeries.build(from: monday, maxDays: 30, sessions: [PlannedSession(day: monday.adding(days: -3), type: .z2, durationMinutes: 60)])
        #expect(past.knownDays == 0)
    }

    @Test func templateValidityEnds() {
        let tpl = [WeeklyTemplateEntry(weekdayIndex: 2, type: .z2, durationMinutes: 60, validFrom: monday, validUntil: monday.adding(days: 13))]
        let s = DemandSeries.build(from: monday, maxDays: 100, sessions: [], template: tpl)
        #expect(s.knownDays == 14 && !s.reachedCap)
        #expect(s.dailyG[2] == 60 && s.dailyG[9] == 60 && s.totalG == 120)
    }

    /// TV-2 mit gleichmäßigem Tagesbedarf 900/7
    @Test func tv2UniformDemand() {
        let r = Forecast.simulate(lots: [lot(14_000)], series: uniform(900, days: 300), today: monday)
        #expect(r.end == .stockExhausted)
        #expect(r.coveredDays == 108)
        #expect(r.weeks == 15.5)
        #expect(r.reachDate == monday.adding(days: 108)) // AC-P3
    }

    /// 900 g/Woche als Wochenvorlage (Mo/Mi/Sa je 300 g): der Teiltag zählt anteilig.
    @Test func tv2WeeklyTemplateLumpyDemand() {
        let tpl = [0, 2, 5].map { WeeklyTemplateEntry(weekdayIndex: $0, type: .z2, durationMinutes: 300, carbsPerHourOverride: 60, validFrom: monday) }
        #expect(DemandCalculator.sessionDemandG(durationMinutes: 300, carbsPerHour: 60) == 300)
        let s = DemandSeries.build(from: monday, maxDays: 300, sessions: [], template: tpl)
        let r = Forecast.simulate(lots: [lot(14_000)], series: s, today: monday)
        // 15 Wochen = 13 500 g, danach Mo 300, Di 0, Mi 200/300 -> 107,67 Tage
        #expect(r.coveredDays == 107)
        #expect(abs(r.coveredDaysExact - 107.6667) < 0.001)
        #expect(r.weeks == 15.3)
    }

    @Test func horizonReachedWhenStockOutlastsSeries() {
        let r = Forecast.simulate(lots: [lot(1_000_000)], series: DemandSeries(start: monday, dailyG: Array(repeating: 100, count: 30), reachedCap: true), today: monday)
        #expect(r.end == .horizonReached && r.coveredDays == 30)
    }

    @Test func zeroDemandAndZeroStock() {
        #expect(Forecast.simulate(lots: [lot(500)], series: DemandSeries(start: monday, dailyG: [0, 0, 0]), today: monday).end == .noDemandData)
        let none = Forecast.simulate(lots: [], series: uniform(700, days: 10), today: monday)
        #expect(none.end == .stockExhausted && none.coveredDays == 0 && none.weeks == 0 && none.lastFullyCoveredDay == nil)
    }

    /// TV-6: 500 g, "MHD in 14 Tagen" = 14 Verbrauchstage (letzter nutzbarer Tag = heute+13), 100 g/Woche.
    @Test func tv6ExpiryLoss() {
        let l = lot(500, expiry: monday.adding(days: 13))
        let r = Forecast.simulate(lots: [l], series: uniform(100, days: 28), today: monday)
        #expect(abs(r.consumedG - 200) < 1e-6)
        #expect(r.losses.count == 1)
        #expect(abs(r.losses[0].lostCarbsG - 300) < 1e-6)
        #expect(r.losses[0].lostQuantity == 12)
        #expect(r.losses[0].batchID == l.batchID)
        // AC-P7: ab dem Tag nach dem MHD fehlt der Nachschub, obwohl Ware ablief
        #expect(r.supplyGap?.day == monday.adding(days: 14))
        #expect(r.end == .stockExhausted && r.coveredDays == 14) // Bestand endet wegen Verfall
    }

    /// MHD-Tag selbst ist noch nutzbar: bei MHD heute+14 sind es 15 Verbrauchstage.
    @Test func lastDayStillConsumable() {
        let r = Forecast.simulate(lots: [lot(500, expiry: monday.adding(days: 14))], series: uniform(100, days: 28), today: monday)
        #expect(abs(r.consumedG - 15 * 100.0 / 7) < 1e-6)
    }

    @Test func fefoConsumesEarliestFirstAndExpiredNotUsable() {
        let early = lot(100, expiry: monday.adding(days: 3))
        let late = lot(1000, expiry: monday.adding(days: 100))
        let r = Forecast.simulate(lots: [late, early], series: DemandSeries(start: monday, dailyG: Array(repeating: 50, count: 10)), today: monday)
        #expect(r.losses.isEmpty && r.consumedG == 500)
        // bereits abgelaufen (gestern): kein nutzbarer Bestand, kein "Verfall" in der Zukunft
        let old = lot(500, expiry: monday.adding(days: -1))
        let r2 = Forecast.simulate(lots: [old], series: DemandSeries(start: monday, dailyG: [100, 100]), today: monday)
        #expect(r2.coveredDays == 0 && r2.losses.isEmpty)
        #expect(r2.supplyGap?.day == monday)
        // trotzdem nutzen: zählt wieder
        let used = lot(500, expiry: monday.adding(days: -1), despite: true)
        #expect(Forecast.simulate(lots: [used], series: DemandSeries(start: monday, dailyG: [100, 100]), today: monday).consumedG == 200)
    }

    @Test func windowsAndAmpel() {
        let lots = [lot(14_000)]
        let s = uniform(900, days: 300)
        let w7 = Forecast.window(days: 7, lots: lots, series: s, today: monday)
        #expect(abs(w7.demandG - 900) < 1e-6 && w7.ampel == .enough && w7.isDemandComplete)
        let w84 = Forecast.window(days: 84, lots: lots, series: s, today: monday)
        #expect(abs(w84.demandG - 10_800) < 1e-6 && abs(w84.differenceG - 3200) < 1e-6 && w84.ampel == .enough)
        #expect(Forecast.window(days: 84, lots: [lot(11_000)], series: s, today: monday).ampel == .tight)  // 101,9 %
        #expect(Forecast.window(days: 84, lots: [lot(10_000)], series: s, today: monday).ampel == .shortage)
        #expect(Forecast.window(days: 84, lots: [lot(10_000)], series: s, today: monday).shortfallG > 799)
        // unvollständiger Bedarf: keine Ampel
        let short = Forecast.window(days: 28, lots: lots, series: uniform(900, days: 10), today: monday)
        #expect(!short.isDemandComplete && short.ampel == nil)
        // Bedarf 0
        let zero = Forecast.window(days: 7, lots: lots, series: DemandSeries(start: monday, dailyG: Array(repeating: 0, count: 7)), today: monday)
        #expect(zero.ampel == .enough && zero.coverage == nil)
    }

    @Test func windowSubtractsExpiringStock() {
        let w = Forecast.window(days: 28, lots: [lot(500, expiry: monday.adding(days: 13))], series: uniform(100, days: 28), today: monday)
        #expect(abs(w.usableStockG - 200) < 1e-6)
    }

    @Test func runUsesLedgerAndNegativeStockIsNotUsable() {
        let p = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        let a = BatchInfo(productID: p.id, purchaseDate: monday, quantityPurchased: 20)
        let b = BatchInfo(productID: p.id, purchaseDate: monday, quantityPurchased: 1)
        let ledger = Ledger([Movement(batchID: a.id, type: .purchase, delta: 20, occurredAt: t0),
                             Movement(batchID: b.id, type: .consume, delta: -1, occurredAt: t0)])
        let sessions = (0..<14).map { PlannedSession(day: monday.adding(days: $0), type: .long, durationMinutes: 15) } // 20 g/Tag
        let rep = Forecast.run(today: monday, products: [p], batches: [a, b], ledger: ledger, sessions: sessions)
        #expect(rep.windows.map(\.days) == [7, 28, 84])
        #expect(rep.windows[0].usableStockG == 500)
        #expect(rep.simulation.end == .demandEnded)
    }

    @Test func weeksAreFlooredNotRounded() {
        #expect(Forecast.floorToTenth(15.5555) == 15.5)
        #expect(Forecast.floorToTenth(2.0) == 2.0)
        #expect(Forecast.floorToTenth(0.99) == 0.9)
    }
}
