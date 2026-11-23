import CarbStockCore
import Foundation
import SwiftData

/// Kauf-Entscheider, Einkaufsliste und Verlauf (Spec 4.4, 5.7, 7.3).
///
/// Bewerten ist reine Lesearbeit (AC-K5): `assess` schreibt nichts. Erst „Gekauft“ legt über den
/// `InventoryService` Charge + Kaufbuchung an. Der Verlauf (`PurchaseEvaluation`) entsteht nur nach
/// ausdrücklichem Sichern oder bei „Gekauft“/„Verworfen“; `userDecision` setzt nur der Nutzer.
@MainActor
final class PurchaseService {
    enum Failure: Error, Equatable {
        case invalidOffer([OfferDraft.Problem])
        case invalidBought([BoughtDraft.Problem])
        case invalidEntry([ShoppingEntryDraft.Problem])
        case productNotFound
        /// Nur Urteile „kaufen“ und „teilweise kaufen“ lassen sich auf die Liste setzen.
        case notBuyable
        /// Eintrag ist schon gekauft oder verworfen.
        case itemClosed
    }

    /// Ergebnis einer Bewertung samt allem, was zum Sichern, Listen und Kaufen nötig ist.
    struct Assessed: Equatable, Sendable {
        /// Stabil für diese Bewertung: wiederholtes Sichern aktualisiert denselben Verlaufseintrag.
        let id: UUID
        let product: ProductInfo
        let offer: PurchaseOffer
        let price: OfferPrice?
        let assessment: PurchaseAssessment
        let saved: SavedOffer
        let outcome: PurchaseOutcome

        /// Menge, die das Urteil empfiehlt (nil bei „nicht kaufen“/„nicht beurteilbar“).
        var recommendedQuantity: Int? {
            switch assessment.verdict {
            case .buy: offer.quantity
            case .buyPartially(let n): n
            case .dontBuy, .notAssessable: nil
            }
        }

        /// Preis für die empfohlene Menge: bei „teilweise kaufen“ anteilig (geschätzt, Versand und Rabatt mitgerechnet).
        var recommendedTotalPriceCents: Int? {
            guard let quantity = recommendedQuantity, let total = saved.offer.totalPriceCents else { return nil }
            let offered = saved.offer.quantity
            return quantity == offered ? total : Int((Double(total) * Double(quantity) / Double(offered)).rounded())
        }

        /// Vorbelegung von „Gekauft“: empfohlene Menge, anteiliger Preis, MHD des Angebots.
        func boughtDraft(existingProductID: UUID?) -> BoughtDraft {
            BoughtDraft(offer: saved.offer, existingProductID: existingProductID,
                        quantity: recommendedQuantity ?? saved.offer.quantity, totalPriceCents: recommendedTotalPriceCents)
        }
    }

    private let context: ModelContext
    private let today: () -> CalendarDay
    private let now: () -> Date

    init(context: ModelContext,
         today: @escaping () -> CalendarDay = { CalendarDay(Date.now, in: .current) },
         now: @escaping () -> Date = { Date.now }) {
        self.context = context
        self.today = today
        self.now = now
    }

    private var inventory: InventoryService { InventoryService(context: context, today: today, now: now) }
    private var training: TrainingService { TrainingService(context: context, today: today) }

    // MARK: Bewerten (liest nur)

