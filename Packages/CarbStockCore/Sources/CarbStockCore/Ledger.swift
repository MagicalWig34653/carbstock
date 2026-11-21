import Foundation

// Buchungsbuch (Spec 5.4, 5.6, 5.9) und FEFO-Abgang (4.2, 7.2, TV-5).

/// Deterministic idempotency keys (5.4): the same business event always yields the same key.
public enum IdempotencyKey {
    public static func pack(itemID: UUID) -> String { "pack:\(itemID.uuidString)" }
    /// Generation 0 is the first tick (legacy key). After a tick was removed (reversal), ticking again needs a new
    /// key, otherwise the ledger would drop the booking as a duplicate. Two devices in the same state derive the same key.
    public static func pack(itemID: UUID, generation: Int) -> String {
        generation <= 0 ? pack(itemID: itemID) : "pack:\(itemID.uuidString):\(generation)"
    }
    public static func expire(batchID: UUID) -> String { "expire:\(batchID.uuidString)" }
    public static func purchase(batchID: UUID) -> String { "purchase:\(batchID.uuidString)" }
}

/// Result of `Ledger.nextPackAction`.
public enum PackAction: Hashable, Sendable {
    case none
    /// Book a `pack` movement with this idempotency key.
    case pack(key: String)
    /// Book the counter movement (`reversal`) of this `pack` movement.
    case reverse(movementID: UUID)
}

/// A batch whose derived stock is negative (two devices booked offline at the same time, TV-8).
/// Never clamped; reported so the UI can show a conflict and a correction proposal.
public struct StockConflict: Hashable, Sendable {
    public let batchID: UUID
    public let quantity: Int
    /// `adjust` delta that would bring the batch back to 0.
    public var suggestedCorrection: Int { -quantity }
}

/// Read view over all movements (5.9): stock is always the sum of `delta` of the *effective* movements.
///
/// Effective means: (1) of several movements with the same `idempotencyKey` only the oldest counts
/// (`createdAt`, then `id` as tiebreak); (2) a `reversal` counts only if it names an existing
/// (effective) original and only once per original (the oldest reversal wins). A `reversal`
/// without `reversesMovementID` points at nothing and is ignored (invariant 5.9.3).
public struct Ledger: Sendable {
    /// Effective movements in (createdAt, id) order.
    public let movements: [Movement]
    public let ignoredMovementIDs: Set<UUID>
    private let quantities: [UUID: Int]

    public init(_ all: [Movement]) {
        let sorted = all.sorted { Ledger.isOlder($0, $1) }
        var seenKeys = Set<String>()
        var survivors: [Movement] = []
        var ignored = Set<UUID>()
        for m in sorted {
            if let key = m.idempotencyKey {
                if !seenKeys.insert(key).inserted { ignored.insert(m.id); continue }
            }
            survivors.append(m)
        }
        let survivorIDs = Set(survivors.map(\.id))
        var reversed = Set<UUID>()
        var effective: [Movement] = []
        for m in survivors {
            if m.type == .reversal {
                guard let original = m.reversesMovementID, survivorIDs.contains(original),
                      reversed.insert(original).inserted else { ignored.insert(m.id); continue }
            }
            effective.append(m)
        }
        var q: [UUID: Int] = [:]
        for m in effective { q[m.batchID, default: 0] += m.delta }
        self.movements = effective
        self.ignoredMovementIDs = ignored
        self.quantities = q
    }

    private static func isOlder(_ a: Movement, _ b: Movement) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }

    /// Stock of one batch in base units (may be negative).
    public func quantity(ofBatch id: UUID) -> Int { quantities[id] ?? 0 }

    /// Carbs remaining in a batch in g (not clamped).
    public func carbsRemainingG(batch: BatchInfo, product: ProductInfo) -> Double {
        Double(quantity(ofBatch: batch.id)) * product.carbsPerBaseUnit
    }

    /// All batches with negative stock, ordered by batch id for determinism.
    public func conflicts() -> [StockConflict] {
        quantities.filter { $0.value < 0 }
            .map { StockConflict(batchID: $0.key, quantity: $0.value) }
            .sorted { $0.batchID.uuidString < $1.batchID.uuidString }
    }

    /// Net `pack`/`reversal` quantity booked against a pack list item (5.6): sum of deltas, usually <= 0.
    /// A reversal without its own `referenceID` inherits the one of the movement it reverses.
    public func packNet(itemID: UUID) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: movements.map { ($0.id, $0) })
        var sum = 0
        for m in movements where m.type == .pack || m.type == .reversal {
            var ref = m.referenceID
            if ref == nil, m.type == .reversal, let o = m.reversesMovementID { ref = byID[o]?.referenceID }
            if ref == itemID { sum += m.delta }
        }
        return sum
    }

    /// Item counts as packed when the net sum is not 0 (5.6).
    public func isPacked(itemID: UUID) -> Bool { packNet(itemID: itemID) != 0 }

    /// Packed quantity in base units (positive number).
    public func packedQuantity(itemID: UUID) -> Int { -packNet(itemID: itemID) }

    /// Quantity put back with `return` bookings that refer to the item (AC-L6).
    public func returnedQuantity(itemID: UUID) -> Int {
        movements.filter { $0.type == .return && $0.referenceID == itemID }.reduce(0) { $0 + $1.delta }
    }

    /// Packed minus put back: what the session really used (AC-L6, "Verbrauch rechnet netto").
    public func netConsumedQuantity(itemID: UUID) -> Int { packedQuantity(itemID: itemID) - returnedQuantity(itemID: itemID) }

    /// What a tick change needs (AC-L2/L3). Nothing if the item is already in the wanted state.
    public func nextPackAction(itemID: UUID, wantPacked: Bool) -> PackAction {
        let packed = isPacked(itemID: itemID)
        if wantPacked {
            guard !packed else { return .none }
            let generation = movements.filter { $0.type == .reversal && packReference($0) == itemID }.count
            return .pack(key: IdempotencyKey.pack(itemID: itemID, generation: generation))
        }
        guard packed else { return .none }
        let reversedIDs = Set(movements.filter { $0.type == .reversal }.compactMap(\.reversesMovementID))
        let open = movements.filter { $0.type == .pack && $0.referenceID == itemID && !reversedIDs.contains($0.id) }
            .max { Ledger.isOlder($0, $1) }
        guard let open else { return .none }
        return .reverse(movementID: open.id)
    }

    private func packReference(_ m: Movement) -> UUID? {
        if let r = m.referenceID { return r }
        guard let o = m.reversesMovementID else { return nil }
        return movements.first { $0.id == o }?.referenceID
    }
}

