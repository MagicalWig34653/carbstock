import CarbStockCore
import Foundation
import SwiftData

/// All inventory writes (spec 4.1, 5.4, 9.4). Movements are only ever inserted, never edited.
/// Stock is always Σ delta and never stored.
@MainActor
final class InventoryService {
    enum Failure: Error, Equatable {
        case invalid([ProductDraft.Problem])
        case quantityNotPositive
        case wrongMovementType
        case noBatch
        /// Not enough usable (not expired, not archived) stock; `shortfall` base units could not be served.
        case insufficientStock(shortfall: Int)
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

    // MARK: Reading

    /// Read view over all movements (5.9): idempotency dedup and reversal rules live in the Core.
    func ledger() -> Ledger {
        let all = (try? context.fetch(FetchDescriptor<StockMovement>())) ?? []
        return Ledger(all.compactMap(\.info))
    }

    func stock(of batch: Batch, ledger: Ledger? = nil) -> Int { (ledger ?? self.ledger()).quantity(ofBatch: batch.id) }

    /// Stock of the product over its non-archived batches.
    func stock(of product: Product, ledger: Ledger? = nil) -> Int {
        let l = ledger ?? self.ledger()
        return activeBatches(of: product).reduce(0) { $0 + l.quantity(ofBatch: $1.id) }
    }

    func activeBatches(of product: Product) -> [Batch] { (product.batches ?? []).filter { !$0.isArchived } }

    func summary(of product: Product, ledger: Ledger? = nil) -> ProductSummary {
        let l = ledger ?? self.ledger()
        let batches = activeBatches(of: product)
        let withStock = batches.filter { l.quantity(ofBatch: $0.id) > 0 }
        let total = batches.reduce(0) { $0 + l.quantity(ofBatch: $1.id) }
        let expiries = withStock.map { $0.expiryDay.flatMap(CalendarDay.init(isoString:)) }
        return ProductSummary(
            id: product.id, name: product.name, brand: product.brand, flavor: product.flavor,
            hasCaffeine: product.hasCaffeine, hasLactate: product.hasLactate, category: product.category,
            baseUnit: product.baseUnit, isArchived: product.isArchived, stock: total,
            carbsTotalG: Double(total) * product.info.carbsPerBaseUnit,
            earliestExpiry: expiries.compactMap { $0 }.min(), batchesWithStock: expiries)
    }

    // MARK: Creating

    /// Product + first batch + purchase movement in one go (4.1). Without a quantity only the product is created.
    @discardableResult
    func createProduct(_ draft: ProductDraft) throws -> Product {
        let problems = draft.problems
        guard problems.isEmpty else { throw Failure.invalid(problems) }
        let brand = draft.brand.trimmingCharacters(in: .whitespaces)
        let product = Product(name: draft.name.trimmingCharacters(in: .whitespaces),
                              brand: brand.isEmpty ? nil : brand, flavor: Flavor.normalised(draft.flavor), category: draft.category,
                              baseUnit: draft.baseUnit, portionAmount: draft.effectivePortion,
                              carbsPerPortionG: draft.carbsPerPortionG, glucoseFructoseRatio: draft.glucoseFructoseRatio,
                              hasCaffeine: draft.category == .gel && draft.hasCaffeine,
                              hasLactate: draft.category == .gel && draft.hasLactate)
        context.insert(product)
        if draft.quantity > 0 {
            try insertBatch(for: product, quantity: draft.quantity, totalPriceCents: draft.totalPriceCents,
                            purchaseDay: draft.purchaseDay, expiry: draft.expiry, source: draft.source)
        }
        try context.save()
        return product
    }

    @discardableResult
    func addBatch(to product: Product, quantity: Int, totalPriceCents: Int? = nil, purchaseDay: CalendarDay? = nil,
                  expiry: CalendarDay? = nil, source: String = "") throws -> Batch {
        guard quantity > 0 else { throw Failure.quantityNotPositive }
        let batch = try insertBatch(for: product, quantity: quantity, totalPriceCents: totalPriceCents,
                                    purchaseDay: purchaseDay, expiry: expiry, source: source)
        try context.save()
        return batch
    }

