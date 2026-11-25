#if DEBUG
import CoreData
import Foundation
import Testing
@testable import CarbStock

/// `cloudkit/schema.ckdb` (wird per `cktool import-schema` nach Development importiert) passt Feld für Feld und Typ
/// für Typ zum Inventory-Modell. Abbildung nach Apple, „Reading CloudKit Records for Core Data“. Felder und Typen sind
/// nach der Production-Promotion unveränderlich, deshalb ist die Prüfung exakt.
@MainActor
@Suite struct CloudKitSchemaFileTests {
    /// {Satztyp: {Feld: Typ}} ohne die Systemfelder (`___…`).
    static func parse(_ text: String) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        var current: String?
        for line in text.split(separator: "\n") {
            let words = line.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            guard let first = words.first else { continue }
            if first == "RECORD", words.count > 2 { current = words[2]; out[words[2]] = [:] }
            else if first == ");" { current = nil }
            else if let current, first != "GRANT", !first.hasPrefix("\"___"), words.count > 1 {
                out[current]?[first] = words[1]
            }
        }
        return out
    }

    static func expected(_ model: NSManagedObjectModel) throws -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for entity in model.entities {
            let name = try #require(entity.name)
            var fields = ["CD_entityName": "STRING"]
            for (attribute, description) in entity.attributesByName {
                let type: String
                var variableLength = false
                switch description.attributeType {
                case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType, .booleanAttributeType: type = "INT64"
                case .doubleAttributeType, .floatAttributeType: type = "DOUBLE"
                case .dateAttributeType: type = "TIMESTAMP"
                case .UUIDAttributeType: type = "STRING"
                case .stringAttributeType: type = "STRING"; variableLength = true
                case .binaryDataAttributeType: type = "BYTES"; variableLength = true
                default:
                    Issue.record("\(name).\(attribute): Typ \(description.attributeType.rawValue) nicht vorgesehen")
                    continue
                }
                fields["CD_\(attribute)"] = type
                if variableLength { fields["CD_\(attribute)_ckAsset"] = "ASSET" }
            }
            // To-one: Datensatzname des Ziels als Text. To-many steht nur auf der Gegenseite.
            for (relationship, description) in entity.relationshipsByName where !description.isToMany {
                fields["CD_\(relationship)"] = "STRING"
            }
            out["CD_\(name)"] = fields
        }
        return out
    }

    static func schemaFile() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("cloudkit/schema.ckdb"), encoding: .utf8)
    }

    @Test func schemaFileMatchesTheInventoryModelExactly() throws {
        var file = Self.parse(try Self.schemaFile())
        #expect(file.removeValue(forKey: "Users") != nil, "Der Systemtyp Users gehört in die Datei, sonst will der Import ihn ändern")
        let want = try Self.expected(CloudKitSchemaTool.inventoryModel())
        #expect(file.keys.sorted() == want.keys.sorted())
        for (recordType, fields) in want {
            #expect(file[recordType] == fields, "\(recordType)")
        }
    }

    /// Stichproben gegen Fehler in der Ableitung selbst.
    @Test func theMappingFollowsApplesRules() throws {
        let want = try Self.expected(CloudKitSchemaTool.inventoryModel())
        #expect(want["CD_StockMovement"]?["CD_batch"] == "STRING")
        #expect(want["CD_StockMovement"]?["CD_deviceID"] == "STRING")
        #expect(want["CD_StockMovement"]?["CD_deviceID_ckAsset"] == "ASSET")
        #expect(want["CD_Batch"]?["CD_id"] == "STRING" && want["CD_Batch"]?["CD_id_ckAsset"] == nil)
        #expect(want["CD_Product"]?["CD_isArchived"] == "INT64")
        #expect(want["CD_Product"]?["CD_carbsPerPortionG"] == "DOUBLE")
        #expect(want["CD_Product"]?["CD_batches"] == nil)
        #expect(want["CD_ShoppingListItem"]?["CD_offerJSON"] == "BYTES")
        #expect(want["CD_PurchaseEvaluation"]?["CD_createdAt"] == "TIMESTAMP")
    }
}
#endif
