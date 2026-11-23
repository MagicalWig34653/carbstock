import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

@MainActor
@Suite struct TrainingServiceTests {
    // 2026-11-23 is a Monday.
    let today = CalendarDay(year: 2026, month: 11, day: 23)
    let container: ModelContainer
    let context: ModelContext
    let training: TrainingService
    let inventory: InventoryService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        let day = CalendarDay(year: 2026, month: 11, day: 23)
        training = TrainingService(context: context, today: { day })
        inventory = InventoryService(context: context, today: { day })
    }

    func stock(carbs: Double, quantity: Int, expiry: CalendarDay? = nil, name: String = "Pulver") throws {
        var d = ProductDraft()
        d.name = name; d.category = .drink; d.baseUnit = .gram; d.portionAmount = 1; d.carbsPerPortionG = carbs
        d.quantity = quantity; d.expiry = expiry
        try inventory.createProduct(d)
    }

    // AC-P1: Überschreiben gilt nur für diese Session
    @Test func sessionOverrideAppliesOnlyToThatSession() throws {
        var a = SessionDraft(day: today); a.type = .long; a.durationMinutes = 240
        var b = a; b.carbsPerHourOverride = 50
        try training.addSession(a)
        try training.addSession(b)
        let infos = training.sessions().compactMap(\.info)
        #expect(infos.count == 2)
        let demands = infos.map { DemandCalculator.sessionDemandG($0, userRates: training.userRates()) }.sorted()
        #expect(demands == [200, 320]) // 240 min × 50 g/h und × 80 g/h (TV-1)
        #expect(a.demandG(userRates: [:]) == 320 && b.demandG(userRates: [:]) == 200)
    }

    @Test func draftValidation() throws {
        var d = SessionDraft(day: today)
        d.durationMinutes = 0
        d.carbsPerHourOverride = 500
        #expect(d.problems == [.durationOutOfRange, .rateOutOfRange])
        #expect(throws: TrainingService.Failure.invalidSession([.durationOutOfRange, .rateOutOfRange])) { try training.addSession(d) }
        #expect(training.sessions().isEmpty)
        var t = TemplateDraft(weekdayIndex: 2, validFrom: today)
        t.validUntil = today.adding(days: -1)
        #expect(t.problems == [.endBeforeStart])
        #expect(throws: TrainingService.Failure.invalidTemplate([.endBeforeStart])) { try training.addTemplateEntry(t) }
    }

    @Test func editStatusAndDeleteSession() throws {
        var d = SessionDraft(day: today); d.title = "  So-Langfahrt "
        let s = try training.addSession(d)
        #expect(s.title == "So-Langfahrt" && s.statusRaw == SessionStatus.planned.rawValue)
        d.durationMinutes = 90; d.title = ""
        try training.update(s, with: d)
        #expect(s.durationMinutes == 90 && s.title == nil)
        try training.setStatus(.skipped, on: s)
        #expect(training.sessions().first?.info?.status == .skipped)
        try training.delete(s)
        #expect(training.sessions().isEmpty)
    }

    @Test func rateOverridesStoreOnlyDeviations() throws {
        #expect(training.userRates().isEmpty)
        try training.setRate(90, for: .long)
        #expect(training.userRates() == [.long: 90])
        try training.setRate(95, for: .long) // ersetzt, kein zweiter Datensatz
        #expect(try context.fetch(FetchDescriptor<CarbRateOverride>()).count == 1)
        try training.setRate(80, for: .long) // = eingebauter Wert → keine Abweichung
        #expect(training.userRates().isEmpty)
        try training.setRate(95, for: .long)
        try training.setRate(nil, for: .long) // zurücksetzen
        #expect(try context.fetch(FetchDescriptor<CarbRateOverride>()).isEmpty)
        #expect(throws: TrainingService.Failure.rateOutOfRange) { try training.setRate(0, for: .z2) }
    }

    @Test func userRateChangesSessionDemand() throws {
        var d = SessionDraft(day: today); d.type = .long; d.durationMinutes = 240
        try training.addSession(d)
        try stock(carbs: 1, quantity: 100_000)
        #expect(training.report().series.dailyG.first == 320)
        try training.setRate(90, for: .long)
        #expect(training.report().series.dailyG.first == 360)
    }

    // AC-P4
    @Test func withoutSessionsAndTemplateRunwayIsUnknown() throws {
        try stock(carbs: 1, quantity: 14_000)
        let r = training.report()
        #expect(RunwayStatement(simulation: r.simulation, series: r.series) == .unknown)
        #expect(r.windows.allSatisfy { !$0.isDemandComplete && $0.ampel == nil })
    }

    // AC-P2/P3: Wochenvorlage 900 g (Montag, 15 h × 60 g/h) gegen 14 000 g Bestand
    @Test func templateDrivesWindowsAndRunway() throws {
        try stock(carbs: 1, quantity: 14_000)
        var t = TemplateDraft(weekdayIndex: 0, validFrom: today)
        t.type = .z2; t.durationMinutes = 900
        try training.addTemplateEntry(t)
        let r = training.report()
        #expect(r.windows.map(\.days) == [7, 28, 84])
        #expect(r.windows.map(\.demandG) == [900, 3600, 10_800]) // 1, 4 und 12 Montage
        #expect(r.windows.allSatisfy { $0.isDemandComplete })
        #expect(r.windows.map(\.ampel) == [.enough, .enough, .enough])
        // 15 volle Montage (13 500 g), am 16. fehlen 400 g: 105 volle Tage, 15,0 Wochen
        #expect(RunwayStatement(simulation: r.simulation, series: r.series) == .reaches(weeks: 15.0, until: today.adding(days: 105)))
    }

    // AC-P5: nur Sessions → "mindestens bis"
    @Test func explicitSessionsGiveAtLeast() throws {
        try stock(carbs: 1, quantity: 14_000)
        var d = SessionDraft(day: today.adding(days: 9)); d.durationMinutes = 60
        try training.addSession(d)
        let r = training.report()
        #expect(RunwayStatement(simulation: r.simulation, series: r.series) == .atLeast(until: today.adding(days: 9)))
    }

    @Test func skippedSessionDoesNotCount() throws {
        try stock(carbs: 1, quantity: 14_000)
        var d = SessionDraft(day: today); d.durationMinutes = 120
        let s = try training.addSession(d)
        #expect(training.report().series.dailyG == [120])
        try training.setStatus(.skipped, on: s)
        #expect(training.report().series.dailyG == [0])
    }

    // AC-P6/P7 über die App-Daten: Gel läuft vor dem Verbrauch ab → Verfallsrisiko
    @Test func expiryRiskShowsUpInReport() throws {
        var g = ProductDraft()
        g.name = "Gel"; g.category = .gel; g.carbsPerPortionG = 25; g.quantity = 20; g.expiry = today.adding(days: 13)
        try inventory.createProduct(g) // 500 g
        var t = TemplateDraft(weekdayIndex: 0, validFrom: today)
        t.durationMinutes = 100 // 100 g pro Woche
        try training.addTemplateEntry(t)
        let r = training.report()
        #expect(r.simulation.losses.count == 1)
        #expect(abs(r.simulation.totalLossG - 300) < 1e-6)
        #expect(r.simulation.losses.first?.lostQuantity == 12)
    }

    @Test func stockBreakdownByCategory() throws {
        try stock(carbs: 1, quantity: 500)
        var g = ProductDraft(); g.name = "Gel"; g.category = .gel; g.carbsPerPortionG = 25; g.quantity = 4
        try inventory.createProduct(g)
        let shares = training.stockBreakdown()
        #expect(shares.map(\.category) == [.drink, .gel] && shares.map(\.carbsG) == [500, 100])
    }
}

