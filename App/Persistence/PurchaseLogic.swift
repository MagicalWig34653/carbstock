import CarbStockCore
import Foundation

// Pure Logik des Tabs „Einkauf“ (Spec 4.4, 5.7, 7.3): Eingabe → Entwurf → Probleme, Angebotspreis,
// Übersetzung des Core-Urteils in Anzeigezeilen, Snapshots für Verlauf und Einkaufsliste.
// Kein SwiftData, keine Uhr, kein SwiftUI. Die Rechenregeln selbst liegen im Core (PurchaseAdvisor, OfferPricing).

enum Money {
    /// 12,34 € → 1234 ct (kaufmännisch gerundet). Nil bleibt nil.
    static func cents(fromEuro euro: Double?) -> Int? {
        guard let euro, euro.isFinite else { return nil }
        return Int((euro * 100).rounded(.toNearestOrAwayFromZero))
    }
}

// MARK: Angebot (Eingabe des Kauf-Entscheiders)

enum OfferLimits {
    /// Der Bedarf wird höchstens 730 Tage vorausberechnet (Forecast.run), also höchstens 104 Wochen Horizont.
    static let horizonWeeks = 1...104
    static let defaultHorizonWeeks = 12
}

enum OfferPriceMode: String, CaseIterable, Identifiable, Sendable {
    case total, perUnit
    var id: String { rawValue }
}

enum OfferDiscountKind: String, CaseIterable, Identifiable, Sendable {
    case percent, euro
    var id: String { rawValue }
}

/// Angebot, wie die Nutzerin/der Nutzer es eingibt (Spec 4.4). Kein Gedankenspiel-Zustand wird gespeichert.
struct OfferDraft: Equatable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        case nameMissing, carbsNotPositive, portionNotPositive
        case quantityNotPositive, priceNegative, shippingNegative, discountNegative, discountAbove100Percent
        case horizonOutOfRange

        var message: String {
            switch self {
            case .nameMissing: "Bitte einen Produktnamen eingeben."
            case .carbsNotPositive: "Carbs je Portion müssen größer als 0 sein."
            case .portionNotPositive: "Die Portionsgröße muss größer als 0 sein."
            case .quantityNotPositive: "Bitte die Menge des Angebots eingeben (größer als 0)."
            case .priceNegative: "Der Preis darf nicht negativ sein."
            case .shippingNegative: "Die Versandkosten dürfen nicht negativ sein."
            case .discountNegative: "Der Rabatt darf nicht negativ sein."
            case .discountAbove100Percent: "Der Rabatt kann höchstens 100 % betragen."
            case .horizonOutOfRange: "Der Kaufhorizont muss zwischen 1 und 104 Wochen liegen."
            }
        }
    }

    /// Nil = neues Produkt (Felder in `newProduct`), sonst ein vorhandenes Produkt.
    var existingProductID: UUID?
    var newProduct = ProductDraft()
    var quantity: Int?
    var priceMode: OfferPriceMode = .total
    /// Gesamtpreis oder Preis je Einheit in Euro (je Stück, bei Pulver je kg), wie `priceMode` sagt.
    var priceEuro: Double?
    var shippingEuro: Double?
    var discountValue: Double?
    var discountKind: OfferDiscountKind = .percent
    var expiry: CalendarDay?
    var horizonWeeks = OfferLimits.defaultHorizonWeeks
    /// Schnäppchenregel (O-05): standardmäßig aus.
    var bargainRule = false
    /// Stabile ID, damit ein neues Produkt bei jeder Bewertung dieselbe ID hat (Determinismus, AC-K7).
    var newProductID = UUID()

    var horizonDays: Int { horizonWeeks * 7 }

    func problems(existing: ProductInfo? = nil) -> [Problem] {
        var list: [Problem] = []
        if existingProductID == nil {
            let p = newProduct
            if p.name.trimmingCharacters(in: .whitespaces).isEmpty { list.append(.nameMissing) }
            if !(p.carbsPerPortionG > 0) { list.append(.carbsNotPositive) }
            if !(p.effectivePortion > 0) { list.append(.portionNotPositive) }
        }
        if (quantity ?? 0) <= 0 { list.append(.quantityNotPositive) }
        if let p = priceEuro, p < 0 { list.append(.priceNegative) }
        if let s = shippingEuro, s < 0 { list.append(.shippingNegative) }
        if let d = discountValue {
            if d < 0 { list.append(.discountNegative) }
            if discountKind == .percent, d > 100 { list.append(.discountAbove100Percent) }
        }
        if !OfferLimits.horizonWeeks.contains(horizonWeeks) { list.append(.horizonOutOfRange) }
        return list
    }

    /// Das Produkt des Angebots: das vorhandene (`existing`) oder das neu eingegebene.
    func productInfo(existing: ProductInfo?) -> ProductInfo? {
        if existingProductID != nil { return existing }
        let p = newProduct
        let brand = p.brand.trimmingCharacters(in: .whitespaces)
        return ProductInfo(id: newProductID, name: p.name.trimmingCharacters(in: .whitespaces),
                           brand: brand.isEmpty ? nil : brand, category: p.category, baseUnit: p.baseUnit,
                           portionAmount: p.effectivePortion, carbsPerPortionG: p.carbsPerPortionG,
                           glucoseFructoseRatio: p.glucoseFructoseRatio)
    }

    /// Angebotspreis nach Versand und Rabatt (Core `OfferPricing`). Nil ohne Preis oder bei ungültiger Eingabe.
    func price(unit: BaseUnit) -> OfferPrice? {
        guard let quantity, let euro = priceEuro, let cents = Money.cents(fromEuro: euro) else { return nil }
        let basis: OfferPriceBasis = priceMode == .total
            ? .total(cents: cents)
            : .perUnit(cents: euro * 100, unitSize: unit == .gram ? 1000 : 1)
        let discount: OfferDiscount? = discountValue.flatMap { v in
            guard v > 0 else { return nil }
            return discountKind == .percent ? .percent(v) : Money.cents(fromEuro: v).map(OfferDiscount.cents)
        }
        return OfferPricing.price(basis: basis, quantity: quantity, shippingCents: Money.cents(fromEuro: shippingEuro) ?? 0,
                                  discount: discount)
    }

    var parameters: PurchaseParameters {
        var p = PurchaseParameters()
        p.horizonDays = horizonDays
        p.bargainRule = bargainRule
        return p
    }
}

