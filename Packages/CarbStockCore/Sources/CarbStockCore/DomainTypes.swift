import Foundation

// Value types the app maps its SwiftData records into (spec section 5).
// Field names are part of the contract with the persistence layer; keep them
// in sync with App/Models. Quantities are integers in the product's base unit,
// money is integer cents, carbs are Double grams rounded only for display (5.9.6).

public enum ProductCategory: String, CaseIterable, Codable, Sendable {
    case gel, drink, bar, jelly, homemade
}

public enum BaseUnit: String, CaseIterable, Codable, Sendable {
    case piece, gram
}

public enum MovementType: String, CaseIterable, Codable, Sendable {
    case purchase, consume, pack, `return`, expire, discard, adjust, reversal
}

/// Session types (spec 4.3/5.5). `recovery` is the working assumption for "regen" (O-07).
public enum SessionType: String, CaseIterable, Codable, Sendable {
    case vo2, threshold, z2, long, recovery
}

public struct ProductInfo: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var baseUnit: BaseUnit
    /// Base units per portion (piece: 1; powder: e.g. 40 g).
    public var portionAmount: Double
    public var carbsPerPortionG: Double
    public var glucoseFructoseRatio: Double?
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, brand: String? = nil, category: ProductCategory,
                baseUnit: BaseUnit, portionAmount: Double = 1, carbsPerPortionG: Double,
                glucoseFructoseRatio: Double? = nil, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.baseUnit = baseUnit
        self.portionAmount = portionAmount
        self.carbsPerPortionG = carbsPerPortionG
        self.glucoseFructoseRatio = glucoseFructoseRatio
        self.isArchived = isArchived
    }

    /// Derived, never stored (5.2).
    public var carbsPerBaseUnit: Double { carbsPerPortionG / portionAmount }
}

public struct BatchInfo: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var productID: UUID
    public var purchaseDate: CalendarDay
    public var quantityPurchased: Int
    public var totalPriceCents: Int?
    public var currency: String
    /// Valid up to and including this day; nil = no best-before date (grey).
    public var expiryDate: CalendarDay?
    /// User chose "use anyway" for an expired batch (4.2): counts for the forecast again.
    public var useDespiteExpiry: Bool
    public var isArchived: Bool

    public init(id: UUID = UUID(), productID: UUID, purchaseDate: CalendarDay, quantityPurchased: Int,
                totalPriceCents: Int? = nil, currency: String = "EUR", expiryDate: CalendarDay? = nil,
                useDespiteExpiry: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.quantityPurchased = quantityPurchased
        self.totalPriceCents = totalPriceCents
        self.currency = currency
        self.expiryDate = expiryDate
        self.useDespiteExpiry = useDespiteExpiry
        self.isArchived = isArchived
    }
}

/// Immutable stock movement (5.4). Never edited; corrections are `reversal` or `adjust`.
public struct Movement: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var batchID: UUID
    public var type: MovementType
    /// Signed, in the product's base unit.
    public var delta: Int
    public var occurredAt: Date
    public var createdAt: Date
    public var idempotencyKey: String?
    public var reversesMovementID: UUID?
    public var referenceID: UUID?

    public init(id: UUID = UUID(), batchID: UUID, type: MovementType, delta: Int, occurredAt: Date,
                createdAt: Date? = nil, idempotencyKey: String? = nil, reversesMovementID: UUID? = nil,
                referenceID: UUID? = nil) {
        self.id = id
        self.batchID = batchID
        self.type = type
        self.delta = delta
        self.occurredAt = occurredAt
        self.createdAt = createdAt ?? occurredAt
        self.idempotencyKey = idempotencyKey
        self.reversesMovementID = reversesMovementID
        self.referenceID = referenceID
    }
}

public enum SessionStatus: String, CaseIterable, Codable, Sendable {
    case planned, done, skipped
}

public struct PlannedSession: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var day: CalendarDay
    public var type: SessionType
    public var durationMinutes: Int
    public var carbsPerHourOverride: Int?
    public var status: SessionStatus

    public init(id: UUID = UUID(), day: CalendarDay, type: SessionType, durationMinutes: Int,
                carbsPerHourOverride: Int? = nil, status: SessionStatus = .planned) {
        self.id = id
        self.day = day
        self.type = type
        self.durationMinutes = durationMinutes
        self.carbsPerHourOverride = carbsPerHourOverride
        self.status = status
    }
}

/// Recurring session per weekday (proposal, O-08). `weekdayIndex`: 0 = Monday … 6 = Sunday.
public struct WeeklyTemplateEntry: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var weekdayIndex: Int
    public var type: SessionType
    public var durationMinutes: Int
    public var carbsPerHourOverride: Int?
    public var validFrom: CalendarDay
    public var validUntil: CalendarDay?

    public init(id: UUID = UUID(), weekdayIndex: Int, type: SessionType, durationMinutes: Int,
                carbsPerHourOverride: Int? = nil, validFrom: CalendarDay, validUntil: CalendarDay? = nil) {
        self.id = id
        self.weekdayIndex = weekdayIndex
        self.type = type
        self.durationMinutes = durationMinutes
        self.carbsPerHourOverride = carbsPerHourOverride
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

/// Built-in carbs/h defaults (5.5: live in code, only user overrides are stored). Values are the
/// working assumption of O-07 and are planning presets, not nutrition advice (10.2).
public struct CarbRate: Hashable, Sendable {
    public let defaultPerHour: Int
    public let range: ClosedRange<Int>?

    public static func builtIn(_ type: SessionType) -> CarbRate {
        switch type {
        case .vo2: CarbRate(defaultPerHour: 70, range: 60...80)
        case .threshold: CarbRate(defaultPerHour: 70, range: 60...80)
        case .long: CarbRate(defaultPerHour: 80, range: 70...90)
        case .recovery: CarbRate(defaultPerHour: 40, range: 30...50)
        case .z2: CarbRate(defaultPerHour: 60, range: nil) // O-07: no value in the original, placeholder
        }
    }
}
