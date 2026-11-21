import CarbStockCore
import Foundation
import SwiftData

/// Eingaben für eine neue Packliste (Spec 4.5, O-10).
struct PackListDraft: Equatable, Sendable {
    enum Problem: Error, Equatable, Sendable { case titleEmpty, targetNotPositive, reserveOutOfRange, sharesEmpty }

    var title: String = ""
    var sessionID: UUID?
    /// Demand of the session or the free target in g carbs (before the reserve).
    var demandG: Double = 0
    var reservePercent: Int = 10
    /// Category shares in percent; empty = distribute by stock (FEFO over all categories).
    var sharesPercent: [ProductCategory: Int] = [:]
    var useShares = false

    var problems: [Problem] {
        var p: [Problem] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty { p.append(.titleEmpty) }
        if demandG <= 0 { p.append(.targetNotPositive) }
        if !(0...100).contains(reservePercent) { p.append(.reserveOutOfRange) }
        if useShares && sharesPercent.values.allSatisfy({ $0 <= 0 }) { p.append(.sharesEmpty) }
        return p
    }

    var targetG: Double { demandG * (1 + Double(reservePercent) / 100) }
    var effectiveShares: [ProductCategory: Double] {
        useShares ? sharesPercent.filter { $0.value > 0 }.mapValues(Double.init) : [:]
    }
}

/// Reine Ableitung des Anzeigezustands eines Postens (aus Buchungen, nie gespeichert, Spec 5.6).
struct PackItemState: Equatable, Sendable {
    var plannedQuantity: Int
    var packedQuantity: Int
    var returnedQuantity: Int
    var isPacked: Bool { packedQuantity > 0 }
    var netConsumed: Int { packedQuantity - returnedQuantity }
    /// How much may still be put back.
    var returnable: Int { max(0, packedQuantity - returnedQuantity) }
}

/// Packlisten: planen, abhaken (pack), Haken entfernen (reversal), Rest zurücklegen (return). Die Packliste
/// liegt im lokalen Training-Speicher, die Buchungen im Inventar-Speicher; verbunden nur über UUIDs (9.2.3).
@MainActor
final class PackService {
    enum Failure: Error, Equatable {
        case invalid([PackListDraft.Problem])
        case listFinished
        case batchMissing
        case insufficientStock(shortfall: Int)
        case nothingToReturn
        case returnTooMuch
        /// An open list with ticked items cannot be deleted: remove the ticks first, otherwise the stock stays booked out.
        case hasPackedItems
    }

    private let context: ModelContext
    private let today: () -> CalendarDay
    private let now: () -> Date
    private var inventory: InventoryService { InventoryService(context: context, today: today, now: now) }

    init(context: ModelContext,
         today: @escaping () -> CalendarDay = { CalendarDay(Date.now, in: .current) },
         now: @escaping () -> Date = { Date.now }) {
        self.context = context
        self.today = today
        self.now = now
    }

    // MARK: Reading

