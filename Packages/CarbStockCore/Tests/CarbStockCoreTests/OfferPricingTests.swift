import Foundation
import Testing
@testable import CarbStockCore

/// Angebotspreis aus Gesamt- oder Stückpreis, Versand und Rabatt (Spec 4.4, O-13).
@Suite struct OfferPricingTests {
    @Test func totalPriceWithoutExtras() {
        let p = OfferPricing.price(basis: .total(cents: 4800), quantity: 60)
        #expect(p?.goodsCents == 4800 && p?.discountCents == 0 && p?.shippingCents == 0 && p?.totalCents == 4800)
        #expect(p?.perUnitCents == 80) // 0,80 € je Stück
    }

    @Test func unitPriceTimesQuantity() {
        // 60 Gele zu 0,80 € = 48,00 €; Stückpreis mit halben Cent wird erst im Gesamtbetrag gerundet.
        #expect(OfferPricing.price(basis: .perUnit(cents: 80, unitSize: 1), quantity: 60)?.totalCents == 4800)
        #expect(OfferPricing.price(basis: .perUnit(cents: 79.5, unitSize: 1), quantity: 3)?.totalCents == 239) // 238,5 -> 239
    }

    @Test func unitPricePerKilogramForPowder() {
        // 2,50 € je kg, 2000 g -> 5,00 €
        #expect(OfferPricing.price(basis: .perUnit(cents: 250, unitSize: 1000), quantity: 2000)?.totalCents == 500)
    }

    @Test func shippingAndDiscount() {
        // 48,00 € Ware, 10 % Rabatt (4,80), 4,90 € Versand -> 48,10 €
        let p = OfferPricing.price(basis: .total(cents: 4800), quantity: 60, shippingCents: 490, discount: .percent(10))
        #expect(p?.discountCents == 480 && p?.shippingCents == 490 && p?.totalCents == 4810)
        #expect(p?.perUnitCents ?? 0 > 80.16 - 1e-9 && p?.perUnitCents ?? 0 < 80.17) // 4810 / 60
        // fester Rabatt (Gutschein), Versand bleibt
        let c = OfferPricing.price(basis: .total(cents: 4800), quantity: 60, shippingCents: 490, discount: .cents(500))
        #expect(c?.totalCents == 4790)
    }

    @Test func discountNeverGoesBelowZeroOrAboveHundredPercent() {
        #expect(OfferPricing.price(basis: .total(cents: 1000), quantity: 10, discount: .cents(5000))?.totalCents == 0)
        #expect(OfferPricing.price(basis: .total(cents: 1000), quantity: 10, shippingCents: 300, discount: .percent(150))?.totalCents == 300)
        #expect(OfferPricing.price(basis: .total(cents: 1000), quantity: 10, discount: .percent(-5))?.discountCents == 0)
    }

    @Test func percentDiscountRoundsHalfAwayFromZero() {
        // 33,3 % von 10,01 € = 333,333 ct -> 333 ct
        #expect(OfferPricing.price(basis: .total(cents: 1001), quantity: 1, discount: .percent(33.3))?.discountCents == 333)
        // 12,5 % von 1,00 € = 12,5 ct -> 13 ct
        #expect(OfferPricing.price(basis: .total(cents: 100), quantity: 1, discount: .percent(12.5))?.discountCents == 13)
    }

    @Test func invalidInputGivesNoPrice() {
        #expect(OfferPricing.price(basis: .total(cents: 100), quantity: 0) == nil)
        #expect(OfferPricing.price(basis: .total(cents: -1), quantity: 5) == nil)
        #expect(OfferPricing.price(basis: .total(cents: 100), quantity: 5, shippingCents: -1) == nil)
        #expect(OfferPricing.price(basis: .perUnit(cents: 10, unitSize: 0), quantity: 5) == nil)
    }

    /// Passt zum Kauf-Urteil: 60 Gele à 25 g für 48,00 € sind 3,20 € je 100 g Carbs.
    @Test func feedsTheAdvisorPrice() {
        let gel = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        let p = OfferPricing.price(basis: .perUnit(cents: 80, unitSize: 1), quantity: 60)!
        let context = PurchaseContext(today: CalendarDay(year: 2026, month: 11, day: 23), lots: [],
                                      series: DemandSeries(start: CalendarDay(year: 2026, month: 11, day: 23), dailyG: []))
        let a = PurchaseAdvisor.assess(offer: PurchaseOffer(product: gel, quantity: 60, totalPriceCents: p.totalCents), context: context)
        #expect(abs(a.offerPricePer100gCarbs! - 3.2) < 1e-9)
    }
}
