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
    /// Geschmacksrichtung (optional). Jede Sorte ist ein eigenes Produkt mit eigenem Bestand.
    public var flavor: String?
    public var category: ProductCategory
    public var baseUnit: BaseUnit
    /// Base units per portion (piece: 1; powder: e.g. 40 g).
    public var portionAmount: Double
    public var carbsPerPortionG: Double
    public var glucoseFructoseRatio: Double?
    public var isArchived: Bool
    /// Geloption: mit Koffein bzw. mit Laktatzusatz (nur Ja/Nein, keine Mengen).
    public var hasCaffeine: Bool
    public var hasLactate: Bool

    public init(id: UUID = UUID(), name: String, brand: String? = nil, flavor: String? = nil, category: ProductCategory,
                baseUnit: BaseUnit, portionAmount: Double = 1, carbsPerPortionG: Double,
                glucoseFructoseRatio: Double? = nil, isArchived: Bool = false,
                hasCaffeine: Bool = false, hasLactate: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.flavor = flavor
        self.category = category
        self.baseUnit = baseUnit
        self.portionAmount = portionAmount
        self.carbsPerPortionG = carbsPerPortionG
        self.glucoseFructoseRatio = glucoseFructoseRatio
        self.isArchived = isArchived
        self.hasCaffeine = hasCaffeine
        self.hasLactate = hasLactate
    }

    /// Sicherungen und Verlauf aus der Zeit vor den Zusätzen haben die Felder nicht: dann „nein“.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        flavor = try c.decodeIfPresent(String.self, forKey: .flavor)
        category = try c.decode(ProductCategory.self, forKey: .category)
        baseUnit = try c.decode(BaseUnit.self, forKey: .baseUnit)
        portionAmount = try c.decode(Double.self, forKey: .portionAmount)
        carbsPerPortionG = try c.decode(Double.self, forKey: .carbsPerPortionG)
        glucoseFructoseRatio = try c.decodeIfPresent(Double.self, forKey: .glucoseFructoseRatio)
        isArchived = try c.decode(Bool.self, forKey: .isArchived)
        hasCaffeine = try c.decodeIfPresent(Bool.self, forKey: .hasCaffeine) ?? false
        hasLactate = try c.decodeIfPresent(Bool.self, forKey: .hasLactate) ?? false
    }

    /// Name für Listen und Auswahl: mit Geschmack und Zusätzen, soweit gesetzt.
    public var displayName: String {
        var parts = [name]
        if let f = flavor?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { parts.append(f) }
        if hasCaffeine { parts.append("mit Koffein") }
        if hasLactate { parts.append("mit Laktat") }
        return parts.joined(separator: " · ")
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
    /// Bezugsquelle (Shop, Aktion). Optional: fehlt in älteren Sicherungen.
    public var source: String?

    public init(id: UUID = UUID(), productID: UUID, purchaseDate: CalendarDay, quantityPurchased: Int,
                totalPriceCents: Int? = nil, currency: String = "EUR", expiryDate: CalendarDay? = nil,
                useDespiteExpiry: Bool = false, isArchived: Bool = false, source: String? = nil) {
        self.id = id
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.quantityPurchased = quantityPurchased
        self.totalPriceCents = totalPriceCents
        self.currency = currency
        self.expiryDate = expiryDate
        self.useDespiteExpiry = useDespiteExpiry
        self.isArchived = isArchived
        self.source = source
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
    /// Freitext zur Buchung (z. B. „Inventur“). Optional: fehlt in älteren Sicherungen.
    public var note: String?

    public init(id: UUID = UUID(), batchID: UUID, type: MovementType, delta: Int, occurredAt: Date,
                createdAt: Date? = nil, idempotencyKey: String? = nil, reversesMovementID: UUID? = nil,
                referenceID: UUID? = nil, note: String? = nil) {
        self.id = id
        self.batchID = batchID
        self.type = type
        self.delta = delta
        self.occurredAt = occurredAt
        self.createdAt = createdAt ?? occurredAt
        self.idempotencyKey = idempotencyKey
        self.reversesMovementID = reversesMovementID
        self.referenceID = referenceID
        self.note = note
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
    /// Eigene Angaben ohne Einfluss auf den Bedarf; optional, fehlen in älteren Sicherungen.
    public var title: String?
    public var note: String?
    public var startTime: Date?

    public init(id: UUID = UUID(), day: CalendarDay, type: SessionType, durationMinutes: Int,
                carbsPerHourOverride: Int? = nil, status: SessionStatus = .planned,
                title: String? = nil, note: String? = nil, startTime: Date? = nil) {
        self.id = id
        self.day = day
        self.type = type
        self.durationMinutes = durationMinutes
        self.carbsPerHourOverride = carbsPerHourOverride
        self.status = status
        self.title = title
        self.note = note
        self.startTime = startTime
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
