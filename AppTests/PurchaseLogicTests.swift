import CarbStockCore
import Foundation
import Testing
@testable import CarbStock

/// Reine Logik des Tabs „Einkauf“: Eingabe → Entwurf → Probleme, Angebotspreis, Anzeigezeilen, Snapshots.
@Suite struct PurchaseLogicTests {
    func gelDraft(quantity: Int? = 60, price: Double? = 48) -> OfferDraft {
        var d = OfferDraft()
        d.newProduct.name = "Gel"; d.newProduct.category = .gel; d.newProduct.carbsPerPortionG = 25
        d.quantity = quantity; d.priceEuro = price
        return d
    }

    @Test func emptyDraftListsEveryMissingField() {
        let d = OfferDraft()
        #expect(d.problems() == [.nameMissing, .carbsNotPositive, .quantityNotPositive])
        #expect(d.problems().allSatisfy { !$0.message.isEmpty })
        #expect(gelDraft().problems().isEmpty)
    }

    @Test func existingProductNeedsNoNewProductFields() {
        var d = OfferDraft()
        d.existingProductID = UUID(); d.quantity = 10
        #expect(d.problems().isEmpty)
    }

    @Test func rangeProblems() {
        var d = gelDraft()
        d.priceEuro = -1; d.shippingEuro = -2; d.discountValue = 120; d.horizonWeeks = 0
        #expect(d.problems() == [.priceNegative, .shippingNegative, .discountAbove100Percent, .horizonOutOfRange])
        d.discountKind = .euro; d.discountValue = -3; d.horizonWeeks = 105
        #expect(d.problems() == [.priceNegative, .shippingNegative, .discountNegative, .horizonOutOfRange])
    }

    @Test func defaultsFollowTheSpec() {
        let d = OfferDraft()
        #expect(d.horizonWeeks == 12 && d.horizonDays == 84) // 4.4: Kaufhorizont 12 Wochen
        #expect(!d.bargainRule)                              // O-05: Schnäppchenregel aus
        #expect(d.parameters.horizonDays == 84 && !d.parameters.bargainRule)
    }

    @Test func totalPriceWithShippingAndDiscount() {
        var d = gelDraft(quantity: 60, price: 48)
        d.shippingEuro = 4.90; d.discountValue = 10 // 10 %
        let p = d.price(unit: .piece)
        #expect(p?.goodsCents == 4800 && p?.discountCents == 480 && p?.shippingCents == 490 && p?.totalCents == 4810)
    }

    @Test func unitPriceTimesQuantity() {
        var d = gelDraft(quantity: 60, price: 0.80)
        d.priceMode = .perUnit
        #expect(d.price(unit: .piece)?.totalCents == 4800)
        d.discountKind = .euro; d.discountValue = 3 // 3 € Gutschein
        #expect(d.price(unit: .piece)?.totalCents == 4500)
    }

    @Test func powderUnitPriceIsPerKilogram() {
        var d = gelDraft(quantity: 2500, price: 6) // 6 € je kg, 2,5 kg
        d.priceMode = .perUnit
        #expect(d.price(unit: .gram)?.totalCents == 1500)
    }

    @Test func noPriceGivesNoOfferPrice() {
        #expect(gelDraft(price: nil).price(unit: .piece) == nil)
        #expect(gelDraft(quantity: nil).price(unit: .piece) == nil)
    }

    @Test func newProductGetsStableIDAndTrimmedFields() {
        var d = gelDraft()
        d.newProduct.name = "  Gel  "; d.newProduct.brand = " "
        let a = d.productInfo(existing: nil), b = d.productInfo(existing: nil)
        #expect(a == b && a?.name == "Gel" && a?.brand == nil && a?.carbsPerBaseUnit == 25)
    }

    @Test func flavorFlowsFromNewProductThroughSnapshotToDraft() throws {
        var d = gelDraft()
        d.newProduct.name = "Gel"; d.newProduct.flavor = " Zitrone "
        let info = try #require(d.productInfo(existing: nil))
        #expect(info.flavor == "Zitrone")
        d.newProduct.flavor = " "
        #expect(d.productInfo(existing: nil)?.flavor == nil)
    }

    /// Verlauf und Einkaufsliste aus der Version ohne Geschmack (Feld fehlt im JSON) bleiben lesbar.
    @Test func oldOfferSnapshotWithoutFlavorStillDecodes() throws {
        let json = #"{"productID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","isNewProduct":true,"productName":"Gel","categoryRaw":"gel","baseUnitRaw":"piece","portionAmount":1,"carbsPerPortionG":25,"quantity":10,"horizonDays":84,"bargainRule":false}"#
        let s = try JSONDecoder().decode(OfferSnapshot.self, from: Data(json.utf8))
        #expect(s.flavor == nil && s.productDraft.flavor.isEmpty)
        var withFlavor = s; withFlavor.flavor = "Cola"
        let back = try JSONDecoder().decode(OfferSnapshot.self, from: try JSONEncoder().encode(withFlavor))
        #expect(back.productDraft.flavor == "Cola")
    }

    @Test func additivesFlowFromNewProductThroughSnapshotToDraft() throws {
        var d = gelDraft()
        d.newProduct.name = "Gel"; d.newProduct.hasCaffeine = true; d.newProduct.hasLactate = true
        let info = try #require(d.productInfo(existing: nil))
        #expect(info.hasCaffeine && info.hasLactate)
        d.newProduct.hasLactate = false
        #expect(d.productInfo(existing: nil).map { $0.hasCaffeine && !$0.hasLactate } == true)
    }