// MARK: Snapshots (Verlauf und Einkaufsliste, JSON)

/// Eingabe-Snapshot einer Bewertung (Spec 5.7): Produkt, Menge, Preis, MHD, Horizont.
struct OfferSnapshot: Codable, Equatable, Sendable {
    var productID: UUID
    /// True, wenn das Produkt zum Zeitpunkt der Bewertung noch nicht angelegt war.
    var isNewProduct: Bool
    var productName: String
    var brand: String?
    var categoryRaw: String
    var baseUnitRaw: String
    var portionAmount: Double
    var carbsPerPortionG: Double
    var glucoseFructoseRatio: Double?
    var quantity: Int
    /// Endpreis nach Versand und Rabatt.
    var totalPriceCents: Int?
    var shippingCents: Int?
    var discountCents: Int?
    var expiryDay: String?
    var horizonDays: Int
    var bargainRule: Bool

    var baseUnit: BaseUnit { BaseUnit(rawValue: baseUnitRaw) ?? .piece }
    var category: ProductCategory { ProductCategory(rawValue: categoryRaw) ?? .gel }
    var expiry: CalendarDay? { expiryDay.flatMap(CalendarDay.init(isoString:)) }

    /// Produktfelder als Entwurf für „Neues Produkt“ (z. B. beim Kauf aus der Einkaufsliste).
    var productDraft: ProductDraft {
        var d = ProductDraft()
        d.name = productName; d.brand = brand ?? ""; d.category = category; d.baseUnit = baseUnit
        d.portionAmount = portionAmount; d.carbsPerPortionG = carbsPerPortionG
        d.glucoseFructoseRatio = glucoseFructoseRatio
        return d
    }
}

struct ReasonSnapshot: Codable, Equatable, Sendable {
    var rule: String
    var text: String
    var values: [String: Double]
}

/// Ergebnis-Snapshot: Urteil und Begründungszeilen (strukturiert, mit Regelnummer).
struct AssessmentSnapshot: Codable, Equatable, Sendable {
    /// buy · buyPartially · dontBuy · notAssessable
    var verdictRaw: String
    var verdictQuantity: Int?
    var reasons: [ReasonSnapshot]
    var pricePer100gCarbs: Double?
    var percentVersusReference: Double?

    init(_ a: PurchaseAssessment) {
        switch a.verdict {
        case .buy: verdictRaw = "buy"; verdictQuantity = nil
        case .buyPartially(let n): verdictRaw = "buyPartially"; verdictQuantity = n
        case .dontBuy: verdictRaw = "dontBuy"; verdictQuantity = nil
        case .notAssessable: verdictRaw = "notAssessable"; verdictQuantity = nil
        }
        reasons = a.reasons.map { ReasonSnapshot(rule: $0.rule.rawValue, text: $0.text, values: $0.values) }
        pricePer100gCarbs = a.offerPricePer100gCarbs
        percentVersusReference = a.percentVersusReference
    }