    @discardableResult
    private func insertBatch(for product: Product, quantity: Int, totalPriceCents: Int?, purchaseDay: CalendarDay?,
                             expiry: CalendarDay?, source: String) throws -> Batch {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let batch = Batch(product: product, purchaseDay: purchaseDay ?? today(), quantityPurchased: quantity,
                          totalPriceCents: totalPriceCents, expiryDay: expiry, source: trimmed.isEmpty ? nil : trimmed)
        context.insert(batch)
        context.insert(StockMovement(batch: batch, type: .purchase, delta: quantity, occurredAt: now(),
                                     idempotencyKey: IdempotencyKey.purchase(batchID: batch.id)))
        product.updatedAt = now()
        return batch
    }

    // MARK: Booking

    /// Outflow (consume/discard/expire) or inflow (return) on one batch; `quantity` is always positive.
    @discardableResult
    func book(_ type: MovementType, quantity: Int, on batch: Batch, note: String? = nil) throws -> StockMovement {
        guard quantity > 0 else { throw Failure.quantityNotPositive }
        let delta: Int
        switch type {
        case .consume, .discard, .expire, .pack: delta = -quantity
        case .return: delta = quantity
        default: throw Failure.wrongMovementType
        }
        let movement = insertMovement(type, delta: delta, on: batch, note: note)
        try context.save()
        return movement
    }

    /// Inventory correction (adjust) by a signed delta.
    @discardableResult
    func adjust(by delta: Int, on batch: Batch, note: String? = nil) throws -> StockMovement {
        guard delta != 0 else { throw Failure.quantityNotPositive }
        let movement = insertMovement(.adjust, delta: delta, on: batch, note: note)
        try context.save()
        return movement
    }

    /// "Korrektur buchen" for a negative batch: an adjust that brings it back to 0.
    func correctNegative(_ batch: Batch) throws {
        let current = stock(of: batch)
        guard current < 0 else { return }
        try adjust(by: -current, on: batch, note: "Korrektur Konflikt")
    }

    /// Zähl-Durchgang (Spec 4.6): plan for the counted stock of one product (Core).
    private func countPlan(counted: Int, for product: Product) -> [CountAdjustment] {
        InventoryCount.plan(counted: counted, batches: activeBatches(of: product).compactMap(\.info),
                            ledger: ledger(), today: today())
    }

    /// Difference between the counted and the expected stock (counted − expected), for the preview before booking.
    func countDifference(counted: Int, for product: Product) -> Int {
        counted - stock(of: product)
    }

    /// Books only the difference as `adjust` with the note "Inventur", in one save. Empty when nothing differs.
    @discardableResult
    func applyCount(_ counted: Int, to product: Product) throws -> [StockMovement] {
        let batches = activeBatches(of: product)
        let movements = countPlan(counted: counted, for: product).compactMap { a in
            batches.first { $0.id == a.batchID }.map { insertMovement(.adjust, delta: a.delta, on: $0, note: "Inventur") }
        }
        if !movements.isEmpty { try context.save() }
        return movements
    }

    /// Quick booking −1/+1 on the product. −1 lands on the FEFO batch (earliest best-before, not expired);
    /// +1 returns to the first usable batch (fallback: first batch at all).
    @discardableResult
    func quickBook(_ direction: Int, on product: Product) throws -> StockMovement {
        if direction < 0 {
            let parts = try allocate(1, type: .consume, from: product)
            guard let first = parts.first else { throw Failure.noBatch }
            try context.save()
            return first
        }
        let day = today()
        let infos = activeBatches(of: product).compactMap { b in b.info.map { (b, $0) } }
            .sorted { BatchInfo.fefoPrecedes($0.1, $1.1) }
        let usable = infos.first { $0.1.useDespiteExpiry || Expiry.status(expiry: $0.1.expiryDate, today: day) != .expired }
        guard let batch = (usable ?? infos.first)?.0 else { throw Failure.noBatch }
        return try book(.return, quantity: 1, on: batch)
    }

    /// Outflow over several batches in FEFO order (TV-5). Nothing is booked if the usable stock is too small.
    func removeFEFO(quantity: Int, reason: MovementType = .consume, from product: Product) throws {
        guard quantity > 0 else { throw Failure.quantityNotPositive }
        guard [.consume, .discard, .expire].contains(reason) else { throw Failure.wrongMovementType }
        let parts = try allocate(quantity, type: reason, from: product)
        guard !parts.isEmpty else { throw Failure.noBatch }
        try context.save()
    }