extension BatchInfo {
    /// FEFO order: earliest best-before first, no best-before last; ties by purchase date, then id (deterministic).
    public static func fefoPrecedes(_ a: BatchInfo, _ b: BatchInfo) -> Bool {
        switch (a.expiryDate, b.expiryDate) {
        case let (x?, y?) where x != y: return x < y
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        if a.purchaseDate != b.purchaseDate { return a.purchaseDate < b.purchaseDate }
        return a.id.uuidString < b.id.uuidString
    }

    /// Expired = best-before before `today`; the best-before day itself still counts (AC-H2).
    func isExpired(on today: CalendarDay) -> Bool { expiryDate.map { $0 < today } ?? false }
}

public struct FEFOAllocation: Hashable, Sendable {
    /// Not yet persisted movements with negative `delta`, in FEFO order.
    public let movements: [Movement]
    public let allocatedQuantity: Int
    /// Part of the requested quantity no eligible batch could serve.
    public let shortfall: Int
}

public enum FEFO {
    /// Distributes `quantity` base units of a product over its batches, earliest best-before first (TV-5, AC-B3).
    ///
    /// Annahme (4.2): expired batches are skipped unless `useDespiteExpiry`; archived batches and
    /// batches with stock <= 0 are skipped; batches without best-before date come last.
    /// Stock is never driven negative here; what cannot be served is reported as `shortfall`.
    public static func allocate(quantity: Int, productID: UUID, batches: [BatchInfo], ledger: Ledger,
                                today: CalendarDay, type: MovementType = .consume, occurredAt: Date,
                                createdAt: Date? = nil, referenceID: UUID? = nil) -> FEFOAllocation {
        guard quantity > 0 else { return FEFOAllocation(movements: [], allocatedQuantity: 0, shortfall: 0) }
        let eligible = batches
            .filter { $0.productID == productID && !$0.isArchived && ($0.useDespiteExpiry || !$0.isExpired(on: today)) }
            .sorted(by: BatchInfo.fefoPrecedes)
        var open = quantity
        var out: [Movement] = []
        for b in eligible where open > 0 {
            let available = ledger.quantity(ofBatch: b.id)
            guard available > 0 else { continue }
            let take = min(available, open)
            out.append(Movement(batchID: b.id, type: type, delta: -take, occurredAt: occurredAt,
                                createdAt: createdAt, referenceID: referenceID))
            open -= take
        }
        return FEFOAllocation(movements: out, allocatedQuantity: quantity - open, shortfall: open)
    }
}

/// Price figures per batch (5.3). Nil without price (AC-B6).
public enum PriceMetrics {
    /// Carbs of the purchased quantity in g.
    public static func totalCarbsG(batch: BatchInfo, product: ProductInfo) -> Double {
        Double(batch.quantityPurchased) * product.carbsPerBaseUnit
    }

    /// Euro per g carbs (not rounded).
    public static func pricePerGramCarbs(batch: BatchInfo, product: ProductInfo) -> Double? {
        guard let cents = batch.totalPriceCents else { return nil }
        let carbs = totalCarbsG(batch: batch, product: product)
        guard carbs > 0 else { return nil }
        return Double(cents) / 100 / carbs
    }

    /// Euro per 100 g carbs (AC-B1: 25 EUR / 900 g = 2.78). Rounding is left to the display.
    public static func pricePer100gCarbs(batch: BatchInfo, product: ProductInfo) -> Double? {
        pricePerGramCarbs(batch: batch, product: product).map { $0 * 100 }
    }

    /// Grams of carbs per euro (inverse).
    public static func carbsPerEuro(batch: BatchInfo, product: ProductInfo) -> Double? {
        pricePerGramCarbs(batch: batch, product: product).map { 1 / $0 }
    }
}
