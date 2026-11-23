import SwiftData
import Foundation
import Testing
@testable import CarbStock

/// CloudKit schema rules (spec 9.2) and privacy rule AC-D4, checked by introspecting the real schema.
@Suite struct SchemaRulesTests {
    static let inventory = Schema(Stores.inventoryTypes)
    static let training = Schema(Stores.trainingTypes)
    static let imports = Schema(Stores.importTypes)
    static let all = Schema(Stores.inventoryTypes + Stores.trainingTypes + Stores.importTypes)

    @Test func noUniqueConstraints() {
        for entity in Self.all.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has uniqueness constraints")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
            }
        }
    }

    // Schema.Attribute does not expose default values, so a "has a default" check is not possible
    // by introspection. What CloudKit needs is "optional or default": checked here as far as visible
    // (relationships must be optional with an inverse and no .deny); defaults are exercised by
    // StoresTests, which saves models created through their initialisers.
    @Test func relationshipsAreOptionalWithInverseAndNotDeny() {
        for entity in Self.all.entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) is not optional")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) has no inverse")
                #expect(relationship.deleteRule != .deny, "\(entity.name).\(relationship.name) uses .deny")
            }
        }
    }

    @Test func noForbiddenFieldNames() {
        let forbidden = ["weight", "pulse", "heart", "power", "watt", "ftp", "calorie",
                         "location", "latitude", "longitude", "health"]
        for entity in Self.all.entities {
            let names = [entity.name] + entity.attributes.map(\.name) + entity.relationships.map(\.name)
            for name in names {
                for word in forbidden {
                    #expect(!name.lowercased().contains(word), "\(entity.name): '\(name)' contains '\(word)' (AC-D4)")
                }
            }
        }
    }

    @Test func trainingTypesAreNotInInventoryConfiguration() {
        let inventoryNames = Set(Self.inventory.entities.map(\.name))
        let trainingNames = Set(Self.training.entities.map(\.name))
        #expect(!trainingNames.isEmpty)
        #expect(inventoryNames.isDisjoint(with: trainingNames))
        // No relationship may cross configurations.
        for entity in Self.training.entities {
            for relationship in entity.relationships {
                #expect(trainingNames.contains(relationship.destination), "\(entity.name) points outside Training")
            }
        }
        for entity in Self.inventory.entities {
            for relationship in entity.relationships {
                #expect(inventoryNames.contains(relationship.destination), "\(entity.name) points outside Inventory")
            }
        }
    }

    /// Imports (Apple Health copies) live in their own local configuration: no overlap, no relationships (AC-X1).
    @Test func importTypesAreSeparateAndStoreOnlyAllowedFields() throws {
        let importNames = Set(Self.imports.entities.map(\.name))
        #expect(importNames == ["ImportedActivity", "ActivityPairDecision"])
        #expect(importNames.isDisjoint(with: Self.inventory.entities.map(\.name)))
        #expect(importNames.isDisjoint(with: Self.training.entities.map(\.name)))
        for entity in Self.imports.entities { #expect(entity.relationships.isEmpty, "\(entity.name) hat Beziehungen") }
        let activity = try #require(Self.imports.entities.first { $0.name == "ImportedActivity" })
        let allowed: Set<String> = ["id", "sourceRaw", "externalID", "start", "movingSeconds", "elapsedSeconds", "sportRaw", "title",
                                    "isIgnored", "isMissingAtSource", "suggestionHandled", "linkedSessionID", "importedAt", "schemaVersion"]
        #expect(Set(activity.attributes.map(\.name)) == allowed)
    }

    /// Geschmack: ein neues optionales Feld am Produkt, alle bisherigen Felder bleiben.
    @Test func flavorFieldIsAdditiveAndOptional() throws {
        let entity = try #require(Self.inventory.entities.first { $0.name == "Product" })
        let attributes = Dictionary(uniqueKeysWithValues: entity.attributes.map { ($0.name, $0) })
        #expect(attributes["flavor"]?.isOptional == true)
        for name in ["id", "name", "brand", "categoryRaw", "baseUnitRaw", "portionAmount", "carbsPerPortionG", "glucoseFructoseRatio",
                     "isArchived", "createdAt", "updatedAt", "schemaVersion"] {
            #expect(attributes[name] != nil, "Product.\(name) fehlt")
        }
    }

    /// Koffein-/Laktatzusatz: zwei neue Felder am Produkt, nichts umbenannt; ein neues Produkt startet mit „nein“.
    @Test func additiveFieldsExistAndDefaultToNo() throws {
        let entity = try #require(Self.inventory.entities.first { $0.name == "Product" })
        let names = Set(entity.attributes.map(\.name))
        #expect(names.contains("hasCaffeine") && names.contains("hasLactate") && names.contains("flavor"))
        let p = Product(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        #expect(!p.hasCaffeine && !p.hasLactate)
    }

    /// M4b: `CarbRateOverride.updatedAt` ist additiv (Vorgabewert), nichts Bestehendes fällt weg.
    @Test func carbRateOverrideHasUpdatedAtAdditively() throws {
        let entity = try #require(Self.training.entities.first { $0.name == "CarbRateOverride" })
        let names = Set(entity.attributes.map(\.name))
        #expect(names.isSuperset(of: ["typeRaw", "carbsPerHour", "schemaVersion", "updatedAt"]))
        let before = Date.now
        #expect(CarbRateOverride(type: .z2, carbsPerHour: 60).updatedAt >= before)
    }

    /// M5 added fields to two existing records: additive means optional (or defaulted), nothing renamed or removed.
    @Test func m5FieldsAreAdditiveAndOptional() throws {
        func attributes(_ name: String) throws -> [String: Schema.Attribute] {
            let entity = try #require(Self.inventory.entities.first { $0.name == name })
            return Dictionary(uniqueKeysWithValues: entity.attributes.map { ($0.name, $0) })
        }
        let item = try attributes("ShoppingListItem")
        for name in ["expiryDay", "offerJSON", "batchID"] { #expect(item[name]?.isOptional == true, "ShoppingListItem.\(name)") }
        // unchanged since M0: the original fields are all still there
        for name in ["id", "productID", "freeText", "plannedQuantity", "estimatedTotalPriceCents", "stateRaw", "createdAt", "schemaVersion"] {
            #expect(item[name] != nil, "ShoppingListItem.\(name) fehlt")
        }
        let evaluation = try attributes("PurchaseEvaluation")
        #expect(evaluation["verdictQuantity"]?.isOptional == true)
        for name in ["id", "inputJSON", "verdictRaw", "reasonsJSON", "userDecisionRaw", "createdAt", "schemaVersion"] {
            #expect(evaluation[name] != nil, "PurchaseEvaluation.\(name) fehlt")
        }
    }
}
