import Foundation

// Haltbarkeit (Spec 4.2): Status, Verbrauch-zuerst-Liste, Verbrauchsrate.

public enum ExpiryStatus: String, CaseIterable, Codable, Sendable {
    case green, yellow, red, expired, noExpiry
}

/// Thresholds in months (4.2, O-12: defaults 6 and 3, configurable).
public struct ExpiryThresholds: Hashable, Sendable {
    public var greenMonths: Int
    public var redMonths: Int
    public static let standard = ExpiryThresholds(greenMonths: 6, redMonths: 3)
    public init(greenMonths: Int = 6, redMonths: Int = 3) {
        self.greenMonths = greenMonths
        self.redMonths = redMonths
    }
}

public enum Expiry {
    /// green: expiry >= today + greenMonths; yellow: below that; red: expiry < today + redMonths;
    /// expired: expiry < today (the best-before day itself is not expired, AC-H2); noExpiry: nil.
    public static func status(expiry: CalendarDay?, today: CalendarDay,
                              thresholds: ExpiryThresholds = .standard) -> ExpiryStatus {
        guard let expiry else { return .noExpiry }
        if expiry < today { return .expired }
        if expiry < today.adding(months: thresholds.redMonths) { return .red }
        if expiry < today.adding(months: thresholds.greenMonths) { return .yellow }
        return .green
    }

    /// Days left (0 on the last day, negative when expired); nil without best-before date.
    public static func remainingDays(expiry: CalendarDay?, today: CalendarDay) -> Int? {
        expiry.map { today.days(until: $0) }
    }

    /// Recommended consumption rate in base units per week so that `remainingQuantity` is gone by the
    /// best-before date (4.2). Annahme: the best-before day is still usable, so `remainingDays + 1` days
    /// are available. Nil for expired, no best-before date or nothing left.
    public static func recommendedRatePerWeek(remainingQuantity: Int, expiry: CalendarDay?,
                                              today: CalendarDay) -> Double? {
        guard remainingQuantity > 0, let days = remainingDays(expiry: expiry, today: today), days >= 0 else { return nil }
        return Double(remainingQuantity) / Double(days + 1) * 7
    }
}

public struct UseFirstEntry: Hashable, Sendable, Identifiable {
    public var id: UUID { batch.id }
    public let batch: BatchInfo
    public let product: ProductInfo
    public let remainingQuantity: Int
    public let carbsG: Double
    public let status: ExpiryStatus
    public let remainingDays: Int?
    /// Base units per week; nil if not applicable (see `Expiry.recommendedRatePerWeek`).
    public let recommendedRatePerWeek: Double?
}

public enum UseFirstList {
    /// "Verbrauch zuerst" (AC-H3): expired first, then earliest best-before, then no best-before.
    /// Expired batches have the earliest dates, so one FEFO sort yields exactly that order.
    /// Batches with remaining quantity <= 0 (also negative) and archived batches or products are left out.
    public static func build(products: [ProductInfo], batches: [BatchInfo], ledger: Ledger, today: CalendarDay,
                             thresholds: ExpiryThresholds = .standard) -> [UseFirstEntry] {
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return batches.sorted(by: BatchInfo.fefoPrecedes).compactMap { b in
            guard !b.isArchived, let p = byID[b.productID] else { return nil }
            let qty = ledger.quantity(ofBatch: b.id)
            guard qty > 0 else { return nil }
            return UseFirstEntry(batch: b, product: p, remainingQuantity: qty,
                                 carbsG: Double(qty) * p.carbsPerBaseUnit,
                                 status: Expiry.status(expiry: b.expiryDate, today: today, thresholds: thresholds),
                                 remainingDays: Expiry.remainingDays(expiry: b.expiryDate, today: today),
                                 recommendedRatePerWeek: Expiry.recommendedRatePerWeek(remainingQuantity: qty, expiry: b.expiryDate, today: today))
        }
    }
}
