import Foundation

// Kauf-Urteil (Spec 4.4, 7.3): deterministische Regeln R1-R6, Begründung als strukturierte Liste.

public struct PurchaseOffer: Hashable, Sendable {
    public var product: ProductInfo
    /// Offered quantity in the product's base unit.
    public var quantity: Int
    /// Total price incl. shipping/discount (O-13); nil = unknown.
    public var totalPriceCents: Int?
    public var expiryDate: CalendarDay?

    public init(product: ProductInfo, quantity: Int, totalPriceCents: Int? = nil, expiryDate: CalendarDay? = nil) {
        self.product = product
        self.quantity = quantity
        self.totalPriceCents = totalPriceCents
        self.expiryDate = expiryDate
    }
}

/// Own earlier batch with its product, the basis of the reference price (4.4).
public struct PricedBatch: Hashable, Sendable {
    public var product: ProductInfo
    public var batch: BatchInfo
    public init(product: ProductInfo, batch: BatchInfo) {
        self.product = product
        self.batch = batch
    }
}

/// Tunable parameters with the defaults of 7.3 / O-05.
public struct PurchaseParameters: Hashable, Sendable {
    public var horizonDays = 84
    /// Bargain rule (O-05): off by default.
    public var bargainRule = false
    /// Annahme: with the bargain rule on, a price at least this many percent below the reference counts as bargain.
    public var bargainDiscountPercent = 20.0
    /// R5: more than this share of the offered quantity expiring unconsumed reduces the quantity.
    public var expiryLossThreshold = 0.10
    /// R6: price more than this many percent above the reference adds "only if needed urgently".
    public var priceDeviationPercent = 15.0
    public var minOwnPurchases = 2
    public var minCategoryPurchases = 3
    /// Annahme (4.2 Verhältnis, Spec 14 Vorschlag): ratios that differ by more than this are reported as different.
    public var ratioTolerance = 0.05
    public init() {}
}

public struct PurchaseContext: Sendable {
    public var today: CalendarDay
    public var lots: [StockLot]
    public var series: DemandSeries
    public var history: [PricedBatch]

    public init(today: CalendarDay, lots: [StockLot], series: DemandSeries, history: [PricedBatch] = []) {
        self.today = today
        self.lots = lots
        self.series = series
        self.history = history
    }
}

public enum PurchaseRule: String, Sendable {
    case r1 = "R1", r2 = "R2", r3 = "R3", r4 = "R4", r5 = "R5", r6 = "R6"
    /// Additional line: glucose/fructose ratio (Spec 14, proposal).
    case ratio = "V1"
}

public struct VerdictReason: Hashable, Sendable {
    public let rule: PurchaseRule
    /// German text with the numbers already inserted (no locale formatters; decimal comma).
    public let text: String
    /// The numbers behind the text for the UI (keys are stable identifiers).
    public let values: [String: Double]
}

public enum PurchaseVerdict: Hashable, Sendable {
    case buy
    case buyPartially(quantity: Int)
    case dontBuy
    case notAssessable
}

public struct PurchaseAssessment: Hashable, Sendable {
    public let verdict: PurchaseVerdict
    public let reasons: [VerdictReason]
    /// Always shown when the offer has a price (AC-K3).
    public let offerPricePer100gCarbs: Double?
    public let shortfallG: Double?
    public let referencePricePer100gCarbs: Double?
    /// Negative = cheaper than the reference median (AC-K4).
    public let percentVersusReference: Double?
}

enum NumberText {
    /// Decimal comma, fixed decimals, half away from zero. No Foundation formatter.
    static func de(_ x: Double, _ decimals: Int = 0) -> String {
        var f = 1.0
        for _ in 0..<decimals { f *= 10 }
        let scaled = Int((abs(x) * f).rounded())
        let whole = scaled / Int(f)
        var s = String(whole)
        if decimals > 0 {
            var frac = String(scaled % Int(f))
            while frac.count < decimals { frac = "0" + frac }
            s += "," + frac
        }
        return (x < 0 && scaled != 0) ? "-" + s : s
    }
}

public enum PurchaseAdvisor {
    static let offerLotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Reference EUR per g carbs (4.4): median over own batches of the same product (>= 2 priced), else
    /// of the same category (>= 3), else nil (AC-K4). Batches without price are ignored.
    public static func referencePricePerGram(for product: ProductInfo, history: [PricedBatch],
                                             parameters: PurchaseParameters = PurchaseParameters()) -> Double? {
        func price(_ h: PricedBatch) -> Double? { PriceMetrics.pricePerGramCarbs(batch: h.batch, product: h.product) }
        let own = history.filter { $0.product.id == product.id }.compactMap(price)
        if own.count >= parameters.minOwnPurchases { return median(own) }
        let category = history.filter { $0.product.category == product.category }.compactMap(price)
        if category.count >= parameters.minCategoryPurchases { return median(category) }
        return nil
    }

