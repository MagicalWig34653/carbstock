import Foundation
import SwiftData

/// Builds the two-store container (spec 9.1, 11.5).
///
/// - Inventory  → private CloudKit database `iCloud.de.linolaske.carbstock`
/// - Training   → local only (O-01 option B)
/// - Imports    → local only, excluded from backups (Apple Health workouts, never CloudKit)
///
/// If CloudKit cannot be set up (no iCloud account, missing entitlement in the simulator, tests),
/// the app falls back to a purely local inventory store and shows that state (spec 9.5, AC-S2).
enum Stores {
    static let cloudContainerID = "iCloud.de.linolaske.carbstock"

    static let inventoryTypes: [any PersistentModel.Type] = [
        Product.self, Batch.self, StockMovement.self, ShoppingListItem.self, PurchaseEvaluation.self,
    ]
    static let trainingTypes: [any PersistentModel.Type] = [
        TrainingSession.self, WeeklyTemplateRecord.self, CarbRateOverride.self, PackList.self, PackListItem.self,
    ]

    static let importTypes: [any PersistentModel.Type] = [ImportedActivity.self, ActivityPairDecision.self]

    enum SyncMode: Equatable, Sendable {
        case iCloud
        case localOnly(reason: String)
        case inMemory
    }

    struct Built {
        let container: ModelContainer
        let syncMode: SyncMode
    }

    static func make(inMemory: Bool) -> Built {
        let schema = Schema(inventoryTypes + trainingTypes + importTypes)
        if inMemory {
            // swiftlint:disable:next force_try
            let container = try! container(schema: schema, inventoryCloud: false, inMemory: true)
            return Built(container: container, syncMode: .inMemory)
        }
        // Without the entitlement (unsigned simulator builds) CloudKit traps instead of throwing.
        // A missing iCloud ACCOUNT is fine: the mirroring store works locally and syncs after sign-in.
        guard cloudKitEnabledInBuild else {
            // swiftlint:disable:next force_try
            let local = try! container(schema: schema, inventoryCloud: false, inMemory: false)
            return Built(container: local, syncMode: .localOnly(reason: "CloudKit in diesem Build abgeschaltet"))
        }
        do {
            return Built(container: try container(schema: schema, inventoryCloud: true, inMemory: false), syncMode: .iCloud)
        } catch {
            do {
                let local = try container(schema: schema, inventoryCloud: false, inMemory: false)
                return Built(container: local, syncMode: .localOnly(reason: String(describing: error)))
            } catch {
                fatalError("CarbStock: local store cannot be opened: \(error)")
            }
        }
    }

    static var cloudKitEnabledInBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "CarbStockCloudKitEnabled") as? String)?.uppercased() == "YES"
    }

    private static func container(schema: Schema, inventoryCloud: Bool, inMemory: Bool) throws -> ModelContainer {
        // Both configurations keep their own file name so a later switch of the training store
        // to CloudKit (O-01 option A) does not touch the inventory file.
        let inventory = ModelConfiguration(
            "Inventory",
            schema: Schema(inventoryTypes),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inventoryCloud ? .private(cloudContainerID) : .none
        )
        let training = ModelConfiguration(
            "Training",
            schema: Schema(trainingTypes),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        let imports: ModelConfiguration
        if inMemory {
            imports = ModelConfiguration("Imports", schema: Schema(importTypes), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            imports = ModelConfiguration("Imports", schema: Schema(importTypes), url: try importsStoreURL(), cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [inventory, training, imports])
    }

    /// Own folder, marked as excluded from device backups: imported workouts are derived from Apple Health
    /// and can be read again from there (docs/TRAININGSQUELLEN.md).
    private static func importsStoreURL() throws -> URL {
        var dir = URL.applicationSupportDirectory.appending(path: "Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        return dir.appending(path: "Imports.store")
    }
}
