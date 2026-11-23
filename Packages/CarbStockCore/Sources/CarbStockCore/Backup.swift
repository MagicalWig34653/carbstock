import Foundation

// Sicherung als JSON (Spec 9.6, AC-S7) und Zusammenführen doppelter Produkte (9.3, AC-S4). Reine Logik.

/// Vollständige Sicherung der Nutzerdaten. Import ist idempotent: bekannte IDs werden nicht noch einmal angelegt.
/// Enthält bewusst keine Gesundheitsdaten (nur Vorrat, Buchungen, Sessions, Wochenvorlage, Carbs/h-Abweichungen).
public struct BackupDocument: Hashable, Sendable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var products: [ProductInfo]
    public var batches: [BatchInfo]
    public var movements: [Movement]
    public var sessions: [PlannedSession]
    public var template: [WeeklyTemplateEntry]
    /// Only the user's deviations from the built-in table (5.5).
    public var carbRates: [SessionType: Int]

    public init(version: Int = BackupDocument.currentVersion, exportedAt: Date, products: [ProductInfo] = [],
                batches: [BatchInfo] = [], movements: [Movement] = [], sessions: [PlannedSession] = [],
                template: [WeeklyTemplateEntry] = [], carbRates: [SessionType: Int] = [:]) {
        self.version = version
        self.exportedAt = exportedAt
        self.products = products
        self.batches = batches
        self.movements = movements
        self.sessions = sessions
        self.template = template
        self.carbRates = carbRates
    }

    // Enum-keyed dictionaries would encode as an array of pairs; a plain string-keyed object is readable and stable.
    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, products, batches, movements, sessions, template, carbRates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        products = try c.decode([ProductInfo].self, forKey: .products)
        batches = try c.decode([BatchInfo].self, forKey: .batches)
        movements = try c.decode([Movement].self, forKey: .movements)
        sessions = try c.decodeIfPresent([PlannedSession].self, forKey: .sessions) ?? []
        template = try c.decodeIfPresent([WeeklyTemplateEntry].self, forKey: .template) ?? []
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .carbRates) ?? [:]
        carbRates = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SessionType(rawValue: k).map { ($0, v) } })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(products, forKey: .products)
        try c.encode(batches, forKey: .batches)
        try c.encode(movements, forKey: .movements)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(template, forKey: .template)
        try c.encode(Dictionary(uniqueKeysWithValues: carbRates.map { ($0.key.rawValue, $0.value) }), forKey: .carbRates)
    }

    public enum DecodeFailure: Error, Hashable, Sendable {
        case notABackup
        case newerVersion(Int)
    }

    public enum Problem: Hashable, Sendable {
        case batchWithoutProduct(UUID)
        case movementWithoutBatch(UUID)
    }

    /// Deterministic bytes (sorted keys): the same data always gives the same file.
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable { var version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw DecodeFailure.notABackup }
        guard header.version <= currentVersion else { throw DecodeFailure.newerVersion(header.version) }
        guard let doc = try? JSONDecoder().decode(BackupDocument.self, from: data) else { throw DecodeFailure.notABackup }
        return doc
    }

    /// Broken references. An import must not start with these.
    public var problems: [Problem] {
        let productIDs = Set(products.map(\.id)), batchIDs = Set(batches.map(\.id))
        return batches.filter { !productIDs.contains($0.productID) }.map { .batchWithoutProduct($0.id) }
            + movements.filter { !batchIDs.contains($0.batchID) }.map { .movementWithoutBatch($0.id) }
    }

    public struct ImportPlan: Hashable, Sendable {
        public var products: [ProductInfo]
        public var batches: [BatchInfo]
        public var movements: [Movement]
        public var sessions: [PlannedSession]
        public var template: [WeeklyTemplateEntry]
        public var isEmpty: Bool { products.isEmpty && batches.isEmpty && movements.isEmpty && sessions.isEmpty && template.isEmpty }
    }

    /// What is new compared to the data already on the device (by ID, so a second import adds nothing).
    public func importPlan(knownProducts: Set<UUID>, knownBatches: Set<UUID>, knownMovements: Set<UUID>,
                           knownSessions: Set<UUID>, knownTemplate: Set<UUID>) -> ImportPlan {
        ImportPlan(products: products.filter { !knownProducts.contains($0.id) },
                   batches: batches.filter { !knownBatches.contains($0.id) },
                   movements: movements.filter { !knownMovements.contains($0.id) },
                   sessions: sessions.filter { !knownSessions.contains($0.id) },
                   template: template.filter { !knownTemplate.contains($0.id) })
    }
}

/// Doppelt angelegte Produkte (zwei Geräte, kein Unique-Constraint, 9.3).
public enum DuplicateProducts {
    static func normalised(_ s: String?) -> String {
        (s ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Groups of at least two non-archived products with the same name, brand, flavor and additives (ignoring case, accents, spacing).
    public static func groups(in products: [ProductInfo]) -> [[ProductInfo]] {
        var order: [String] = []
        var byKey: [String: [ProductInfo]] = [:]
        for p in products where !p.isArchived {
            let key = normalised(p.name) + "|" + normalised(p.brand) + "|" + normalised(p.flavor) + "|\(p.hasCaffeine)|\(p.hasLactate)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(p)
        }
        return order.compactMap { byKey[$0].flatMap { $0.count > 1 ? $0 : nil } }
    }

    /// Batches keep their quantities (base units), so both products must count in the same unit with the same
    /// carbs per base unit; otherwise stock would silently change its meaning.
    public static func canMerge(_ source: ProductInfo, into target: ProductInfo) -> Bool {
        source.id != target.id && source.baseUnit == target.baseUnit
            && abs(source.carbsPerBaseUnit - target.carbsPerBaseUnit) < 1e-9
    }
}
