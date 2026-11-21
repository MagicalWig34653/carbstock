import Foundation
import Testing
@testable import CarbStockCore

@Suite struct PackListPlannerTests {
    let today = CalendarDay(year: 2026, month: 11, day: 23)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let gel = ProductInfo(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
    let drink = ProductInfo(name: "Drink", category: .drink, baseUnit: .gram, portionAmount: 50, carbsPerPortionG: 40)
    let bar = ProductInfo(name: "Riegel", category: .bar, baseUnit: .piece, carbsPerPortionG: 30)

    func cand(_ p: ProductInfo, _ qty: Int, expiry: CalendarDay? = nil) -> PackCandidate {
        PackCandidate(product: p, batch: BatchInfo(productID: p.id, purchaseDate: today, quantityPurchased: qty, expiryDate: expiry), availableQuantity: qty)
    }
    let shares: [ProductCategory: Double] = [.gel: 50, .drink: 30, .bar: 20]

    /// TV-7 / AC-L1
    @Test func tv7() {
        let plan = PackListPlanner.plan(demandG: 320, shares: shares, candidates: [cand(gel, 50), cand(drink, 1000), cand(bar, 20)])
        #expect(plan.unitsByCategory == [.gel: 6, .drink: 3, .bar: 2])
        #expect(plan.totalCarbsG == 330 && plan.targetCarbsG == 320 && plan.shortfallG == 0)
        // Postenmenge in Basiseinheiten: 3 Portionen Pulver à 50 g = 150 g
        let d = plan.items.first { $0.category == .drink }!
        #expect(d.units == 3 && d.quantity == 150 && d.carbsG == 120)
        #expect(plan.items.first { $0.category == .gel }!.quantity == 6)
        // Reihenfolge der Kategorien stabil
        #expect(plan.items.map(\.category) == [.gel, .drink, .bar])
    }

    @Test func reserveRaisesTarget() {
        let plan = PackListPlanner.plan(demandG: 300, reserve: 0.1, shares: shares, candidates: [cand(gel, 50), cand(drink, 1000), cand(bar, 20)])
        #expect(abs(plan.targetCarbsG - 330) < 1e-9)
        #expect(plan.totalCarbsG >= 330)
    }

    /// AC-L5
    @Test func splitsAcrossBatchesFefo() {
        let early = cand(gel, 4, expiry: today.adding(days: 30))
        let late = cand(gel, 10, expiry: today.adding(days: 300))
        let plan = PackListPlanner.plan(demandG: 200, shares: [.gel: 100], candidates: [late, early])
        #expect(plan.items.map(\.batchID) == [early.batch.id, late.batch.id])
        #expect(plan.items.map(\.units) == [4, 4])
        #expect(plan.totalCarbsG == 200)
    }

    /// AC-L4: fehlende Kategorie wird von anderen übernommen
    @Test func redistributesWhenCategoryEmpty() {
        let plan = PackListPlanner.plan(demandG: 320, shares: shares, candidates: [cand(gel, 4), cand(bar, 50)])
        #expect(plan.shortfallG == 0)
        #expect(plan.unitsByCategory[.gel] == 4)
        #expect(plan.unitsByCategory[.drink] == nil)
        #expect(plan.totalCarbsG >= 320 && plan.totalCarbsG < 350)
    }

    @Test func shortfallWhenStockInsufficient() {
        let plan = PackListPlanner.plan(demandG: 320, shares: shares, candidates: [cand(gel, 4), cand(bar, 2)])
        #expect(plan.totalCarbsG == 160 && plan.shortfallG == 160)
        // Bestand 0 / keine Kandidaten
        let none = PackListPlanner.plan(demandG: 320, shares: shares, candidates: [])
        #expect(none.items.isEmpty && none.shortfallG == 320)
    }

    @Test func noSharesUsesFefoAcrossCategories() {
        let g = cand(gel, 10, expiry: today.adding(days: 20))
        let b = cand(bar, 10, expiry: today.adding(days: 10))
        let n = cand(drink, 1000) // ohne MHD zuletzt
        let plan = PackListPlanner.plan(demandG: 100, candidates: [n, g, b])
        // Riegel zuerst (früheres MHD): 4 Riegel = 120 g
        #expect(plan.items.count == 1 && plan.items[0].category == .bar && plan.items[0].units == 4)
        let big = PackListPlanner.plan(demandG: 400, candidates: [n, g, b])
        #expect(big.unitsByCategory[.bar] == 10 && big.unitsByCategory[.gel] == 4 && big.shortfallG == 0)
    }

    @Test func zeroDemandGivesEmptyPlan() {
        let plan = PackListPlanner.plan(demandG: 0, shares: shares, candidates: [cand(gel, 5)])
        #expect(plan.items.isEmpty && plan.shortfallG == 0 && plan.totalCarbsG == 0)
    }

    @Test func candidatesFromLedgerSkipExpiredEmptyAndNegative() {
        let ok = BatchInfo(productID: gel.id, purchaseDate: today, quantityPurchased: 5, expiryDate: today) // MHD-Tag zählt noch
        let expired = BatchInfo(productID: gel.id, purchaseDate: today, quantityPurchased: 5, expiryDate: today.adding(days: -1))
        let used = BatchInfo(productID: gel.id, purchaseDate: today, quantityPurchased: 5, expiryDate: today.adding(days: -1), useDespiteExpiry: true)
        let negative = BatchInfo(productID: gel.id, purchaseDate: today, quantityPurchased: 1)
        let ledger = Ledger([ok, expired, used].map { Movement(batchID: $0.id, type: .purchase, delta: 5, occurredAt: t0) }
                            + [Movement(batchID: negative.id, type: .consume, delta: -1, occurredAt: t0)])
        let c = PackListPlanner.candidates(products: [gel], batches: [ok, expired, used, negative], ledger: ledger, today: today)
        #expect(c.map(\.batch.id) == [used.id, ok.id])
        #expect(c.allSatisfy { $0.availableQuantity == 5 })
    }

    @Test func pieceBasedPortionsFloorStock() {
        // 120 g Pulver = 2 Portionen à 50 g (Rest 20 g nicht packbar)
        let plan = PackListPlanner.plan(demandG: 200, shares: [.drink: 1], candidates: [cand(drink, 120)])
        #expect(plan.unitsByCategory[.drink] == 2 && plan.items[0].quantity == 100 && plan.shortfallG == 120)
    }
}