    init(verdictRaw: String, verdictQuantity: Int?, reasons: [ReasonSnapshot],
         pricePer100gCarbs: Double? = nil, percentVersusReference: Double? = nil) {
        self.verdictRaw = verdictRaw; self.verdictQuantity = verdictQuantity; self.reasons = reasons
        self.pricePer100gCarbs = pricePer100gCarbs; self.percentVersusReference = percentVersusReference
    }

    var verdict: PurchaseVerdict {
        switch verdictRaw {
        case "buy": .buy
        case "buyPartially": .buyPartially(quantity: verdictQuantity ?? 0)
        case "dontBuy": .dontBuy
        default: .notAssessable
        }
    }
}

/// Angebot samt Urteil, wie es an einem Einkaufslisten-Eintrag hängt (`ShoppingListItem.offerJSON`).
struct SavedOffer: Codable, Equatable, Sendable {
    var offer: OfferSnapshot
    var assessment: AssessmentSnapshot
}

enum UserDecision: String, Sendable {
    case none, bought, skipped
    var title: String {
        switch self {
        case .none: "Offen"
        case .bought: "Gekauft"
        case .skipped: "Nicht gekauft"
        }
    }
    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .bought: "checkmark.circle.fill"
        case .skipped: "xmark.circle.fill"
        }
    }
}

enum ShoppingItemState: String, Sendable {
    case open, bought, dropped
}

extension ShoppingListItem {
    var state: ShoppingItemState { ShoppingItemState(rawValue: stateRaw) ?? .open }
    var savedOffer: SavedOffer? { offerJSON.flatMap { try? JSONDecoder().decode(SavedOffer.self, from: $0) } }
    var expiry: CalendarDay? { expiryDay.flatMap(CalendarDay.init(isoString:)) }
}

extension PurchaseEvaluation {
    var userDecision: UserDecision { UserDecision(rawValue: userDecisionRaw) ?? .none }
    var offer: OfferSnapshot? { inputJSON.flatMap { try? JSONDecoder().decode(OfferSnapshot.self, from: $0) } }
    var reasons: [ReasonSnapshot] { reasonsJSON.flatMap { try? JSONDecoder().decode([ReasonSnapshot].self, from: $0) } ?? [] }
    var assessment: AssessmentSnapshot {
        AssessmentSnapshot(verdictRaw: verdictRaw, verdictQuantity: verdictQuantity, reasons: reasons,
                           pricePer100gCarbs: reasons.compactMap { $0.values["pricePer100gCarbs"] }.first,
                           percentVersusReference: reasons.compactMap { $0.values["percentVersusReference"] }.first)
    }
}

// MARK: Anzeige des Urteils

enum VerdictTone: Equatable, Sendable { case buy, partial, dontBuy, unknown }

struct ReasonLine: Identifiable, Equatable, Sendable {
    /// „R3“ … „R6“, „V1“ (Mischverhältnis)
    let rule: String
    /// Kurzer Titel ohne Fachjargon.
    let title: String
    /// Text mit eingesetzten Zahlen (kommt aus dem Core).
    let text: String
    var id: String { rule + "|" + text }
}

/// Core-Urteil als Anzeigemodell (AC-K7: jede Zeile hat Zahlen und Regelnummer). Farbe ist nie das einzige
/// Signal: Titel und Symbol tragen das Urteil ebenfalls.
struct PurchaseOutcome: Equatable, Sendable {
    let tone: VerdictTone
    let title: String
    let detail: String?
    let symbol: String
    let lines: [ReasonLine]

    init(verdict: PurchaseVerdict, reasons: [ReasonSnapshot], unit: BaseUnit, offeredQuantity: Int? = nil) {
        switch verdict {
        case .buy:
            tone = .buy; title = "Kaufen"; symbol = "checkmark.circle.fill"
            detail = "Das ganze Angebot passt zu deinem Bedarf."
        case .buyPartially(let n):
            tone = .partial; title = "Teilweise kaufen: \(Fmt.quantity(n, unit: unit))"; symbol = "circle.lefthalf.filled"
            detail = offeredQuantity.map { "Angeboten sind \(Fmt.quantity($0, unit: unit)), sinnvoll sind \(Fmt.quantity(n, unit: unit))." }
        case .dontBuy:
            tone = .dontBuy; title = "Nicht kaufen"; symbol = "xmark.octagon.fill"
            detail = nil
        case .notAssessable:
            tone = .unknown; title = "Nicht beurteilbar"; symbol = "questionmark.circle.fill"
            detail = "Ohne bekannten Bedarf gibt es kein ehrliches Ja oder Nein. Der Preis je 100 g Carbs ist trotzdem berechnet."
        }
        lines = reasons.map { ReasonLine(rule: $0.rule, title: Self.ruleTitle($0.rule), text: $0.text) }
    }