    /// Core FEFO allocation, inserted as movements (not yet saved). Throws before inserting anything on shortfall.
    private func allocate(_ quantity: Int, type: MovementType, from product: Product) throws -> [StockMovement] {
        let batches = activeBatches(of: product)
        let result = FEFO.allocate(quantity: quantity, productID: product.id, batches: batches.compactMap(\.info),
                                   ledger: ledger(), today: today(), type: type, occurredAt: now())
        guard result.shortfall == 0 else { throw Failure.insufficientStock(shortfall: result.shortfall) }
        return result.movements.compactMap { m in
            batches.first { $0.id == m.batchID }.map { insertMovement(type, delta: m.delta, on: $0, note: nil) }
        }
    }

    /// Storno (5.4, 5.9): books the counter movement of `movement`; counts at most once per original (Core).
    @discardableResult
    func reverse(_ movement: StockMovement, note: String? = nil) throws -> StockMovement {
        guard let batch = movement.batch else { throw Failure.noBatch }
        let counter = StockMovement(batch: batch, type: .reversal, delta: -movement.delta, occurredAt: now(),
                                    reversesMovementID: movement.id, referenceID: movement.referenceID, note: note)
        context.insert(counter)
        batch.product?.updatedAt = now()
        try context.save()
        return counter
    }

    /// All batches with stock as the "Verbrauch zuerst" list (AC-H3), straight from the Core.
    func useFirst(thresholds: ExpiryThresholds = .standard) -> [UseFirstEntry] {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let batches = products.flatMap { $0.batches ?? [] }
        return UseFirstList.build(products: products.map(\.info), batches: batches.compactMap(\.info),
                                  ledger: ledger(), today: today(), thresholds: thresholds)
    }

    /// Planned expiry reminders for the current state (pure Core planning, spec 8.2).
    func reminderPlan(hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> [ReminderPlan] {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return ReminderPlanner.plan(products: products.map(\.info),
                                    batches: products.flatMap { $0.batches ?? [] }.compactMap(\.info),
                                    ledger: ledger(), today: today(),
                                    minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), hour: hour, minute: minute)
    }

    /// Dispose an expired batch (AC-H4): `expire` booking of the whole remaining quantity, idempotent per batch.
    @discardableResult
    func dispose(_ batch: Batch) throws -> StockMovement? {
        let remaining = stock(of: batch)
        guard remaining > 0 else { return nil }
        let key = IdempotencyKey.expire(batchID: batch.id)
        if let existing = (batch.movements ?? []).first(where: { $0.idempotencyKey == key }) { return existing }
        let movement = insertMovement(.expire, delta: -remaining, on: batch, note: nil)
        movement.idempotencyKey = key
        try context.save()
        return movement
    }

    func setUseDespiteExpiry(_ value: Bool, on batch: Batch) throws {
        batch.useDespiteExpiry = value
        batch.updatedAt = now()
        try context.save()
    }

    @discardableResult
    private func insertMovement(_ type: MovementType, delta: Int, on batch: Batch, note: String?) -> StockMovement {
        let movement = StockMovement(batch: batch, type: type, delta: delta, occurredAt: now(), note: note)
        context.insert(movement)
        batch.product?.updatedAt = now()
        return movement
    }

    // MARK: Archiving (9.4, AC-B4)

    enum RemovalResult: Equatable { case archived, deleted }

    /// "Delete" = archive when movements exist; hard delete only for something never booked.
    @discardableResult
    func remove(_ product: Product) throws -> RemovalResult {
        let booked = (product.batches ?? []).contains { !($0.movements ?? []).isEmpty }
        if booked {
            product.isArchived = true
            product.updatedAt = now()
            try context.save()
            return .archived
        }
        context.delete(product)
        try context.save()
        return .deleted
    }

    func restore(_ product: Product) throws {
        product.isArchived = false
        product.updatedAt = now()
        try context.save()
    }

    func setArchived(_ archived: Bool, batch: Batch) throws {
        batch.isArchived = archived
        batch.updatedAt = now()
        try context.save()
    }

    /// Geschmack eines vorhandenen Produkts setzen oder entfernen (leer = kein Geschmack).
    func setFlavor(_ flavor: String, on product: Product) throws {
        product.flavor = Flavor.normalised(flavor)
        product.updatedAt = now()
        try context.save()
    }
}

extension InventoryService {
    /// Koffein- und Laktatzusatz eines vorhandenen Produkts setzen (Ja/Nein, keine Mengen).
    func setAdditives(caffeine: Bool, lactate: Bool, on product: Product) throws {
        product.hasCaffeine = caffeine
        product.hasLactate = lactate
        product.updatedAt = now()
        try context.save()
    }
}

enum Flavor {
    /// Getrimmt; leer wird zu nil.
    static func normalised(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
