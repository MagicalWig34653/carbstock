import CarbStockCore
import Foundation
import SwiftData

/// Sicherung, Import, Zusammenführen doppelter Produkte und "Alle Daten löschen" (Spec 9.6, AC-S4, AC-S7, AC-D3).
@MainActor
final class BackupService {
    enum Failure: Error, Equatable {
        case notABackup
        case newerVersion(Int)
        case brokenReferences(Int)
        case cannotMerge
    }

    struct ImportResult: Equatable {
        var products = 0, batches = 0, movements = 0, sessions = 0, template = 0, rates = 0
        var shoppingItems = 0, purchaseEvaluations = 0, packLists = 0
        var total: Int { products + batches + movements + sessions + template + rates + shoppingItems + purchaseEvaluations + packLists }
    }

    private let context: ModelContext
    private let defaults: UserDefaults
    private let now: () -> Date

    init(context: ModelContext, defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date.now }) {
        self.defaults = defaults
        self.context = context
        self.now = now
    }

    // MARK: Export

    func document() -> BackupDocument {
        let products = fetchAll(Product.self)
        let batches = products.flatMap { $0.batches ?? [] }
        let movements = fetchAll(StockMovement.self).compactMap(\.info)
        let training = TrainingService(context: context)
        let sessions = training.sessions()
        var times: [UUID: BackupRecordTimes] = [:]
        for p in products { times[p.id] = BackupRecordTimes(createdAt: p.createdAt, updatedAt: p.updatedAt) }
        for b in batches { times[b.id] = BackupRecordTimes(createdAt: b.createdAt, updatedAt: b.updatedAt) }
        for s in sessions { times[s.id] = BackupRecordTimes(createdAt: s.createdAt) }
        let rates = training.userRates()
        // Same rule as `userRates`: the youngest record of a type counts.
        var rateTimes: [SessionType: Date] = [:]
        for r in fetchAll(CarbRateOverride.self) {
            guard let type = SessionType(rawValue: r.typeRaw), rates[type] != nil else { continue }
            rateTimes[type] = max(rateTimes[type] ?? r.updatedAt, r.updatedAt)
        }
        // Sorted by ID so that the same data gives the same file.
        func byID<T>(_ records: [T], _ id: KeyPath<T, UUID>) -> [T] {
            records.sorted { $0[keyPath: id].uuidString < $1[keyPath: id].uuidString }
        }
        let shopping = byID(fetchAll(ShoppingListItem.self), \.id).map {
            BackupShoppingItem(id: $0.id, productID: $0.productID, freeText: $0.freeText, plannedQuantity: $0.plannedQuantity,
                               estimatedTotalPriceCents: $0.estimatedTotalPriceCents, state: $0.stateRaw, createdAt: $0.createdAt,
                               expiryDay: $0.expiryDay, offerJSON: $0.offerJSON, batchID: $0.batchID)
        }
        let evaluations = byID(fetchAll(PurchaseEvaluation.self), \.id).map {
            BackupPurchaseEvaluation(id: $0.id, verdict: $0.verdictRaw, verdictQuantity: $0.verdictQuantity,
                                     userDecision: $0.userDecisionRaw, createdAt: $0.createdAt,
                                     inputJSON: $0.inputJSON, reasonsJSON: $0.reasonsJSON)
        }
        let packLists = byID(fetchAll(PackList.self), \.id).map { list in
            BackupPackList(id: list.id, sessionID: list.sessionID, title: list.title, targetCarbsG: list.targetCarbsG,
                           reservePercent: list.reservePercent, state: list.stateRaw, createdAt: list.createdAt,
                           items: byID(list.items ?? [], \.id).map {
                               BackupPackItem(id: $0.id, productID: $0.productID, batchID: $0.batchID,
                                              plannedQuantity: $0.plannedQuantity, plannedCarbsG: $0.plannedCarbsG)
                           })
        }
        return BackupDocument(exportedAt: now(), products: products.map(\.info), batches: batches.compactMap(\.info),
                              movements: movements, sessions: sessions.compactMap(\.info),
                              template: training.templateRecords().compactMap(\.info), carbRates: rates,
                              shoppingItems: shopping, purchaseEvaluations: evaluations, packLists: packLists,
                              recordTimes: times, carbRateTimes: rateTimes)
    }

    func exportData() throws -> Data { try document().encoded() }

    // MARK: Import (idempotent by ID)

    enum Preview: Equatable { case invalid(Failure), ok(newItems: Int) }

    func preview(_ data: Data) -> Preview {
        do {
            let doc = try decode(data)
            return .ok(newItems: plan(for: doc).total)
        } catch let f as Failure {
            return .invalid(f)
        } catch { return .invalid(.notABackup) }
    }

    @discardableResult
    func importBackup(_ data: Data) throws -> ImportResult {
        let doc = try decode(data)
        let plan = plan(for: doc)

        var products = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Product>())) ?? []).map { ($0.id, $0) })
        for p in doc.products where products[p.id] == nil {
            let model = Product(id: p.id, name: p.name, brand: p.brand, flavor: p.flavor, category: p.category, baseUnit: p.baseUnit,
                                portionAmount: p.portionAmount, carbsPerPortionG: p.carbsPerPortionG,
                                glucoseFructoseRatio: p.glucoseFructoseRatio,
                                hasCaffeine: p.hasCaffeine, hasLactate: p.hasLactate)
            model.isArchived = p.isArchived
            if let t = doc.recordTimes[p.id] {
                model.createdAt = t.createdAt
                model.updatedAt = t.updatedAt ?? t.createdAt
            }
            context.insert(model)
            products[p.id] = model
        }
        var batches = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Batch>())) ?? []).map { ($0.id, $0) })
        for b in doc.batches where batches[b.id] == nil {
            guard let product = products[b.productID] else { continue }
            let model = Batch(id: b.id, product: product, purchaseDay: b.purchaseDate, quantityPurchased: b.quantityPurchased,
                              totalPriceCents: b.totalPriceCents, expiryDay: b.expiryDate, source: b.source)
            model.currency = b.currency
            model.useDespiteExpiry = b.useDespiteExpiry
            model.isArchived = b.isArchived
            if let t = doc.recordTimes[b.id] {
                model.createdAt = t.createdAt
                model.updatedAt = t.updatedAt ?? t.createdAt
            }
            context.insert(model)
            batches[b.id] = model
        }
        let knownMovements = Set(((try? context.fetch(FetchDescriptor<StockMovement>())) ?? []).map(\.id))
        for m in doc.movements where !knownMovements.contains(m.id) {
            guard let batch = batches[m.batchID] else { continue }
            let model = StockMovement(id: m.id, batch: batch, type: m.type, delta: m.delta, occurredAt: m.occurredAt,
                                      idempotencyKey: m.idempotencyKey, reversesMovementID: m.reversesMovementID,
                                      referenceID: m.referenceID, note: m.note)
            model.createdAt = m.createdAt
            context.insert(model)
        }
        for s in plan.sessions {
            let model = TrainingSession(day: s.day, type: s.type, durationMinutes: s.durationMinutes,
                                        carbsPerHourOverride: s.carbsPerHourOverride)
            model.id = s.id
            model.statusRaw = s.status.rawValue
            model.sourceRaw = "import"
            model.title = s.title
            model.note = s.note
            model.startTime = s.startTime
            if let t = doc.recordTimes[s.id] { model.createdAt = t.createdAt }
            context.insert(model)
        }
        for t in plan.template {
            let model = WeeklyTemplateRecord(weekdayIndex: t.weekdayIndex, type: t.type, durationMinutes: t.durationMinutes,
                                             validFrom: t.validFrom)
            model.id = t.id
            model.carbsPerHourOverride = t.carbsPerHourOverride
            model.validUntil = t.validUntil?.isoString
            context.insert(model)
        }
        // Rates: only fill gaps; the user's current values win over a backup.
        let training = TrainingService(context: context)
        let current = training.userRates()
        var rates = 0
        for (type, value) in doc.carbRates where current[type] == nil && TrainingLimits.carbsPerHour.contains(value) {
            context.insert(CarbRateOverride(type: type, carbsPerHour: value, updatedAt: doc.carbRateTimes[type] ?? now()))
            rates += 1
        }
        // Lists point at products, batches and sessions by ID only; a target deleted before the export may be missing.
        for s in plan.shoppingItems {
            let model = ShoppingListItem(productID: s.productID, freeText: s.freeText, plannedQuantity: s.plannedQuantity,
                                         estimatedTotalPriceCents: s.estimatedTotalPriceCents)
            model.id = s.id
            model.stateRaw = s.state
            model.createdAt = s.createdAt
            model.expiryDay = s.expiryDay
            model.offerJSON = s.offerJSON
            model.batchID = s.batchID
            context.insert(model)
        }
        for e in plan.purchaseEvaluations {
            let model = PurchaseEvaluation(verdictRaw: e.verdict, inputJSON: e.inputJSON, reasonsJSON: e.reasonsJSON)
            model.id = e.id
            model.verdictQuantity = e.verdictQuantity
            model.userDecisionRaw = e.userDecision
            model.createdAt = e.createdAt
            context.insert(model)
        }
        // A known list is left as it is, items included: it may have been recalculated since the export.
        for l in plan.packLists {
            let list = PackList(title: l.title, targetCarbsG: l.targetCarbsG, reservePercent: l.reservePercent, sessionID: l.sessionID)
            list.id = l.id
            list.stateRaw = l.state
            list.createdAt = l.createdAt
            context.insert(list)
            for i in l.items {
                let item = PackListItem(productID: UUID(), batchID: UUID(), plannedQuantity: i.plannedQuantity, plannedCarbsG: i.plannedCarbsG)
                item.id = i.id
                item.productID = i.productID
                item.batchID = i.batchID
                item.packList = list
                context.insert(item)
            }
        }
        try context.save()
        return ImportResult(products: plan.products.count, batches: plan.batches.count, movements: plan.movements.count,
                            sessions: plan.sessions.count, template: plan.template.count, rates: rates,
                            shoppingItems: plan.shoppingItems.count, purchaseEvaluations: plan.purchaseEvaluations.count,
                            packLists: plan.packLists.count)
    }

    private func decode(_ data: Data) throws -> BackupDocument {
        let doc: BackupDocument
        do { doc = try BackupDocument.decode(data) } catch BackupDocument.DecodeFailure.newerVersion(let v) {
            throw Failure.newerVersion(v)
        } catch { throw Failure.notABackup }
        // References into already known local data are fine; only references to nowhere are broken.
        let knownProducts = Set(((try? context.fetch(FetchDescriptor<Product>())) ?? []).map(\.id))
        let knownBatches = Set(((try? context.fetch(FetchDescriptor<Batch>())) ?? []).map(\.id))
        let productIDs = knownProducts.union(doc.products.map(\.id)), batchIDs = knownBatches.union(doc.batches.map(\.id))
        let broken = doc.batches.filter { !productIDs.contains($0.productID) }.count
            + doc.movements.filter { !batchIDs.contains($0.batchID) }.count
        if broken > 0 { throw Failure.brokenReferences(broken) }
        return doc
    }

    private func fetchAll<T: PersistentModel>(_: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func plan(for doc: BackupDocument) -> BackupDocument.ImportPlan {
        func ids<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, UUID>) -> Set<UUID> {
            Set(fetchAll(type).map { $0[keyPath: id] })
        }
        return doc.importPlan(knownProducts: ids(Product.self, \.id), knownBatches: ids(Batch.self, \.id),
                              knownMovements: ids(StockMovement.self, \.id), knownSessions: ids(TrainingSession.self, \.id),
                              knownTemplate: ids(WeeklyTemplateRecord.self, \.id),
                              knownShoppingItems: ids(ShoppingListItem.self, \.id),
                              knownEvaluations: ids(PurchaseEvaluation.self, \.id), knownPackLists: ids(PackList.self, \.id))
    }

    // MARK: Merge duplicates (AC-S4)

    func duplicateGroups() -> [[Product]] {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return DuplicateProducts.groups(in: products.map(\.info)).map { $0.compactMap { byID[$0.id] } }
    }

    /// Moves all batches of `source` to `target` and archives `source`. Bookings stay untouched (they hang on batches).
    /// Packing lists and the shopping list point at products by UUID, so they are re-pointed too.
    func merge(_ source: Product, into target: Product) throws {
        guard DuplicateProducts.canMerge(source.info, into: target.info) else { throw Failure.cannotMerge }
        for batch in source.batches ?? [] {
            batch.product = target
            batch.updatedAt = now()
        }
        for item in (try? context.fetch(FetchDescriptor<PackListItem>())) ?? [] where item.productID == source.id {
            item.productID = target.id
        }
        for item in (try? context.fetch(FetchDescriptor<ShoppingListItem>())) ?? [] where item.productID == source.id {
            item.productID = target.id
        }
        source.isArchived = true
        source.updatedAt = now()
        target.updatedAt = now()
        try context.save()
    }

    // MARK: Delete everything (AC-D3)

    /// Deletes every record of all stores. With CloudKit mirroring the deletions are propagated to the private database.
    func deleteAllData() throws {
        // Children first so nothing depends on a cascade that has not run yet.
        try context.delete(model: StockMovement.self)
        try context.delete(model: Batch.self)
        try context.delete(model: Product.self)
        try context.delete(model: ShoppingListItem.self)
        try context.delete(model: PurchaseEvaluation.self)
        try context.delete(model: PackListItem.self)
        try context.delete(model: PackList.self)
        try context.delete(model: TrainingSession.self)
        try context.delete(model: WeeklyTemplateRecord.self)
        try context.delete(model: CarbRateOverride.self)
        // Imported workouts (Imports store) are local copies of Health data: they go too (AC-X6, AC-D3).
        try context.delete(model: ImportedActivity.self)
        try context.delete(model: ActivityPairDecision.self)
        try context.save()
        // Without this, opening "Fahrten" would read Health again on its own and bring the rides back.
        defaults.removeObject(forKey: ActivityService.connectedKey)
    }
}

extension BackupDocument.ImportPlan {
    /// Number of records an import would add.
    var total: Int {
        products.count + batches.count + movements.count + sessions.count + template.count
            + shoppingItems.count + purchaseEvaluations.count + packLists.count
    }
}