    func products() -> [Product] {
        let all = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        return all.filter { !$0.isArchived }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func product(id: UUID) -> Product? {
        ((try? context.fetch(FetchDescriptor<Product>())) ?? []).first { $0.id == id }
    }

    /// Urteil des Core (R1–R6) für das Angebot. Ändert nie Bestand, legt nichts an (AC-K5).
    /// Gleiche Eingabe und gleicher Datenstand ergeben dasselbe Ergebnis (AC-K7).
    func assess(_ draft: OfferDraft, id: UUID = UUID()) throws -> Assessed {
        let existing: Product?
        if let pid = draft.existingProductID {
            guard let found = product(id: pid) else { throw Failure.productNotFound }
            existing = found
        } else {
            existing = nil
        }
        let problems = draft.problems(existing: existing?.info)
        guard problems.isEmpty, let info = draft.productInfo(existing: existing?.info), let quantity = draft.quantity else {
            throw Failure.invalidOffer(problems)
        }
        let price = draft.price(unit: info.baseUnit)
        let offer = PurchaseOffer(product: info, quantity: quantity, totalPriceCents: price?.totalCents,
                                  expiryDate: draft.expiry)
        let (products, batches) = training.inventorySnapshot()
        let lots = StockLot.lots(products: products, batches: batches, ledger: inventory.ledger())
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let history = batches.compactMap { b in byID[b.productID].map { PricedBatch(product: $0, batch: b) } }
        let series = training.report(windows: []).series
        let assessment = PurchaseAdvisor.assess(offer: offer,
            context: PurchaseContext(today: today(), lots: lots, series: series, history: history),
            parameters: draft.parameters)
        let snapshot = OfferSnapshot(
            productID: info.id, isNewProduct: existing == nil, productName: info.name, brand: info.brand, flavor: info.flavor,
            hasCaffeine: info.hasCaffeine, hasLactate: info.hasLactate,
            categoryRaw: info.category.rawValue, baseUnitRaw: info.baseUnit.rawValue,
            portionAmount: info.portionAmount, carbsPerPortionG: info.carbsPerPortionG,
            glucoseFructoseRatio: info.glucoseFructoseRatio, quantity: quantity,
            totalPriceCents: price?.totalCents, shippingCents: price?.shippingCents, discountCents: price?.discountCents,
            expiryDay: draft.expiry?.isoString, horizonDays: draft.horizonDays, bargainRule: draft.bargainRule)
        let saved = SavedOffer(offer: snapshot, assessment: AssessmentSnapshot(assessment))
        return Assessed(id: id, product: info, offer: offer, price: price, assessment: assessment, saved: saved,
                      outcome: PurchaseOutcome(saved.assessment, unit: info.baseUnit, offeredQuantity: quantity))
    }

    // MARK: Verlauf (PurchaseEvaluation)

    func evaluations() -> [PurchaseEvaluation] {
        ((try? context.fetch(FetchDescriptor<PurchaseEvaluation>())) ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Sichert die Bewertung als Snapshot. Dieselbe `id` aktualisiert den vorhandenen Eintrag (nur die Entscheidung).
    @discardableResult
    func saveEvaluation(_ saved: SavedOffer, id: UUID, decision: UserDecision = .none) throws -> PurchaseEvaluation {
        if let existing = evaluations().first(where: { $0.id == id }) {
            existing.userDecisionRaw = decision.rawValue
            try context.save()
            return existing
        }
        let e = PurchaseEvaluation(verdictRaw: saved.assessment.verdictRaw,
                                   inputJSON: try? JSONEncoder().encode(saved.offer),
                                   reasonsJSON: try? JSONEncoder().encode(saved.assessment.reasons))
        e.id = id
        e.verdictQuantity = saved.assessment.verdictQuantity
        e.userDecisionRaw = decision.rawValue
        e.createdAt = now()
        context.insert(e)
        try context.save()
        return e
    }

    @discardableResult
    func saveEvaluation(_ result: Assessed, decision: UserDecision = .none) throws -> PurchaseEvaluation {
        try saveEvaluation(result.saved, id: result.id, decision: decision)
    }

    /// „Verworfen“ direkt aus dem Entscheider: Verlaufseintrag mit Entscheidung „nicht gekauft“.
    @discardableResult
    func skip(_ result: Assessed) throws -> PurchaseEvaluation { try saveEvaluation(result, decision: .skipped) }

    /// Nutzer merkt einen gesicherten, noch offenen Verlaufseintrag als „nicht gekauft“. „Gekauft“ gibt es nur über
    /// den Gekauft-Fluss, damit Verlauf und Bestand nicht auseinanderlaufen.
    func markSkipped(_ evaluation: PurchaseEvaluation) throws {
        guard evaluation.userDecision == .none else { return }
        evaluation.userDecisionRaw = UserDecision.skipped.rawValue
        try context.save()
    }

    func remove(_ evaluation: PurchaseEvaluation) throws {
        context.delete(evaluation)
        try context.save()
    }

    // MARK: Einkaufsliste

    func items() -> [ShoppingListItem] {
        ((try? context.fetch(FetchDescriptor<ShoppingListItem>())) ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Eintrag aus einem Urteil „kaufen“/„teilweise kaufen“ (Spec 4.4). Menge = empfohlene Menge, Preis anteilig geschätzt.
    @discardableResult
    func addToList(_ result: Assessed) throws -> ShoppingListItem {
        guard let quantity = result.recommendedQuantity, quantity > 0 else { throw Failure.notBuyable }
        let o = result.saved.offer
        let item = ShoppingListItem(productID: o.isNewProduct ? nil : o.productID, freeText: o.productName,
                                    plannedQuantity: quantity, estimatedTotalPriceCents: result.recommendedTotalPriceCents)
        item.expiryDay = o.expiryDay
        item.offerJSON = try? JSONEncoder().encode(result.saved)
        item.createdAt = now()
        context.insert(item)
        try context.save()
        return item
    }

    @discardableResult
    func addManually(_ draft: ShoppingEntryDraft) throws -> ShoppingListItem {
        let problems = draft.problems
        guard problems.isEmpty, let quantity = draft.quantity else { throw Failure.invalidEntry(problems) }
        if let pid = draft.productID, product(id: pid) == nil { throw Failure.productNotFound }
        let item = ShoppingListItem(productID: draft.productID, freeText: draft.productID == nil ? draft.trimmedText : nil,
                                    plannedQuantity: quantity, estimatedTotalPriceCents: draft.estimatedCents)
        item.createdAt = now()
        context.insert(item)
        try context.save()
        return item
    }

    /// „Verwerfen“: Eintrag wird `dropped`. Stammt er aus einem Urteil, entsteht der Verlaufseintrag „nicht gekauft“.
    func drop(_ item: ShoppingListItem) throws {
        guard item.state == .open else { throw Failure.itemClosed }
        item.stateRaw = ShoppingItemState.dropped.rawValue
        if let saved = item.savedOffer { try saveEvaluation(saved, id: item.id, decision: .skipped) } else { try context.save() }
    }

    /// Reiner Löschvorgang eines offenen manuellen oder erledigten Eintrags (kein Bestand betroffen).
    func remove(_ item: ShoppingListItem) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: Gekauft → Charge + Kaufbuchung

    /// „Gekauft“ für einen Listeneintrag nach Bestätigung. Genau einmal: ein zweiter Aufruf wirft `itemClosed`
    /// und bucht nichts. Das Urteil selbst hat nie gebucht; hier entstehen Charge und `purchase`-Buchung.
    @discardableResult
    func markBought(_ item: ShoppingListItem, with draft: BoughtDraft) throws -> Batch {
        guard item.state == .open else { throw Failure.itemClosed }
        let batch = try book(draft)
        item.stateRaw = ShoppingItemState.bought.rawValue
        item.batchID = batch.id
        if let saved = item.savedOffer { try saveEvaluation(saved, id: item.id, decision: .bought) } else { try context.save() }
        return batch
    }

    /// „Gekauft“ direkt aus dem Entscheider (ohne Umweg über die Liste); der Verlauf bekommt „gekauft“.
    @discardableResult
    func markBought(_ result: Assessed, with draft: BoughtDraft) throws -> Batch {
        let batch = try book(draft)
        try saveEvaluation(result, decision: .bought)
        return batch
    }

    private func book(_ draft: BoughtDraft) throws -> Batch {
        let problems = draft.problems
        guard problems.isEmpty else { throw Failure.invalidBought(problems) }
        if let pid = draft.productID {
            guard let product = product(id: pid) else { throw Failure.productNotFound }
            return try inventory.addBatch(to: product, quantity: draft.quantity, totalPriceCents: draft.totalPriceCents,
                                          purchaseDay: draft.purchaseDay, expiry: draft.expiry, source: "Einkauf")
        }
        let product = try inventory.createProduct(draft.productDraft)
        guard let batch = (product.batches ?? []).first else { throw Failure.productNotFound }
        return batch
    }
}