    /// Verlauf aus der Version ohne Zusätze (Felder fehlen im JSON) bleibt lesbar; Zusätze überleben Kodieren/Dekodieren.
    @Test func oldOfferSnapshotWithoutAdditivesStillDecodes() throws {
        let json = #"{"productID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","isNewProduct":true,"productName":"Gel","categoryRaw":"gel","baseUnitRaw":"piece","portionAmount":1,"carbsPerPortionG":25,"quantity":10,"horizonDays":84,"bargainRule":false}"#
        let s = try JSONDecoder().decode(OfferSnapshot.self, from: Data(json.utf8))
        #expect(s.productDraft.hasCaffeine == false && s.productDraft.hasLactate == false)
        var with = s; with.hasCaffeine = true; with.hasLactate = true
        let back = try JSONDecoder().decode(OfferSnapshot.self, from: try JSONEncoder().encode(with))
        #expect(back.productDraft.hasCaffeine && back.productDraft.hasLactate)
    }

    @Test func moneyRounding() {
        #expect(Money.cents(fromEuro: 0.8) == 80 && Money.cents(fromEuro: 4.9) == 490 && Money.cents(fromEuro: 19.995) == 2000)
        #expect(Money.cents(fromEuro: nil) == nil)
    }

    // AC-K7: jede Begründungszeile hat Regelnummer und Zahlen; Titel ohne Fachjargon
    @Test func outcomeTranslatesVerdictAndLines() {
        let reasons = [ReasonSnapshot(rule: "R2", text: "Bedarf 900 g, nutzbarer Bestand 0 g in 84 Tagen: Fehlmenge 900 g Carbs.", values: ["shortfallG": 900]),
                       ReasonSnapshot(rule: "R6", text: "Preis: 3,20 € je 100 g Carbs.", values: ["pricePer100gCarbs": 3.2])]
        let o = PurchaseOutcome(verdict: .buyPartially(quantity: 36), reasons: reasons, unit: .piece, offeredQuantity: 60)
        #expect(o.tone == .partial && o.title == "Teilweise kaufen: 36 Stk" && o.symbol == "circle.lefthalf.filled")
        #expect(o.detail == "Angeboten sind 60 Stk, sinnvoll sind 36 Stk.")
        #expect(o.lines.map(\.rule) == ["R2", "R6"] && o.lines.map(\.title) == ["Fehlmenge", "Preis"])
        #expect(o.lines.allSatisfy { $0.text.contains { $0.isNumber } })
        #expect(PurchaseOutcome(verdict: .buy, reasons: [], unit: .piece).title == "Kaufen")
        #expect(PurchaseOutcome(verdict: .dontBuy, reasons: [], unit: .piece).tone == .dontBuy)
        let none = PurchaseOutcome(verdict: .notAssessable, reasons: [], unit: .piece)
        #expect(none.tone == .unknown && none.title == "Nicht beurteilbar")
        #expect(PurchaseOutcome(verdict: .buyPartially(quantity: 40), reasons: [], unit: .gram).title == "Teilweise kaufen: 40 g")
    }

    @Test func everyRuleHasAGermanTitle() {
        for rule in ["R1", "R2", "R3", "R4", "R5", "R6", "V1"] { #expect(PurchaseOutcome.ruleTitle(rule) != "Regel") }
    }

    @Test func assessmentSnapshotRoundTripsAllVerdicts() throws {
        let cases: [(PurchaseVerdict, String, Int?)] = [(.buy, "buy", nil), (.buyPartially(quantity: 7), "buyPartially", 7),
                                                         (.dontBuy, "dontBuy", nil), (.notAssessable, "notAssessable", nil)]
        for (verdict, raw, quantity) in cases {
            let s = AssessmentSnapshot(verdictRaw: raw, verdictQuantity: quantity,
                                       reasons: [ReasonSnapshot(rule: "R2", text: "Fehlmenge 5 g", values: ["shortfallG": 5])])
            #expect(s.verdict == verdict)
            let back = try JSONDecoder().decode(AssessmentSnapshot.self, from: JSONEncoder().encode(s))
            #expect(back == s)
        }
        #expect(AssessmentSnapshot(verdictRaw: "???", verdictQuantity: nil, reasons: []).verdict == .notAssessable)
    }

    @Test func boughtDraftValidationAndPrefill() throws {
        var d = BoughtDraft()
        #expect(d.problems == [.newProduct(.nameMissing), .newProduct(.carbsNotPositive), .quantityNotPositive])
        d.productID = UUID(); d.quantity = 5; d.totalPriceCents = -1
        #expect(d.problems == [.priceNegative])
        let item = ShoppingListItem(freeText: "Riegel", plannedQuantity: 12, estimatedTotalPriceCents: 1800)
        item.expiryDay = "2027-05-01"
        let pre = BoughtDraft(item: item)
        #expect(pre.newProduct.name == "Riegel" && pre.quantity == 12 && pre.totalPriceCents == 1800)
        #expect(pre.expiry == CalendarDay(year: 2027, month: 5, day: 1))
    }

    @Test func entryDraftValidation() {
        var e = ShoppingEntryDraft()
        #expect(e.problems == [.targetMissing, .quantityNotPositive])
        e.freeText = "  Gele  "; e.quantity = 5; e.estimatedPriceEuro = -1
        #expect(e.problems == [.priceNegative] && e.trimmedText == "Gele")
        e.estimatedPriceEuro = 3.5
        #expect(e.problems.isEmpty && e.estimatedCents == 350)
    }
}