@Suite struct TrainingLogicTests {
    let today = CalendarDay(year: 2026, month: 11, day: 23)

    @Test func sessionSectionsSplitByDay() {
        func s(_ offset: Int) -> PlannedSession { PlannedSession(day: today.adding(days: offset), type: .z2, durationMinutes: 60) }
        let sections = SessionSections([s(5), s(0), s(-1), s(-28), s(-29), s(-100)], today: today)
        #expect(sections.upcoming.map(\.day) == [today, today.adding(days: 5)])
        #expect(sections.recent.map(\.day) == [today.adding(days: -1), today.adding(days: -28)])
        #expect(sections.older.map(\.day) == [today.adding(days: -29), today.adding(days: -100)])
    }

    @Test func runwayTexts() {
        let until = today.adding(days: 108)
        let reaches = RunwayStatement.reaches(weeks: 15.5, until: until)
        #expect(RunwayText.headline(reaches).contains("≈ 15,5 Wochen") || RunwayText.headline(reaches).contains("≈ 15.5 Wochen"))
        #expect(RunwayText.detail(reaches, today: today).contains("heute + 108 Tage"))
        #expect(RunwayText.headline(.atLeast(until: until)).hasPrefix("Reicht mindestens bis"))
        #expect(RunwayText.headline(.unknown) == "Bedarf unbekannt")
    }

    @Test func labelsAndDurations() {
        #expect(Fmt.duration(minutes: 240) == "4 h" && Fmt.duration(minutes: 90) == "1 h 30 min" && Fmt.duration(minutes: 45) == "45 min")
        #expect(Weekday.name(0) == "Montag" && Weekday.short(6) == "So" && today.isoWeekdayIndex == 0)
        #expect(SessionType.allCases.allSatisfy { !$0.title.isEmpty })
    }
}

@MainActor
@Suite struct RateSetupTests {
    let container: ModelContainer
    let context: ModelContext
    let service: TrainingService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        service = TrainingService(context: context)
    }

    @Test func startValuesAreTheSuggestionsThenUserValues() {
        let start = RateSetup.initialValues(userRates: [:])
        for t in SessionType.allCases { #expect(start[t] == CarbRate.builtIn(t).defaultPerHour) }
        #expect(RateSetup.initialValues(userRates: [.z2: 45])[.z2] == 45)
    }

    @Test func acceptingTheSuggestionsStoresNothing() throws {
        try RateSetup.apply(RateSetup.initialValues(userRates: [:]), using: service)
        #expect(service.userRates().isEmpty)
        #expect(try context.fetch(FetchDescriptor<CarbRateOverride>()).isEmpty)
    }

    @Test func onlyDeviationsAreStored() throws {
        var v = RateSetup.initialValues(userRates: [:])
        v[.z2] = CarbRate.builtIn(.z2).defaultPerHour + 10
        try RateSetup.apply(v, using: service)
        #expect(service.userRates() == [.z2: CarbRate.builtIn(.z2).defaultPerHour + 10])
        // zurück auf den Vorschlag entfernt den Eintrag wieder
        v[.z2] = CarbRate.builtIn(.z2).defaultPerHour
        try RateSetup.apply(v, using: service)
        #expect(service.userRates().isEmpty)
    }

    @Test func outOfRangeValueIsRejected() {
        #expect(throws: TrainingService.Failure.rateOutOfRange) { try RateSetup.apply([.z2: 9999], using: service) }
    }
}