    func lists() -> [PackList] {
        ((try? context.fetch(FetchDescriptor<PackList>())) ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func items(of list: PackList) -> [PackListItem] {
        (list.items ?? []).sorted { ($0.plannedCarbsG, $0.id.uuidString) > ($1.plannedCarbsG, $1.id.uuidString) }
    }

    func state(of item: PackListItem, ledger: Ledger? = nil) -> PackItemState {
        let l = ledger ?? inventory.ledger()
        return PackItemState(plannedQuantity: item.plannedQuantity, packedQuantity: max(0, l.packedQuantity(itemID: item.id)),
                             returnedQuantity: l.returnedQuantity(itemID: item.id))
    }

    /// Carbs the list misses against its target (AC-L4); 0 if it reaches the target.
    func shortfallG(of list: PackList) -> Double {
        let planned = (list.items ?? []).reduce(0) { $0 + $1.plannedCarbsG }
        return planned + 1e-9 < list.targetCarbsG ? list.targetCarbsG - planned : 0
    }

    // MARK: Planning (7.4)

    func plan(for draft: PackListDraft) -> PackPlan {
        let (products, batches) = TrainingService(context: context, today: today).inventorySnapshot()
        let candidates = PackListPlanner.candidates(products: products, batches: batches, ledger: inventory.ledger(), today: today())
        return PackListPlanner.plan(demandG: draft.demandG, reserve: Double(draft.reservePercent) / 100,
                                    shares: draft.effectiveShares, candidates: candidates)
    }

    @discardableResult
    func create(_ draft: PackListDraft) throws -> PackList {
        guard draft.problems.isEmpty else { throw Failure.invalid(draft.problems) }
        let plan = plan(for: draft)
        let list = PackList(title: draft.title.trimmingCharacters(in: .whitespaces), targetCarbsG: plan.targetCarbsG,
                            reservePercent: draft.reservePercent, sessionID: draft.sessionID)
        context.insert(list)
        fill(list, with: plan)
        try context.save()
        return list
    }

    /// New calculation of a list that is still a draft (stock changed since).
    func recalculate(_ list: PackList, demandG: Double) throws {
        guard list.stateRaw == "draft" else { throw Failure.listFinished }
        for item in list.items ?? [] { context.delete(item) }
        var d = PackListDraft()
        d.title = list.title; d.demandG = demandG; d.reservePercent = list.reservePercent
        let plan = plan(for: d)
        list.targetCarbsG = plan.targetCarbsG
        fill(list, with: plan)
        try context.save()
    }

    private func fill(_ list: PackList, with plan: PackPlan) {
        for p in plan.items {
            let item = PackListItem(productID: p.productID, batchID: p.batchID, plannedQuantity: p.quantity, plannedCarbsG: p.carbsG)
            item.packList = list
            context.insert(item)
        }
    }

    // MARK: Packing (AC-L2, AC-L3)

    /// Sets or removes the tick of an item. Exactly one movement per change; nothing if already in that state.
    @discardableResult
    func setPacked(_ wanted: Bool, item: PackListItem) throws -> StockMovement? {
        guard let list = item.packList, list.stateRaw != "done" else { throw Failure.listFinished }
        let ledger = inventory.ledger()
        switch ledger.nextPackAction(itemID: item.id, wantPacked: wanted) {
        case .none:
            return nil
        case .pack(let key):
            guard let batch = batch(item.batchID) else { throw Failure.batchMissing }
            let available = ledger.quantity(ofBatch: batch.id)
            guard available >= item.plannedQuantity else { throw Failure.insufficientStock(shortfall: item.plannedQuantity - max(0, available)) }
            let m = StockMovement(batch: batch, type: .pack, delta: -item.plannedQuantity, occurredAt: now(),
                                  idempotencyKey: key, referenceID: item.id)
            context.insert(m)
            batch.product?.updatedAt = now()
            if list.stateRaw == "draft" { list.stateRaw = "packing" }
            try context.save()
            return m
        case .reverse(let id):
            guard let original = movement(id) else { throw Failure.batchMissing }
            return try inventory.reverse(original, note: "Haken entfernt")
        }
    }

    // MARK: Put back and finish (AC-L6)

    /// "Rest zurücklegen": `return` booking on the batch of the item, at most what was packed and not yet put back.
    @discardableResult
    func putBack(_ quantity: Int, item: PackListItem) throws -> StockMovement {
        guard let list = item.packList, list.stateRaw != "done" else { throw Failure.listFinished }
        let s = state(of: item)
        guard s.returnable > 0 else { throw Failure.nothingToReturn }
        guard quantity > 0, quantity <= s.returnable else { throw Failure.returnTooMuch }
        guard let batch = batch(item.batchID) else { throw Failure.batchMissing }
        let m = StockMovement(batch: batch, type: .return, delta: quantity, occurredAt: now(), referenceID: item.id, note: "Rest zurückgelegt")
        context.insert(m)
        batch.product?.updatedAt = now()
        try context.save()
        return m
    }

    /// Done lists are read-only; corrections go through normal bookings.
    func finish(_ list: PackList) throws {
        list.stateRaw = "done"
        try context.save()
    }

    func delete(_ list: PackList) throws {
        if list.stateRaw != "done" {
            let ledger = inventory.ledger()
            if (list.items ?? []).contains(where: { ledger.isPacked(itemID: $0.id) }) { throw Failure.hasPackedItems }
        }
        // Bookings stay (they are immutable); only the list disappears.
        context.delete(list)
        try context.save()
    }

    // MARK: Lookups

    private func batch(_ id: UUID?) -> Batch? {
        guard let id else { return nil }
        return (try? context.fetch(FetchDescriptor<Batch>(predicate: #Predicate { $0.id == id })))?.first
    }

    private func movement(_ id: UUID) -> StockMovement? {
        (try? context.fetch(FetchDescriptor<StockMovement>(predicate: #Predicate { $0.id == id })))?.first
    }
}
