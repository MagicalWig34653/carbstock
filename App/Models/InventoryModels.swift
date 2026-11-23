import CarbStockCore
import Foundation
import SwiftData

// Inventory store: mirrored to the user's PRIVATE CloudKit database (spec 9.1, O-01 option B).
//
// CloudKit rules (spec 9.2), enforced here and checked by SchemaRulesTests:
//  - no @Attribute(.unique); every attribute has a default or is optional
//  - every relationship is optional and has an inverse; no .deny delete rule
//  - the schema is ADDITIVE ONLY once promoted to production: never rename or delete
//    a stored property; add new ones with defaults instead. Bump `schemaVersion` on
//    records that carry new meaning.
//  - no health, body, performance, location or HealthKit fields (AC-D4)
//
// Enums are stored as raw strings, calendar days as "yyyy-MM-dd" strings.

@Model
final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    /// Geschmacksrichtung. Additiv ergänzt (optional): bestehende Datensätze bleiben gültig.
    var flavor: String?
    /// Geloption Koffein- bzw. Laktatzusatz (Ja/Nein). Additiv mit Vorgabewert: bestehende Datensätze bleiben gültig.
    var hasCaffeine: Bool = false
    var hasLactate: Bool = false
    var categoryRaw: String = ProductCategory.gel.rawValue
    var baseUnitRaw: String = BaseUnit.piece.rawValue
    var portionAmount: Double = 1
    var carbsPerPortionG: Double = 0
    var glucoseFructoseRatio: Double?
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var schemaVersion: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \Batch.product)
    var batches: [Batch]? = []

    init(id: UUID = UUID(), name: String, brand: String? = nil, flavor: String? = nil, category: ProductCategory, baseUnit: BaseUnit,
         portionAmount: Double = 1, carbsPerPortionG: Double, glucoseFructoseRatio: Double? = nil,
         hasCaffeine: Bool = false, hasLactate: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.flavor = flavor
        self.hasCaffeine = hasCaffeine
        self.hasLactate = hasLactate
        self.categoryRaw = category.rawValue
        self.baseUnitRaw = baseUnit.rawValue
        self.portionAmount = portionAmount
        self.carbsPerPortionG = carbsPerPortionG
        self.glucoseFructoseRatio = glucoseFructoseRatio
    }

    var category: ProductCategory { ProductCategory(rawValue: categoryRaw) ?? .gel }
    var baseUnit: BaseUnit { BaseUnit(rawValue: baseUnitRaw) ?? .piece }
    var displayName: String { info.displayName }

    var info: ProductInfo {
        ProductInfo(id: id, name: name, brand: brand, flavor: flavor, category: category, baseUnit: baseUnit,
                    portionAmount: portionAmount, carbsPerPortionG: carbsPerPortionG,
                    glucoseFructoseRatio: glucoseFructoseRatio, isArchived: isArchived,
                    hasCaffeine: hasCaffeine, hasLactate: hasLactate)
    }
}

@Model
final class Batch {
    var id: UUID = UUID()
    var product: Product?
    var purchaseDay: String = ""
    var quantityPurchased: Int = 0
    var totalPriceCents: Int?
    var currency: String = "EUR"
    var expiryDay: String?
    var source: String?
    var useDespiteExpiry: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var schemaVersion: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \StockMovement.batch)
    var movements: [StockMovement]? = []

    init(id: UUID = UUID(), product: Product, purchaseDay: CalendarDay, quantityPurchased: Int,
         totalPriceCents: Int? = nil, expiryDay: CalendarDay? = nil, source: String? = nil) {
        self.id = id
        self.product = product
        self.purchaseDay = purchaseDay.isoString
        self.quantityPurchased = quantityPurchased
        self.totalPriceCents = totalPriceCents
        self.expiryDay = expiryDay?.isoString
        self.source = source
    }

    var info: BatchInfo? {
        guard let product, let purchase = CalendarDay(isoString: purchaseDay) else { return nil }
        return BatchInfo(id: id, productID: product.id, purchaseDate: purchase, quantityPurchased: quantityPurchased,
                         totalPriceCents: totalPriceCents, currency: currency,
                         expiryDate: expiryDay.flatMap(CalendarDay.init(isoString:)),
                         useDespiteExpiry: useDespiteExpiry, isArchived: isArchived)
    }
}

/// Append-only (spec 5.4). Code must never mutate or delete one, except "delete all data".
@Model
final class StockMovement {
    var id: UUID = UUID()
    var batch: Batch?
    var typeRaw: String = MovementType.adjust.rawValue
    var delta: Int = 0
    var occurredAt: Date = Date.now
    var createdAt: Date = Date.now
    var idempotencyKey: String?
    var reversesMovementID: UUID?
    var referenceID: UUID?
    var deviceID: String?
    var note: String?
    var schemaVersion: Int = 1

    init(id: UUID = UUID(), batch: Batch, type: MovementType, delta: Int, occurredAt: Date = .now,
         idempotencyKey: String? = nil, reversesMovementID: UUID? = nil, referenceID: UUID? = nil,
         deviceID: String? = nil, note: String? = nil) {
        self.id = id
        self.batch = batch
        self.typeRaw = type.rawValue
        self.delta = delta
        self.occurredAt = occurredAt
        self.createdAt = .now
        self.idempotencyKey = idempotencyKey
        self.reversesMovementID = reversesMovementID
        self.referenceID = referenceID
        self.deviceID = deviceID
        self.note = note
    }

    var info: Movement? {
        guard let batch, let type = MovementType(rawValue: typeRaw) else { return nil }
        return Movement(id: id, batchID: batch.id, type: type, delta: delta, occurredAt: occurredAt,
                        createdAt: createdAt, idempotencyKey: idempotencyKey,
                        reversesMovementID: reversesMovementID, referenceID: referenceID)
    }
}

@Model
final class ShoppingListItem {
    var id: UUID = UUID()
    var productID: UUID?
    var freeText: String?
    var plannedQuantity: Int = 0
    var estimatedTotalPriceCents: Int?
    var stateRaw: String = "open" // open · bought · dropped
    var createdAt: Date = Date.now
    var schemaVersion: Int = 1
    // Added with M5 (additive, optional): best-before of the offer, the offer/verdict snapshot it came from
    // (JSON, see `SavedOffer`) and the batch that "Gekauft" created.
    var expiryDay: String?
    var offerJSON: Data?
    var batchID: UUID?

    init(productID: UUID? = nil, freeText: String? = nil, plannedQuantity: Int, estimatedTotalPriceCents: Int? = nil) {
        self.productID = productID
        self.freeText = freeText
        self.plannedQuantity = plannedQuantity
        self.estimatedTotalPriceCents = estimatedTotalPriceCents
    }
}

/// History of the purchase advisor (5.7). Input and reasons are stored as JSON snapshots so
/// the CloudKit schema stays small and additive.
@Model
final class PurchaseEvaluation {
    var id: UUID = UUID()
    var inputJSON: Data?
    var verdictRaw: String = ""
    var reasonsJSON: Data?
    var userDecisionRaw: String = "none" // bought · skipped · none
    var createdAt: Date = Date.now
    var schemaVersion: Int = 1
    /// Added with M5 (additive, optional): quantity of "teilweise kaufen" (`verdictRaw` = "buyPartially").
    var verdictQuantity: Int?

    init(verdictRaw: String, inputJSON: Data? = nil, reasonsJSON: Data? = nil) {
        self.verdictRaw = verdictRaw
        self.inputJSON = inputJSON
        self.reasonsJSON = reasonsJSON
    }
}
