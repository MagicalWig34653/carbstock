import Foundation
import Testing
@testable import CarbStockCore

@Suite struct PurchaseAdvisorTests {
    let today = CalendarDay(year: 2026, month: 11, day: 23)
    let gel = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)

    func lot(_ g: Double, expiry: CalendarDay? = nil) -> StockLot {
        StockLot(batchID: UUID(), productID: UUID(), expiry: expiry, carbsG: g, unitCarbsG: 25)
    }
    func series(perDay: Double, days: Int = 300) -> DemandSeries {
        DemandSeries(start: today, dailyG: Array(repeating: perDay, count: days), reachedCap: true)
    }
    func ctx(stock: Double, perDay: Double, history: [PricedBatch] = []) -> PurchaseContext {
        PurchaseContext(today: today, lots: stock > 0 ? [lot(stock)] : [], series: series(perDay: perDay), history: history)
    }

    /// TV-4 / AC-K1 (+ Preis TV-3)
    @Test func tv4DontBuyWhenCovered() {
        let offer = PurchaseOffer(product: gel, quantity: 60, totalPriceCents: 3000, expiryDate: today.adding(months: 24))
        let a = PurchaseAdvisor.assess(offer: offer, context: ctx(stock: 14_000, perDay: 900.0 / 7))
        #expect(a.verdict == .dontBuy)
        #expect(a.shortfallG == 0)
        let r3 = a.reasons.first { $0.rule == .r3 }
        #expect(r3 != nil && r3!.text.contains("15,5 Wochen") && r3!.text.contains("12,0 Wochen"))
        #expect(abs(a.offerPricePer100gCarbs! - 2.0) < 1e-9)
        #expect(a.reasons.contains { $0.rule == .r6 && $0.text.contains("2,00 €") })
        #expect(a.reasons.allSatisfy { !$0.values.isEmpty })
    }

    /// AC-K2: Fehlbedarf 1000 g, Angebot 3000 g
    @Test func partialPurchaseForShortfall() {
        let offer = PurchaseOffer(product: gel, quantity: 120, totalPriceCents: 6000)
        let a = PurchaseAdvisor.assess(offer: offer, context: ctx(stock: 7400, perDay: 100))
        #expect(a.shortfallG == 1000)
        #expect(a.verdict == .buyPartially(quantity: 40))
        #expect(a.reasons.map(\.rule).prefix(2) == [.r2, .r4])
    }

    @Test func buyWhenOfferWithinUsefulQuantity() {
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 30), context: ctx(stock: 7400, perDay: 100))
        #expect(a.verdict == .buy)
        #expect(a.offerPricePer100gCarbs == nil && !a.reasons.contains { $0.rule == .r6 }) // ohne Preis keine €-Kennzahl
        // Aufrunden: Fehlmenge 1010 g -> 41 Einheiten
        #expect(PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 120), context: ctx(stock: 7390, perDay: 100)).verdict == .buyPartially(quantity: 41))
    }

    /// AC-K3
    @Test func notAssessableWithoutDemandStillShowsPrice() {
        let offer = PurchaseOffer(product: gel, quantity: 60, totalPriceCents: 3000)
        let c = PurchaseContext(today: today, lots: [lot(1000)], series: DemandSeries(start: today, dailyG: []))
        let a = PurchaseAdvisor.assess(offer: offer, context: c)
        #expect(a.verdict == .notAssessable)
        #expect(a.reasons[0].rule == .r1)
        #expect(a.offerPricePer100gCarbs != nil && a.reasons.contains { $0.rule == .r6 })
        // Bedarf nur teilweise bekannt: Datum im Text
        let partial = PurchaseContext(today: today, lots: [], series: DemandSeries(start: today, dailyG: Array(repeating: 100, count: 30)))
        let b = PurchaseAdvisor.assess(offer: offer, context: partial)
        #expect(b.verdict == .notAssessable && b.reasons[0].text.contains(today.adding(days: 29).isoString))
    }

    func priced(_ product: ProductInfo, cents: Int, qty: Int = 100) -> PricedBatch {
        PricedBatch(product: product, batch: BatchInfo(productID: product.id, purchaseDate: today, quantityPurchased: qty, totalPriceCents: cents))
    }

    /// AC-K4
    @Test func referencePriceMedianOwnThenCategory() {
        // eigene Käufe: 2,00 und 3,00 €/100 g -> Median 2,50
        let own = [priced(gel, cents: 5000), priced(gel, cents: 7500)]
        #expect(abs(PurchaseAdvisor.referencePricePerGram(for: gel, history: own)! * 100 - 2.5) < 1e-9)
        let offer = PurchaseOffer(product: gel, quantity: 100, totalPriceCents: 5000) // 2,00 €/100 g
        let a = PurchaseAdvisor.assess(offer: offer, context: ctx(stock: 0, perDay: 100, history: own))
        #expect(abs(a.percentVersusReference! - (-20)) < 1e-9)
        #expect(a.reasons.contains { $0.rule == .r6 && $0.text.contains("20,0 % günstiger") })
        // nur ein eigener Kauf: keine Referenz, kein Prozent
        let one = PurchaseAdvisor.assess(offer: offer, context: ctx(stock: 0, perDay: 100, history: [priced(gel, cents: 5000)]))
        #expect(one.percentVersusReference == nil && !one.reasons.contains { $0.text.contains("%") && $0.rule == .r6 })
        // Kategorie mit 3 Käufen anderer Gele
        let other = ProductInfo(name: "Anderes Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 40)
        let cat = [priced(other, cents: 4000), priced(other, cents: 8000), priced(other, cents: 6000)]
        #expect(PurchaseAdvisor.referencePricePerGram(for: gel, history: cat) != nil)
        #expect(PurchaseAdvisor.referencePricePerGram(for: gel, history: Array(cat.prefix(2))) == nil)
        #expect(PurchaseAdvisor.median([1, 2, 3, 4]) == 2.5 && PurchaseAdvisor.median([]) == nil)
    }

    @Test func expensivePriceAddsHint() {
        let own = [priced(gel, cents: 5000), priced(gel, cents: 5000)] // 2,00
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 100, totalPriceCents: 6000),
                                       context: ctx(stock: 0, perDay: 100, history: own))
        #expect(a.reasons.contains { $0.text.contains("nur bei akutem Bedarf") })
        #expect(a.verdict == .buy) // R6 ändert nie das Bedarfsurteil
    }

    /// AC-K6: R5 mit Simulation
    @Test func shortLivedOfferReducesQuantity() {
        let offer = PurchaseOffer(product: gel, quantity: 120, expiryDate: today.adding(days: 20))
        let a = PurchaseAdvisor.assess(offer: offer, context: ctx(stock: 0, perDay: 100))
        // 21 Verbrauchstage = 2100 g; Verfall <= 10 % -> 93 Einheiten
        #expect(a.verdict == .buyPartially(quantity: 93))
        let r5 = a.reasons.first { $0.rule == .r5 }
        #expect(r5 != nil && r5!.text.contains("900") && r5!.text.contains("93"))
    }

    @Test func offerThatWouldRotCompletelyIsRejected() {
        // die ersten 30 Tage kein Bedarf, Angebot verfällt nach 20 Tagen
        let s = DemandSeries(start: today, dailyG: Array(repeating: 0, count: 30) + Array(repeating: 100, count: 270), reachedCap: true)
        let c = PurchaseContext(today: today, lots: [], series: s)
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 40, expiryDate: today.adding(days: 20)), context: c)
        #expect(a.verdict == .dontBuy)
        #expect(a.reasons.contains { $0.rule == .r5 })
    }

    @Test func longLivedOfferKeepsVerdict() {
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 40, expiryDate: today.adding(months: 24)),
                                       context: ctx(stock: 0, perDay: 100))
        #expect(a.verdict == .buy)
        #expect(a.reasons.contains { $0.rule == .r5 })
    }

    @Test func bargainRuleOptIn() {
        let own = [priced(gel, cents: 5000), priced(gel, cents: 5000)] // 2,00 €/100 g
        let offer = PurchaseOffer(product: gel, quantity: 40, totalPriceCents: 1500) // 1,50 = -25 %
        let covered = ctx(stock: 14_000, perDay: 900.0 / 7, history: own)
        #expect(PurchaseAdvisor.assess(offer: offer, context: covered).verdict == .dontBuy)
        var p = PurchaseParameters(); p.bargainRule = true
        #expect(PurchaseAdvisor.assess(offer: offer, context: covered, parameters: p).verdict == .buy)
        let normal = PurchaseOffer(product: gel, quantity: 40, totalPriceCents: 1900)
        #expect(PurchaseAdvisor.assess(offer: normal, context: covered, parameters: p).verdict == .dontBuy)
    }

    @Test func ratioLine() {
        var g = gel; g.glucoseFructoseRatio = 0.8
        var l = lot(1000); l.glucoseFructoseRatio = 1.0
        let c = PurchaseContext(today: today, lots: [l], series: series(perDay: 10))
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: g, quantity: 10), context: c)
        #expect(a.reasons.contains { $0.rule == .ratio && $0.text.contains("anderes Verhältnis") })
        // unbekannt: keine Zeile
        #expect(!PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 10), context: c).reasons.contains { $0.rule == .ratio })
    }

    /// AC-K7
    @Test func deterministic() {
        let offer = PurchaseOffer(product: gel, quantity: 120, totalPriceCents: 6000, expiryDate: today.adding(days: 50))
        let c = ctx(stock: 3000, perDay: 100, history: [priced(gel, cents: 5000), priced(gel, cents: 7000)])
        let first = PurchaseAdvisor.assess(offer: offer, context: c)
        for _ in 0..<5 { #expect(PurchaseAdvisor.assess(offer: offer, context: c) == first) }
        #expect(first.reasons.allSatisfy { !$0.text.isEmpty && !$0.values.isEmpty })
    }

    @Test func numberText() {
        #expect(NumberText.de(15.55, 1) == "15,6" || NumberText.de(15.55, 1) == "15,5")
        #expect(NumberText.de(2.0, 2) == "2,00")
        #expect(NumberText.de(1000) == "1000")
        #expect(NumberText.de(-0.001, 1) == "0,0")
        #expect(NumberText.de(-3.456, 1) == "-3,5")
    }
}
