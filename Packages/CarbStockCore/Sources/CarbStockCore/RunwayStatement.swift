import Foundation

/// Die Aussage zur Reichweite, die die App anzeigt (Spec 4.3, AC-P3/P4/P5). Reine Logik, damit sie testbar bleibt.
public enum RunwayStatement: Hashable, Sendable {
    /// AC-P4: kein bekannter Bedarf, keine Aussage ("Bedarf unbekannt").
    case unknown
    /// AC-P3: der Bestand endet an einem Tag mit bekanntem Bedarf: "reicht ≈ X Wochen (bis Datum)".
    /// `until` ist der erste Tag ohne volle Deckung (TV-2: heute + 108 Tage).
    case reaches(weeks: Double, until: CalendarDay)
    /// AC-P5: Bestand ist noch da, wenn der bekannte Bedarf endet (oder die Simulation gedeckelt ist).
    /// `until` ist der letzte Tag mit bekanntem Bedarf; darüber hinaus gibt es keine belastbare Aussage.
    case atLeast(until: CalendarDay)

    public init(simulation: SimulationResult, series: DemandSeries) {
        switch simulation.end {
        case .noDemandData:
            self = .unknown
        case .stockExhausted:
            guard let weeks = simulation.weeks, let until = simulation.reachDate else { self = .unknown; return }
            self = .reaches(weeks: weeks, until: until)
        case .demandEnded, .horizonReached:
            guard let through = series.knownThrough else { self = .unknown; return }
            self = .atLeast(until: through)
        }
    }
}

/// Stock carbs by product category (spec 4.3: shown only, the forecast itself works on total carbs, O-19).
public enum StockBreakdown {
    public struct Share: Hashable, Sendable {
        public let category: ProductCategory
        public let carbsG: Double
    }

    /// Non-archived batches with stock > 0, largest share first (ties: category order).
    public static func carbsByCategory(products: [ProductInfo], batches: [BatchInfo], ledger: Ledger) -> [Share] {
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        var sums: [ProductCategory: Double] = [:]
        for b in batches where !b.isArchived {
            guard let p = byID[b.productID] else { continue }
            let q = ledger.quantity(ofBatch: b.id)
            guard q > 0 else { continue }
            sums[p.category, default: 0] += Double(q) * p.carbsPerBaseUnit
        }
        let order = ProductCategory.allCases
        return sums.map { Share(category: $0.key, carbsG: $0.value) }.sorted {
            $0.carbsG != $1.carbsG ? $0.carbsG > $1.carbsG
                : (order.firstIndex(of: $0.category) ?? 0) < (order.firstIndex(of: $1.category) ?? 0)
        }
    }
}
