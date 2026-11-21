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
        var total: Int { products + batches + movements + sessions + template + rates }
    }

    private let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = { Date.now }) {
        self.context = context
        self.now = now
    }

    // MARK: Export

    func document() -> BackupDocument {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let batches = products.flatMap { $0.batches ?? [] }
        let movements = ((try? context.fetch(FetchDescriptor<StockMovement>())) ?? []).compactMap(\.info)
        let training = TrainingService(context: context)
        return BackupDocument(exportedAt: now(), products: products.map(\.info), batches: batches.compactMap(\.info),
                              movements: movements, sessions: training.sessions().compactMap(\.info),
                              template: training.templateRecords().compactMap(\.info), carbRates: training.userRates())
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
            let model = Product(id: p.id, name: p.name, brand: p.brand, category: p.category, baseUnit: p.baseUnit,
                                portionAmount: p.portionAmount, carbsPerPortionG: p.carbsPerPortionG,
                                glucoseFructoseRatio: p.glucoseFructoseRatio)
            model.isArchived = p.isArchived
            context.insert(model)
            products[p.id] = model
        }
        var batches = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Batch>())) ?? []).map { ($0.id, $0) })
        for b in doc.batches where batches[b.id] == nil {
            guard let product = products[b.productID] else { continue }
            let model = Batch(id: b.id, product: product, purchaseDay: b.purchaseDate, quantityPurchased: b.quantityPurchased,
                              totalPriceCents: b.totalPriceCents, expiryDay: b.expiryDate)
            model.currency = b.currency
            model.useDespiteExpiry = b.useDespiteExpiry
            model.isArchived = b.isArchived
            context.insert(model)
            batches[b.id] = model
        }
        let knownMovements = Set(((try? context.fetch(FetchDescriptor<StockMovement>())) ?? []).map(\.id))
        for m in doc.movements where !knownMovements.contains(m.id) {
            guard let batch = batches[m.batchID] else { continue }
            let model = StockMovement(id: m.id, batch: batch, type: m.type, delta: m.delta, occurredAt: m.occurredAt,
                                      idempotencyKey: m.idempotencyKey, reversesMovementID: m.reversesMovementID,
                                      referenceID: m.referenceID)
            model.createdAt = m.createdAt
            context.insert(model)
        }
        for s in plan.sessions {
            let model = TrainingSession(day: s.day, type: s.type, durationMinutes: s.durationMinutes,
                                        carbsPerHourOverride: s.carbsPerHourOverride)
            model.id = s.id
            model.statusRaw = s.status.rawValue
            model.sourceRaw = "import"
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
            context.insert(CarbRateOverride(type: type, carbsPerHour: value))
            rates += 1
        }
        try context.save()
        return ImportResult(products: plan.products.count, batches: plan.batches.count, movements: plan.movements.count,
                            sessions: plan.sessions.count, template: plan.template.count, rates: rates)
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

    private func plan(for doc: BackupDocument) -> BackupDocument.ImportPlan {
        func ids<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, UUID>) -> Set<UUID> {
            Set(((try? context.fetch(FetchDescriptor<T>())) ?? []).map { $0[keyPath: id] })
        }
        return doc.importPlan(knownProducts: ids(Product.self, \.id), knownBatches: ids(Batch.self, \.id),
                              knownMovements: ids(StockMovement.self, \.id), knownSessions: ids(TrainingSession.self, \.id),
                              knownTemplate: ids(WeeklyTemplateRecord.self, \.id))
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

    /// Deletes every record of both stores. With CloudKit mirroring the deletions are propagated to the private database.
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
        try context.save()
    }
}

extension BackupDocument.ImportPlan {
    /// Number of records an import would add.
    var total: Int { products.count + batches.count + movements.count + sessions.count + template.count }
}