    public static func assess(offer: PurchaseOffer, context: PurchaseContext,
                              parameters p: PurchaseParameters = PurchaseParameters()) -> PurchaseAssessment {
        let c = offer.product.carbsPerBaseUnit
        let q = max(0, offer.quantity)
        let offerCarbs = Double(q) * c
        let perGram: Double? = offer.totalPriceCents.flatMap { offerCarbs > 0 ? Double($0) / 100 / offerCarbs : nil }
        let per100 = perGram.map { $0 * 100 }
        let ref = referencePricePerGram(for: offer.product, history: context.history, parameters: p)
        let percent: Double? = (perGram != nil && ref != nil && ref! > 0) ? (perGram! / ref! - 1) * 100 : nil

        func priceReasons() -> [VerdictReason] {
            var out: [VerdictReason] = []
            if let per100 {
                var text = "Preis: \(NumberText.de(per100, 2)) € je 100 g Carbs."
                var values = ["pricePer100gCarbs": per100]
                if let percent, let ref {
                    let r100 = ref * 100
                    values["referencePricePer100gCarbs"] = r100
                    values["percentVersusReference"] = percent
                    let rounded = (abs(percent) * 10).rounded() / 10
                    if rounded == 0 {
                        text += " Entspricht deinem Median von \(NumberText.de(r100, 2)) € je 100 g."
                    } else {
                        text += " \(NumberText.de(rounded, 1)) % \(percent < 0 ? "günstiger" : "teurer") als dein Median von \(NumberText.de(r100, 2)) € je 100 g."
                    }
                    if percent > p.priceDeviationPercent {
                        text += " Mehr als \(NumberText.de(p.priceDeviationPercent)) % über deinem Median: nur bei akutem Bedarf."
                    }
                }
                out.append(VerdictReason(rule: .r6, text: text, values: values))
            }
            return out
        }
        func ratioReasons() -> [VerdictReason] {
            guard let offered = offer.product.glucoseFructoseRatio else { return [] }
            let withRatio = context.lots.filter { $0.glucoseFructoseRatio != nil && $0.carbsG > 0 }
            let weight = withRatio.reduce(0) { $0 + $1.carbsG }
            guard weight > 0 else { return [] }
            let stock = withRatio.reduce(0) { $0 + $1.carbsG * $1.glucoseFructoseRatio! } / weight
            let differs = abs(offered - stock) > p.ratioTolerance
            return [VerdictReason(rule: .ratio, text: differs
                ? "Glucose:Fructose 1:\(NumberText.de(offered, 2)) im Angebot, 1:\(NumberText.de(stock, 2)) im Bestand: anderes Verhältnis zum Ausprobieren."
                : "Glucose:Fructose 1:\(NumberText.de(offered, 2)) wie im Bestand (1:\(NumberText.de(stock, 2))).",
                values: ["offerRatio": offered, "stockRatio": stock])]
        }
        func finish(_ v: PurchaseVerdict, _ reasons: [VerdictReason], shortfall: Double?) -> PurchaseAssessment {
            PurchaseAssessment(verdict: v, reasons: reasons + priceReasons() + ratioReasons(), offerPricePer100gCarbs: per100,
                               shortfallG: shortfall, referencePricePer100gCarbs: ref.map { $0 * 100 }, percentVersusReference: percent)
        }

        let h = p.horizonDays
        // R1 Datenlage
        if !context.series.isKnown(forDays: h) {
            let text: String
            let values: [String: Double]
            if let through = context.series.knownThrough {
                text = "Bedarf nur bis \(through.isoString) bekannt (\(context.series.knownDays) von \(h) Tagen Horizont)."
                values = ["knownDays": Double(context.series.knownDays), "horizonDays": Double(h)]
            } else {
                text = "Kein Bedarf bekannt: bitte Sessions oder Wochenvorlage eintragen (Horizont \(h) Tage)."
                values = ["knownDays": 0, "horizonDays": Double(h)]
            }
            return finish(.notAssessable, [VerdictReason(rule: .r1, text: text, values: values)], shortfall: nil)
        }
        guard q > 0, c > 0 else {
            return finish(.dontBuy, [VerdictReason(rule: .r4, text: "Angebotsmenge 0: nichts zu kaufen.", values: ["quantity": 0])], shortfall: nil)
        }

        // R2 Fehlmenge
        let window = Forecast.window(days: h, lots: context.lots, series: context.series, today: context.today)
        let f = window.shortfallG
        var reasons = [VerdictReason(rule: .r2, text: "Bedarf \(NumberText.de(window.demandG)) g, nutzbarer Bestand \(NumberText.de(window.usableStockG)) g in \(h) Tagen: Fehlmenge \(NumberText.de(f)) g Carbs.",
                                     values: ["demandG": window.demandG, "usableStockG": window.usableStockG, "shortfallG": f, "horizonDays": Double(h)])]

        var wanted = q
        if f <= 1e-9 {
            // R3 Gedeckt
            let series = context.series
            let sim = Forecast.simulate(lots: context.lots, series: series, today: context.today)
            let weeks = sim.weeks ?? 0
            let atLeast = sim.end != .stockExhausted ? "mindestens " : ""
            let text = "Bestand deckt ≈ \(atLeast)\(NumberText.de(weeks, 1)) Wochen, Horizont \(NumberText.de(Double(h) / 7, 1)) Wochen: kein Fehlbedarf."
            let values = ["reachWeeks": weeks, "horizonWeeks": Double(h) / 7]
            let bargain = p.bargainRule && percent.map { $0 <= -p.bargainDiscountPercent } == true
            if !bargain {
                reasons.append(VerdictReason(rule: .r3, text: text, values: values))
                return finish(.dontBuy, reasons, shortfall: 0)
            }
            reasons.append(VerdictReason(rule: .r3, text: text + " Schnäppchenregel: Preis \(NumberText.de(-percent!, 1)) % unter deinem Median, Kauf trotzdem möglich.",
                                         values: values.merging(["percentVersusReference": percent!]) { a, _ in a }))
        } else {
            // R4 Bedarf vorhanden
            let qStar = Int((f / c - 1e-9).rounded(.up))
            wanted = min(q, qStar)
            reasons.append(VerdictReason(rule: .r4, text: q <= qStar
                ? "Nützliche Menge \(qStar) Einheiten (Fehlmenge \(NumberText.de(f)) g ÷ \(NumberText.de(c, 1)) g je Einheit); Angebot \(q) Einheiten passt."
                : "Nützliche Menge \(qStar) Einheiten (Fehlmenge \(NumberText.de(f)) g ÷ \(NumberText.de(c, 1)) g je Einheit); Angebot \(q) Einheiten ist mehr als nötig.",
                values: ["usefulQuantity": Double(qStar), "offeredQuantity": Double(q), "carbsPerUnitG": c]))
        }

        // R5 Haltbarkeit des Angebots
        if let expiry = offer.expiryDate {
            func lossG(_ qty: Int) -> Double {
                guard qty > 0 else { return 0 }
                let lot = StockLot(batchID: offerLotID, productID: offer.product.id, expiry: expiry,
                                   carbsG: Double(qty) * c, unitCarbsG: c, glucoseFructoseRatio: offer.product.glucoseFructoseRatio)
                let sim = Forecast.simulate(lots: context.lots + [lot], series: context.series, today: context.today)
                return sim.losses.first { $0.batchID == offerLotID }?.lostCarbsG ?? 0
            }
            func ok(_ qty: Int) -> Bool { lossG(qty) <= p.expiryLossThreshold * Double(qty) * c + 1e-9 }
            let lossWanted = lossG(wanted)
            let share = wanted > 0 ? lossWanted / (Double(wanted) * c) : 0
            var chosen = wanted
            if !ok(wanted) {
                var lo = 0, hi = wanted
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if ok(mid) { lo = mid } else { hi = mid - 1 }
                }
                chosen = lo
            }
            let threshold = p.expiryLossThreshold * 100
            if chosen == wanted {
                reasons.append(VerdictReason(rule: .r5, text: "Haltbarkeit: bis MHD \(expiry.isoString) verfallen ≈ \(NumberText.de(lossWanted)) g (\(NumberText.de(share * 100, 1)) %), Grenze \(NumberText.de(threshold)) %.",
                                             values: ["lossG": lossWanted, "lossPercent": share * 100, "thresholdPercent": threshold]))
            } else {
                reasons.append(VerdictReason(rule: .r5, text: "Haltbarkeit: bei \(wanted) Einheiten verfallen bis MHD \(expiry.isoString) ≈ \(NumberText.de(lossWanted)) g (\(NumberText.de(share * 100, 1)) %), Grenze \(NumberText.de(threshold)) %. Menge auf \(chosen) gesenkt.",
                                             values: ["lossG": lossWanted, "lossPercent": share * 100, "thresholdPercent": threshold, "reducedQuantity": Double(chosen)]))
            }
            wanted = chosen
        }

        let verdict: PurchaseVerdict = wanted <= 0 ? .dontBuy : (wanted == q ? .buy : .buyPartially(quantity: wanted))
        return finish(verdict, reasons, shortfall: f)
    }
}
