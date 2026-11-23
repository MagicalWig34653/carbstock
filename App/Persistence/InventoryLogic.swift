import CarbStockCore
import Foundation

// Pure inventory logic: no SwiftData, no clock, no UI. FEFO, Bestand und Haltbarkeit kommen aus
// CarbStockCore (Ledger, FEFO, Expiry); hier liegt nur Darstellung und Listenlogik der App.

/// Haltbarkeitsanzeige: Core-Status plus Resttage (für Text und Symbol).
struct ExpiryBadge: Equatable, Sendable {
    var status: CarbStockCore.ExpiryStatus
    /// Days left (negative when expired); nil without best-before date.
    var days: Int?

    static func of(_ expiry: CalendarDay?, today: CalendarDay,
                   thresholds: ExpiryThresholds = .standard) -> ExpiryBadge {
        ExpiryBadge(status: Expiry.status(expiry: expiry, today: today, thresholds: thresholds),
                    days: Expiry.remainingDays(expiry: expiry, today: today))
    }

    var symbol: String {
        switch status {
        case .expired: "xmark.octagon.fill"
        case .red: "exclamationmark.triangle.fill"
        case .yellow: "clock.fill"
        case .green: "checkmark.circle.fill"
        case .noExpiry: "infinity"
        }
    }

    var text: String {
        let d = days ?? 0
        return switch status {
        case .expired: d == 0 ? "abgelaufen" : "abgelaufen seit \(-d) \(-d == 1 ? "Tag" : "Tagen")"
        case .red, .yellow, .green: d == 0 ? "läuft heute ab" : "noch \(d) \(d == 1 ? "Tag" : "Tage")"
        case .noExpiry: "ohne MHD"
        }
    }
}

/// One list row (derived, never stored).
struct ProductSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var brand: String?
    var flavor: String?
    var hasCaffeine = false
    var hasLactate = false
    var category: ProductCategory
    var baseUnit: BaseUnit
    var isArchived: Bool
    var stock: Int
    var carbsTotalG: Double
    /// Earliest best-before among batches with stock > 0; nil if none has one.
    var earliestExpiry: CalendarDay?
    var displayName: String { ProductInfo(id: id, name: name, flavor: flavor, category: category, baseUnit: baseUnit, carbsPerPortionG: 1,
                                         hasCaffeine: hasCaffeine, hasLactate: hasLactate).displayName }
    /// Zweite Zeile der Liste: Marke, Geschmack, Zusätze (nil, wenn nichts davon gesetzt ist).
    var detailLine: String? {
        var parts = [brand, flavor].compactMap { Flavor.normalised($0) }
        if hasCaffeine { parts.append("mit Koffein") }
        if hasLactate { parts.append("mit Laktat") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var hasStock: Bool { stock > 0 }
    var isConflict: Bool { stock < 0 }
    var batchesWithStock: [CalendarDay?] = []
}

enum InventoryFilterMode: String, CaseIterable, Identifiable, Sendable {
    case all, expiringSoon, expired, noExpiry, archive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Alle"
        case .expiringSoon: "Läuft in ≤ 60 Tagen ab"
        case .expired: "Abgelaufen"
        case .noExpiry: "Ohne MHD"
        case .archive: "Archiv"
        }
    }
}

struct InventoryFilter: Equatable, Sendable {
    var search = ""
    var category: ProductCategory?
    var mode: InventoryFilterMode = .all
    var expiringWithinDays = 60
}

enum InventoryList {
    /// Case- and diacritic-insensitive search over name, brand and flavor (AC-B5), then filters, sorted by name.
    static func apply(_ filter: InventoryFilter, to products: [ProductSummary], today: CalendarDay) -> [ProductSummary] {
        let query = filter.search.trimmingCharacters(in: .whitespaces)
        func matches(_ text: String?) -> Bool {
            text?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return products.filter { p in
            if filter.mode == .archive { if !p.isArchived { return false } } else if p.isArchived { return false }
            if !query.isEmpty, !(matches(p.name) || matches(p.brand) || matches(p.flavor)) { return false }
            if let c = filter.category, p.category != c { return false }
            let dated = p.batchesWithStock
            switch filter.mode {
            case .all, .archive: return true
            case .expiringSoon:
                return dated.contains { d in d.map { $0 >= today && today.days(until: $0) <= filter.expiringWithinDays } ?? false }
            case .expired: return dated.contains { d in d.map { $0 < today } ?? false }
            case .noExpiry: return dated.contains { $0 == nil }
            }
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// Input of "Produkt anlegen" (spec 4.1) with its validation.
struct ProductDraft: Equatable, Sendable {
    enum Problem: Error, Equatable, Sendable {
        case nameMissing, carbsNotPositive, portionNotPositive, quantityNegative, priceNegative
        var message: String {
            switch self {
            case .nameMissing: "Bitte einen Namen eingeben."
            case .carbsNotPositive: "Carbs je Portion müssen größer als 0 sein."
            case .portionNotPositive: "Die Portionsgröße muss größer als 0 sein."
            case .quantityNegative: "Die Menge darf nicht negativ sein."
            case .priceNegative: "Der Preis darf nicht negativ sein."
            }
        }
    }

    var name = ""
    var brand = ""
    var flavor = ""
    var hasCaffeine = false
    var hasLactate = false
    var category: ProductCategory = .gel
    var baseUnit: BaseUnit = .piece
    var portionAmount: Double = 1
    var carbsPerPortionG: Double = 0
    var glucoseFructoseRatio: Double?
    var quantity: Int = 0
    var totalPriceCents: Int?
    var expiry: CalendarDay?
    var purchaseDay: CalendarDay?
    var source = ""

    /// Pieces always have a portion of 1; only powder takes a portion size in g.
    var effectivePortion: Double { baseUnit == .piece ? 1 : portionAmount }

    var problems: [Problem] {
        var list: [Problem] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { list.append(.nameMissing) }
        if !(carbsPerPortionG > 0) { list.append(.carbsNotPositive) }
        if !(effectivePortion > 0) { list.append(.portionNotPositive) }
        if quantity < 0 { list.append(.quantityNegative) }
        if let p = totalPriceCents, p < 0 { list.append(.priceNegative) }
        return list
    }
}
