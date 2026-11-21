import Foundation

// Packlisten-Verfahren (Spec 4.5, 7.4, TV-7).
//
// Einheit eines Postens = eine Portion (`ProductInfo.portionAmount` Basiseinheiten, `carbsPerPortionG` Carbs).
// Bei Stückware ist das 1 Stück, bei Pulver z. B. 50 g Pulver = 1 Portion à 40 g Carbs. Die Postenmenge
// (`PackPlanItem.quantity`) steht dagegen immer in Basiseinheiten, wie die Buchungen: bei Pulver also
// Portionen x portionAmount Gramm. Der Bestand wird in ganze Portionen abgerundet.

/// A batch with stock the planner may draw from.
public struct PackCandidate: Hashable, Sendable {
    public var product: ProductInfo
    public var batch: BatchInfo
    /// Remaining stock in base units (> 0).
    public var availableQuantity: Int

    public init(product: ProductInfo, batch: BatchInfo, availableQuantity: Int) {
        self.product = product
        self.batch = batch
        self.availableQuantity = availableQuantity
    }

    var availableUnits: Int { Int((Double(availableQuantity) / product.portionAmount + 1e-9).rounded(.down)) }
}

public struct PackPlanItem: Hashable, Sendable {
    public let productID: UUID
    public let batchID: UUID
    public let category: ProductCategory
    /// Portions (pieces for piece goods).
    public let units: Int
    /// Base units to book (`units x portionAmount`).
    public let quantity: Int
    public let carbsG: Double
}

public struct PackPlan: Hashable, Sendable {
    public let items: [PackPlanItem]
    /// Demand x (1 + reserve).
    public let targetCarbsG: Double
    public let totalCarbsG: Double
    /// Missing carbs when the stock is not enough (AC-L4); 0 otherwise.
    public let shortfallG: Double
    public var unitsByCategory: [ProductCategory: Int] {
        items.reduce(into: [:]) { $0[$1.category, default: 0] += $1.units }
    }
}

public enum PackListPlanner {
    static let eps = 1e-9

    /// Candidates from the ledger: not archived, stock > 0, expired batches skipped unless `useDespiteExpiry`
    /// (same rule as FEFO booking), FEFO order.
    public static func candidates(products: [ProductInfo], batches: [BatchInfo], ledger: Ledger,
                                  today: CalendarDay) -> [PackCandidate] {
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return batches.sorted(by: BatchInfo.fefoPrecedes).compactMap { b in
            guard !b.isArchived, b.useDespiteExpiry || !b.isExpired(on: today), let p = byID[b.productID] else { return nil }
            let q = ledger.quantity(ofBatch: b.id)
            return q > 0 ? PackCandidate(product: p, batch: b, availableQuantity: q) : nil
        }
    }

    /// Procedure 7.4. `shares` are category weights (e.g. 50/30/20, normalised by their sum); empty = no shares:
    /// then FEFO over all categories. Step 3 rounds half away from zero per lot; fills (step 4) take one unit
    /// at a time from the category with the largest rest and may overshoot the target by less than one unit
    /// (TV-7: 330 g for 320 g). Without shares a unit count is rounded up (reach the target).
    public static func plan(demandG: Double, reserve: Double = 0, shares: [ProductCategory: Double] = [:],
                            candidates input: [PackCandidate]) -> PackPlan {
        let target = max(0, demandG) * (1 + max(0, reserve))
        guard target > eps else { return PackPlan(items: [], targetCarbsG: 0, totalCarbsG: 0, shortfallG: 0) }

        let lots = input.filter { $0.availableUnits > 0 && $0.product.carbsPerPortionG > 0 }
            .sorted { BatchInfo.fefoPrecedes($0.batch, $1.batch) }
        var free = lots.map(\.availableUnits)
        var taken = Array(repeating: 0, count: lots.count)
        var total = 0.0
        func carbs(_ i: Int) -> Double { lots[i].product.carbsPerPortionG }
        func take(_ i: Int, _ n: Int) {
            taken[i] += n; free[i] -= n; total += Double(n) * carbs(i)
        }
        func indices(of c: ProductCategory) -> [Int] { lots.indices.filter { lots[$0].product.category == c } }
        func categoryCarbs(_ c: ProductCategory) -> Double { indices(of: c).reduce(0) { $0 + Double(taken[$1]) * carbs($1) } }

        let positive = shares.filter { $0.value > 0 }
        let sum = positive.values.reduce(0, +)
        var ideal: [ProductCategory: Double] = [:]
        for (c, w) in positive { ideal[c] = w / sum * target }
        let shareCategories = ProductCategory.allCases.filter { ideal[$0] != nil }

        // Steps 2 and 3
        for c in shareCategories {
            var rest = ideal[c]!
            for i in indices(of: c) where rest > eps {
                let n = min(free[i], Int((rest / carbs(i)).rounded(.toNearestOrAwayFromZero)))
                if n > 0 { take(i, n); rest -= Double(n) * carbs(i) }
            }
        }
        // Step 4: fill by largest rest, only where stock exists
        while total + eps < target {
            let best = shareCategories
                .filter { c in indices(of: c).contains { free[$0] > 0 } }
                .max { (ideal[$0]! - categoryCarbs($0)) < (ideal[$1]! - categoryCarbs($1)) }
            guard let c = best, let i = indices(of: c).first(where: { free[$0] > 0 }) else { break }
            take(i, 1)
        }
        // Step 6 / no shares: rest over all categories, FEFO
        while total + eps < target, let i = lots.indices.first(where: { free[$0] > 0 }) {
            take(i, min(free[i], max(1, Int(((target - total) / carbs(i) - 1e-9).rounded(.up)))))
        }

        let order = ProductCategory.allCases
        let items = lots.indices.filter { taken[$0] > 0 }
            .sorted { a, b in
                let (ca, cb) = (order.firstIndex(of: lots[a].product.category)!, order.firstIndex(of: lots[b].product.category)!)
                return ca != cb ? ca < cb : a < b
            }
            .map { i in
                PackPlanItem(productID: lots[i].product.id, batchID: lots[i].batch.id, category: lots[i].product.category,
                             units: taken[i], quantity: Int((Double(taken[i]) * lots[i].product.portionAmount).rounded()),
                             carbsG: Double(taken[i]) * carbs(i))
            }
        return PackPlan(items: items, targetCarbsG: target, totalCarbsG: total, shortfallG: max(0, target - total) > eps ? target - total : 0)
    }
}