    init(_ s: AssessmentSnapshot, unit: BaseUnit, offeredQuantity: Int? = nil) {
        self.init(verdict: s.verdict, reasons: s.reasons, unit: unit, offeredQuantity: offeredQuantity)
    }

    static func ruleTitle(_ rule: String) -> String {
        switch rule {
        case "R1": "Datenlage"
        case "R2": "Fehlmenge"
        case "R3": "Bestand reicht"
        case "R4": "Sinnvolle Menge"
        case "R5": "Haltbarkeit"
        case "R6": "Preis"
        case "V1": "Mischverhältnis"
        default: "Regel"
        }
    }
}

// MARK: Gekauft

/// Eingaben der Bestätigung „Gekauft“ (Charge + Kaufbuchung), vorbelegt aus dem Angebot bzw. Listeneintrag.
struct BoughtDraft: Equatable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        case productMissing, quantityNotPositive, priceNegative
        case newProduct(ProductDraft.Problem)

        var message: String {
            switch self {
            case .productMissing: "Bitte ein Produkt wählen."
            case .quantityNotPositive: "Die Menge muss größer als 0 sein."
            case .priceNegative: "Der Preis darf nicht negativ sein."
            case .newProduct(let p): p.message
            }
        }
    }

    /// Nil = neues Produkt aus `newProduct`.
    var productID: UUID?
    var newProduct = ProductDraft()
    var quantity: Int = 0
    var totalPriceCents: Int?
    var expiry: CalendarDay?
    var purchaseDay: CalendarDay?

    init() {}

    init(offer: OfferSnapshot, existingProductID: UUID?, quantity: Int, totalPriceCents: Int?) {
        self.productID = existingProductID
        self.newProduct = offer.productDraft
        self.quantity = quantity
        self.totalPriceCents = totalPriceCents
        self.expiry = offer.expiry
    }

    /// Eintrag der Einkaufsliste: Angebot (falls vorhanden) liefert die Produktfelder, sonst Freitext als Name.
    init(item: ShoppingListItem) {
        if let saved = item.savedOffer {
            newProduct = saved.offer.productDraft
        } else {
            newProduct.name = item.freeText ?? ""
        }
        productID = item.productID
        quantity = item.plannedQuantity
        totalPriceCents = item.estimatedTotalPriceCents
        expiry = item.expiry
    }

    var problems: [Problem] {
        var list: [Problem] = []
        if productID == nil {
            let p = newProduct
            if p.name.trimmingCharacters(in: .whitespaces).isEmpty { list.append(.newProduct(.nameMissing)) }
            if !(p.carbsPerPortionG > 0) { list.append(.newProduct(.carbsNotPositive)) }
            if !(p.effectivePortion > 0) { list.append(.newProduct(.portionNotPositive)) }
        }
        if quantity <= 0 { list.append(.quantityNotPositive) }
        if let c = totalPriceCents, c < 0 { list.append(.priceNegative) }
        return list
    }

    /// Entwurf für `InventoryService.createProduct` (neues Produkt + erste Charge + Kaufbuchung).
    var productDraft: ProductDraft {
        var d = newProduct
        d.quantity = quantity
        d.totalPriceCents = totalPriceCents
        d.expiry = expiry
        d.purchaseDay = purchaseDay
        d.source = "Einkauf"
        return d
    }
}

/// Eingabe „Manuell zur Einkaufsliste“.
struct ShoppingEntryDraft: Equatable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        case targetMissing, quantityNotPositive, priceNegative
        var message: String {
            switch self {
            case .targetMissing: "Bitte ein Produkt wählen oder einen Text eingeben."
            case .quantityNotPositive: "Die Menge muss größer als 0 sein."
            case .priceNegative: "Der Preis darf nicht negativ sein."
            }
        }
    }

    var productID: UUID?
    var freeText = ""
    var quantity: Int?
    var estimatedPriceEuro: Double?

    var trimmedText: String { freeText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var estimatedCents: Int? { Money.cents(fromEuro: estimatedPriceEuro) }

    var problems: [Problem] {
        var list: [Problem] = []
        if productID == nil, trimmedText.isEmpty { list.append(.targetMissing) }
        if (quantity ?? 0) <= 0 { list.append(.quantityNotPositive) }
        if let c = estimatedCents, c < 0 { list.append(.priceNegative) }
        return list
    }
}
