import Foundation

// Angebotspreis (Spec 4.4: "Gesamtpreis oder Stückpreis, optional Versandkosten und Rabatt", O-13).
// Alles in Cent; gerundet wird nur der Gesamtbetrag (kaufmännisch, .5 nach oben), nie vorher.

public enum OfferPriceBasis: Hashable, Sendable {
    /// Gesamtpreis der Ware (vor Rabatt und Versand).
    case total(cents: Int)
    /// Preis je Einheit; `unitSize` = Mengeneinheiten, auf die sich der Preis bezieht (Stück: 1, Pulver je kg: 1000).
    case perUnit(cents: Double, unitSize: Int)
}

public enum OfferDiscount: Hashable, Sendable {
    /// Prozent vom Warenwert (0 ... 100, außerhalb wird begrenzt).
    case percent(Double)
    /// Fester Betrag in Cent (z. B. Gutschein).
    case cents(Int)
}

public struct OfferPrice: Hashable, Sendable {
    public let goodsCents: Int
    public let discountCents: Int
    public let shippingCents: Int
    /// Ware − Rabatt + Versand: das, was tatsächlich bezahlt wird (geht als Angebotspreis ins Urteil).
    public let totalCents: Int
    public let quantity: Int
    /// Effektiver Preis je Basiseinheit in Cent (nicht gerundet).
    public var perUnitCents: Double { Double(totalCents) / Double(quantity) }
}

public enum OfferPricing {
    /// Annahme (O-13): der Rabatt gilt nur für die Ware, nicht für den Versand; er kann die Ware höchstens auf 0 senken.
    /// Nil bei ungültiger Eingabe (Menge ≤ 0, negative Preise/Versand, Preiseinheit ≤ 0).
    public static func price(basis: OfferPriceBasis, quantity: Int, shippingCents: Int = 0,
                             discount: OfferDiscount? = nil) -> OfferPrice? {
        guard quantity > 0, shippingCents >= 0 else { return nil }
        let goods: Int
        switch basis {
        case .total(let cents):
            guard cents >= 0 else { return nil }
            goods = cents
        case .perUnit(let cents, let unitSize):
            guard cents >= 0, cents.isFinite, unitSize > 0 else { return nil }
            goods = roundCents(cents * Double(quantity) / Double(unitSize))
        }
        var off = 0
        switch discount {
        case .percent(let p)?: off = roundCents(Double(goods) * min(100, max(0, p)) / 100)
        case .cents(let c)?: off = max(0, c)
        case nil: break
        }
        off = min(off, goods)
        return OfferPrice(goodsCents: goods, discountCents: off, shippingCents: shippingCents,
                          totalCents: goods - off + shippingCents, quantity: quantity)
    }

    static func roundCents(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }
}
