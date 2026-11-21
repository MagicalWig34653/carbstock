import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// Kauf-Entscheider, Einkaufsliste, Verlauf und „Gekauft“ (Spec 4.4, 5.7, 15.5 AC-K1…K7).
@MainActor
@Suite struct PurchaseServiceTests {
    // 2026-11-23 ist ein Montag.
    let today = CalendarDay(year: 2026, month: 11, day: 23)
    let container: ModelContainer // muss leben, solange der Kontext benutzt wird
    let context: ModelContext
    let service: PurchaseService
    let training: TrainingService
    let inventory: InventoryService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        let day = CalendarDay(year: 2026, month: 11, day: 23)
        service = PurchaseService(context: context, today: { day })
        training = TrainingService(context: context, today: { day })
        inventory = InventoryService(context: context, today: { day })
    }

    // MARK: Hilfen

    @discardableResult
    func powder(stock: Int) throws -> Product {
        var d = ProductDraft()
        d.name = "Pulver"; d.category = .drink; d.baseUnit = .gram; d.portionAmount = 1; d.carbsPerPortionG = 1
        d.quantity = stock
        return try inventory.createProduct(d)
    }

    /// 900 g pro Woche: Montag 900 min × 60 g/h.
    func weeklyDemand900() throws {
        var t = TemplateDraft(weekdayIndex: 0, validFrom: today)
        t.type = .z2; t.durationMinutes = 900
        try training.addTemplateEntry(t)
    }

    /// 100 g pro Tag: jeden Tag 100 min × 60 g/h.
    func dailyDemand100() throws {
        for weekday in 0..<7 {
            var t = TemplateDraft(weekdayIndex: weekday, validFrom: today)
            t.type = .z2; t.durationMinutes = 100
            try training.addTemplateEntry(t)
        }
    }

    func powderOffer(_ product: Product, quantity: Int, priceEuro: Double? = nil) -> OfferDraft {
        var d = OfferDraft()
        d.existingProductID = product.id; d.quantity = quantity; d.priceEuro = priceEuro
        return d
    }

    func gelOffer(quantity: Int = 60, priceEuro: Double? = 48, expiry: CalendarDay? = nil) -> OfferDraft {
        var d = OfferDraft()
        d.newProduct.name = "Gel"; d.newProduct.category = .gel; d.newProduct.carbsPerPortionG = 25
        d.quantity = quantity; d.priceEuro = priceEuro; d.expiry = expiry
        return d
    }

    func count<T: PersistentModel>(_ type: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? -1 }

    // MARK: AC-K1 … K4, K6, K7

    // AC-K1 (TV-4): 14 000 g Bestand, 900 g/Woche, 12 Wochen → nicht kaufen, Reichweite, R3
    @Test func k1CoveredStockMeansDontBuy() throws {
        let p = try powder(stock: 14_000)
        try weeklyDemand900()
        let r = try service.assess(powderOffer(p, quantity: 3000, priceEuro: 12))
        #expect(r.assessment.verdict == .dontBuy)
        #expect(r.outcome.tone == .dontBuy && r.outcome.title == "Nicht kaufen")
        let r3 = r.outcome.lines.first { $0.rule == "R3" }
        #expect(r3 != nil && r3!.text.contains("Wochen") && r3!.text.contains("12,0 Wochen"))
        #expect(r.recommendedQuantity == nil)
    }

    // AC-K2: Fehlbedarf 1000 g, Angebot 3000 g Carbs → teilweise kaufen für ≈ 1000 g
    @Test func k2PartialPurchaseForShortfall() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900() // 12 Wochen = 10 800 g
        let r = try service.assess(powderOffer(p, quantity: 3000))
        #expect(r.assessment.shortfallG == 1000)
        #expect(r.assessment.verdict == .buyPartially(quantity: 1000))
        #expect(r.outcome.title == "Teilweise kaufen: \(Fmt.quantity(1000, unit: .gram))")
        #expect(r.recommendedQuantity == 1000)
        #expect(r.outcome.lines.map(\.rule).prefix(2) == ["R2", "R4"])
    }

    // AC-K3: ohne Bedarf nicht beurteilbar, Preis je 100 g Carbs trotzdem
    @Test func k3NotAssessableWithoutDemandStillShowsPrice() throws {
        let r = try service.assess(gelOffer(quantity: 60, priceEuro: 48))
        #expect(r.assessment.verdict == .notAssessable && r.outcome.tone == .unknown)
        #expect(r.outcome.lines.first?.rule == "R1")
        #expect(abs(r.assessment.offerPricePer100gCarbs! - 3.2) < 1e-9) // 48 € / 1500 g
        #expect(r.outcome.lines.contains { $0.rule == "R6" && $0.text.contains("3,20 €") })
        #expect(r.recommendedQuantity == nil)
    }

    // AC-K4: Prozentabstand nur mit Referenz (≥ 2 eigene Käufe desselben Produkts)
    @Test func k4PercentOnlyWithReference() throws {
        var g = ProductDraft()
        g.name = "Gel"; g.category = .gel; g.carbsPerPortionG = 25; g.quantity = 100; g.totalPriceCents = 5000 // 2,00 €/100 g
        let gel = try inventory.createProduct(g)
        var offer = OfferDraft()
        offer.existingProductID = gel.id; offer.quantity = 100; offer.priceEuro = 40 // 1,60 €/100 g
        let one = try service.assess(offer)
        #expect(one.assessment.percentVersusReference == nil)
        #expect(!one.outcome.lines.contains { $0.text.contains("%") && $0.rule == "R6" })
        try inventory.addBatch(to: gel, quantity: 100, totalPriceCents: 7500) // 3,00 €/100 g → Median 2,50
        let two = try service.assess(offer)
        #expect(abs(two.assessment.percentVersusReference! - (-36)) < 1e-9) // 1,60 gegen 2,50
        #expect(two.outcome.lines.contains { $0.rule == "R6" && $0.text.contains("36,0 % günstiger") })
    }

    // AC-K6: Angebots-MHD mit zu viel Verfall → Menge gesenkt, Verfallsmenge genannt
    @Test func k6ShortExpiryReducesQuantity() throws {
        try dailyDemand100()
        let r = try service.assess(gelOffer(quantity: 100, priceEuro: 30, expiry: today.adding(days: 10)))
        guard case .buyPartially(let n) = r.assessment.verdict else { Issue.record("erwartet: teilweise kaufen"); return }
        #expect(n > 0 && n < 100)
        let r5 = r.outcome.lines.first { $0.rule == "R5" }
        #expect(r5 != nil && r5!.text.contains("verfallen") && r5!.text.contains("Menge auf \(n) gesenkt"))
    }

    // AC-K7: Zahlen und Regelnummer in jeder Zeile, gleiche Eingabe = gleiches Ergebnis
    @Test func k7ReasonsHaveRuleAndNumbersAndAreDeterministic() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        var offer = powderOffer(p, quantity: 3000, priceEuro: 9)
        offer.expiry = today.adding(months: 24)
        let id = UUID()
        let a = try service.assess(offer, id: id), b = try service.assess(offer, id: id)
        #expect(a == b)
        #expect(!a.outcome.lines.isEmpty)
        for line in a.outcome.lines {
            #expect(line.rule.range(of: #"^(R[1-6]|V1)$"#, options: .regularExpression) != nil)
            #expect(line.text.contains { $0.isNumber }, "Zeile \(line.rule) ohne Zahl")
        }
    }

    @Test func horizonAndBargainRuleChangeTheVerdict() throws {
        let p = try powder(stock: 14_000)
        try weeklyDemand900()
        var offer = powderOffer(p, quantity: 3000)
        #expect(try service.assess(offer).assessment.verdict == .dontBuy) // 12 Wochen: 10 800 g < 14 000 g
        offer.horizonWeeks = 26                                           // 26 Wochen: 23 400 g
        #expect(try service.assess(offer).assessment.shortfallG == 9400)
    }

    @Test func invalidOfferThrowsWithProblems() throws {
        #expect(throws: PurchaseService.Failure.invalidOffer([.nameMissing, .carbsNotPositive, .quantityNotPositive])) {
            try service.assess(OfferDraft())
        }
        var d = OfferDraft(); d.existingProductID = UUID(); d.quantity = 1
        #expect(throws: PurchaseService.Failure.productNotFound) { try service.assess(d) }
    }

    // MARK: AC-K5 — Urteil bucht nichts

    @Test func k5AssessmentChangesNothing() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        let before = (count(Product.self), count(Batch.self), count(StockMovement.self), count(PurchaseEvaluation.self),
                      count(ShoppingListItem.self), inventory.stock(of: p))
        _ = try service.assess(powderOffer(p, quantity: 3000, priceEuro: 9))
        _ = try service.assess(gelOffer())
        let after = (count(Product.self), count(Batch.self), count(StockMovement.self), count(PurchaseEvaluation.self),
                     count(ShoppingListItem.self), inventory.stock(of: p))
        #expect(before == after)
    }

    @Test func k5BoughtCreatesBatchAndPurchaseMovementExactlyOnce() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        let r = try service.assess(powderOffer(p, quantity: 3000, priceEuro: 9))
        let item = try service.addToList(r)
        #expect(item.plannedQuantity == 1000 && item.productID == p.id && item.state == .open)
        #expect(item.estimatedTotalPriceCents == 300) // 9 € anteilig für 1000 von 3000 g
        // Eintrag allein bucht nichts
        #expect(count(Batch.self) == 1 && count(StockMovement.self) == 1)

        var draft = BoughtDraft(item: item)
        #expect(draft.quantity == 1000 && draft.totalPriceCents == 300 && draft.productID == p.id)
        draft.expiry = today.adding(months: 12)
        let batch = try service.markBought(item, with: draft)
        #expect(count(Batch.self) == 2 && count(StockMovement.self) == 2)
        #expect(batch.quantityPurchased == 1000 && batch.totalPriceCents == 300 && batch.product?.id == p.id)
        #expect(batch.expiryDay == today.adding(months: 12).isoString)
        let purchase = (batch.movements ?? []).first
        #expect(purchase?.typeRaw == MovementType.purchase.rawValue && purchase?.delta == 1000)
        #expect(purchase?.idempotencyKey == IdempotencyKey.purchase(batchID: batch.id))
        #expect(inventory.stock(of: p) == 10_800)
        #expect(item.state == .bought && item.batchID == batch.id)

        // zweites „Gekauft“ bucht nicht noch einmal
        #expect(throws: PurchaseService.Failure.itemClosed) { try service.markBought(item, with: draft) }
        #expect(count(Batch.self) == 2 && count(StockMovement.self) == 2)
    }

    // MARK: Einkaufsliste

    @Test func onlyBuyVerdictsGoOnTheList() throws {
        let dontBuy = try service.assess(gelOffer()) // ohne Bedarf: nicht beurteilbar
        #expect(throws: PurchaseService.Failure.notBuyable) { try service.addToList(dontBuy) }
        #expect(count(ShoppingListItem.self) == 0)
    }

    @Test func manualEntriesAndDrop() throws {
        var e = ShoppingEntryDraft()
        #expect(throws: PurchaseService.Failure.invalidEntry([.targetMissing, .quantityNotPositive])) { try service.addManually(e) }
        e.freeText = " Riegel "; e.quantity = 12; e.estimatedPriceEuro = 18
        let item = try service.addManually(e)
        #expect(item.freeText == "Riegel" && item.plannedQuantity == 12 && item.estimatedTotalPriceCents == 1800 && item.offerJSON == nil)
        try service.drop(item)
        #expect(item.state == .dropped)
        #expect(count(PurchaseEvaluation.self) == 0) // manueller Eintrag: kein Verlauf
        #expect(throws: PurchaseService.Failure.itemClosed) { try service.drop(item) }
        #expect(throws: PurchaseService.Failure.itemClosed) { try service.markBought(item, with: BoughtDraft(item: item)) }
        try service.remove(item)
        #expect(service.items().isEmpty)
    }

    @Test func manualEntryForExistingProduct() throws {
        let p = try powder(stock: 10)
        var e = ShoppingEntryDraft(); e.productID = p.id; e.quantity = 500
        let item = try service.addManually(e)
        #expect(item.productID == p.id && item.freeText == nil)
        let batch = try service.markBought(item, with: BoughtDraft(item: item)) // Menge 500 vorbelegt, ohne Preis
        #expect(batch.quantityPurchased == 500 && batch.totalPriceCents == nil)
        #expect(inventory.stock(of: p) == 510)
    }

    @Test func manualItemWithFreeTextBuysAsNewProduct() throws {
        var e = ShoppingEntryDraft(); e.freeText = "Riegel"; e.quantity = 12
        let item = try service.addManually(e)
        var draft = BoughtDraft(item: item)
        #expect(throws: PurchaseService.Failure.invalidBought([.newProduct(.carbsNotPositive)])) { try service.markBought(item, with: draft) }
        #expect(item.state == .open && count(Batch.self) == 0) // nichts gebucht, Eintrag bleibt offen
        draft.newProduct.carbsPerPortionG = 30; draft.newProduct.category = .bar
        let batch = try service.markBought(item, with: draft)
        #expect(batch.product?.name == "Riegel" && batch.quantityPurchased == 12)
        #expect(count(Product.self) == 1 && count(StockMovement.self) == 1)
    }

    // MARK: Verlauf (PurchaseEvaluation)

    @Test func historyOnlyAfterExplicitSaveAndIsIdempotent() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        let r = try service.assess(powderOffer(p, quantity: 3000, priceEuro: 9))
        #expect(count(PurchaseEvaluation.self) == 0)
        let e = try service.saveEvaluation(r)
        #expect(e.userDecision == .none && e.verdictRaw == "buyPartially" && e.verdictQuantity == 1000)
        #expect(e.offer?.quantity == 3000 && e.offer?.totalPriceCents == 900 && e.offer?.horizonDays == 84)
        #expect(e.offer?.productName == "Pulver" && e.offer?.isNewProduct == false)
        #expect(e.reasons == r.saved.assessment.reasons && e.reasons.contains { $0.rule == "R2" })
        #expect(e.assessment.verdict == .buyPartially(quantity: 1000))
        // Sichern ist wiederholbar, ohne Dublette
        try service.saveEvaluation(r)
        #expect(count(PurchaseEvaluation.self) == 1)
        // Nutzer entscheidet „nicht gekauft“
        try service.skip(r)
        #expect(count(PurchaseEvaluation.self) == 1 && service.evaluations().first?.userDecision == .skipped)
        #expect(count(Batch.self) == 1 && count(StockMovement.self) == 1) // Verlauf bucht nichts
    }

    @Test func userMarksOpenEvaluationSkippedAndCanDeleteIt() throws {
        let r = try service.assess(gelOffer())
        let e = try service.saveEvaluation(r)
        try service.markSkipped(e)
        #expect(e.userDecision == .skipped)
        // eine getroffene Entscheidung bleibt unverändert
        let bought = try service.saveEvaluation(try service.assess(gelOffer()), decision: .bought)
        try service.markSkipped(bought)
        #expect(bought.userDecision == .bought)
        try service.remove(e)
        #expect(count(PurchaseEvaluation.self) == 1)
    }

    @Test func boughtFromDeciderSavesEvaluationAsBought() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        let r = try service.assess(powderOffer(p, quantity: 3000, priceEuro: 9))
        let draft = r.boughtDraft(existingProductID: p.id)
        #expect(draft.quantity == 1000 && draft.totalPriceCents == 300 && draft.productID == p.id) // anteilig vorbelegt
        let batch = try service.markBought(r, with: draft)
        #expect(batch.quantityPurchased == 1000)
        #expect(count(Batch.self) == 2 && count(StockMovement.self) == 2)
        #expect(service.evaluations().map(\.userDecision) == [.bought])
    }

    @Test func listItemFromVerdictCarriesSnapshotIntoHistory() throws {
        try weeklyDemand900()
        let r = try service.assess(gelOffer(quantity: 600, priceEuro: 480, expiry: today.adding(months: 24)))
        // Gel 25 g, 600 Stück = 15 000 g; kein Bestand → Fehlmenge 10 800 g → 432 Stück sinnvoll
        #expect(r.assessment.verdict == .buyPartially(quantity: 432))
        let item = try service.addToList(r)
        #expect(item.productID == nil && item.freeText == "Gel" && item.plannedQuantity == 432)
        #expect(item.expiryDay == today.adding(months: 24).isoString)
        #expect(item.estimatedTotalPriceCents == 34_560) // 480 € × 432/600
        #expect(count(PurchaseEvaluation.self) == 0) // Eintrag allein sichert keinen Verlauf

        // „Gekauft“: neues Produkt aus dem Angebot, Verlauf = gekauft, gleiche ID wie der Eintrag
        let draft = BoughtDraft(item: item)
        #expect(draft.productID == nil && draft.newProduct.name == "Gel" && draft.newProduct.carbsPerPortionG == 25)
        #expect(draft.expiry == today.adding(months: 24))
        let batch = try service.markBought(item, with: draft)
        #expect(batch.product?.name == "Gel" && batch.quantityPurchased == 432 && batch.totalPriceCents == 34_560)
        #expect(count(Product.self) == 1 && count(Batch.self) == 1 && count(StockMovement.self) == 1)
        let e = service.evaluations()
        #expect(e.count == 1 && e[0].id == item.id && e[0].userDecision == .bought && e[0].offer?.isNewProduct == true)
    }

    @Test func droppingAListItemFromAVerdictRecordsSkipped() throws {
        let p = try powder(stock: 9800)
        try weeklyDemand900()
        let item = try service.addToList(try service.assess(powderOffer(p, quantity: 3000)))
        try service.drop(item)
        #expect(item.state == .dropped)
        let e = service.evaluations()
        #expect(e.count == 1 && e[0].userDecision == .skipped && e[0].verdictRaw == "buyPartially")
        #expect(count(Batch.self) == 1 && count(StockMovement.self) == 1)
    }
}
