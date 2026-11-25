#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// DEBUG-Werkzeug: Development-Schema des Containers vollständig anlegen (vor der Production-Promotion, G1).
/// Es läuft nur mit Startargument und Knopfdruck, nur für die Inventory-Modelle und nie auf dem echten Speicher.
@MainActor
@Suite struct CloudKitSchemaToolTests {
    /// Merkt sich, womit das Werkzeug `initializeCloudKitSchema` aufgerufen hätte.
    private final class Recorder: @unchecked Sendable {
        var calls = 0
        var entities: [String] = []
        var storeURL: URL?
        var folderExisted = false
    }

    private func environment(_ r: Recorder, cloudKit: Bool = true, account: AccountState = .available,
                             error: (any Error)? = nil) -> CloudKitSchemaTool.Environment {
        .init(cloudKitEnabled: cloudKit, account: { account }, initialize: { model, url in
            r.calls += 1
            r.entities = model.entities.compactMap(\.name).sorted()
            r.storeURL = url
            r.folderExisted = FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
            if let error { throw error }
        })
    }

    @Test func onlyTheLaunchArgumentSwitchesItOn() {
        #expect(!CloudKitSchemaTool.isRequested([]))
        #expect(!CloudKitSchemaTool.isRequested(["CarbStock", "-CarbStockInMemory", "-CarbStockSampleData"]))
        #expect(CloudKitSchemaTool.isRequested(["CarbStock", "-CarbStockCloudKitSchema"]))
    }

    /// Das Modell für CloudKit enthält genau die fünf Inventory-Typen mit allen Feldern, auch nie beschriebene.
    @Test func modelHoldsExactlyTheInventoryTypesWithEveryField() throws {
        let model = try CloudKitSchemaTool.inventoryModel()
        let entities = Dictionary(uniqueKeysWithValues: model.entities.map { ($0.name ?? "", $0) })
        #expect(entities.keys.sorted() == ["Batch", "Product", "PurchaseEvaluation", "ShoppingListItem", "StockMovement"])
        for entity in Schema(Stores.inventoryTypes).entities {
            let found = try #require(entities[entity.name])
            let expected = Set(entity.attributes.map(\.name) + entity.relationships.map(\.name))
            #expect(Set(found.propertiesByName.keys) == expected, "\(entity.name)")
        }
        #expect(entities["StockMovement"]?.attributesByName["deviceID"] != nil)
    }

    @Test func refusesABuildWithoutCloudKit() async {
        let r = Recorder()
        let outcome = await CloudKitSchemaTool.run(environment(r, cloudKit: false))
        #expect(r.calls == 0)
        guard case .refused(let reason) = outcome else { Issue.record("\(outcome)"); return }
        #expect(reason.contains("iCloud-Berechtigung"))
    }

    @Test(arguments: [AccountState.noAccount, .restricted, .temporarilyUnavailable, .unknown])
    func refusesWithoutAnICloudAccount(account: AccountState) async {
        let r = Recorder()
        let outcome = await CloudKitSchemaTool.run(environment(r, account: account))
        #expect(r.calls == 0)
        guard case .refused(let reason) = outcome else { Issue.record("\(outcome)"); return }
        #expect(reason.contains("iCloud"))
    }

    @Test func initializesOnceOnAThrowawayStoreAndRemovesIt() async throws {
        let r = Recorder()
        let outcome = await CloudKitSchemaTool.run(environment(r))
        #expect(r.calls == 1)
        #expect(outcome == .done(recordTypes: ["CD_Batch", "CD_Product", "CD_PurchaseEvaluation", "CD_ShoppingListItem", "CD_StockMovement"]))
        #expect(r.entities == ["Batch", "Product", "PurchaseEvaluation", "ShoppingListItem", "StockMovement"])
        let url = try #require(r.storeURL)
        // Nie der echte Speicher: eigener Ordner im temporären Verzeichnis, danach weg.
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(url.lastPathComponent != "Inventory.store")
        #expect(r.folderExisted)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test func reportsAFailureAndStillCleansUp() async throws {
        let r = Recorder()
        let error = NSError(domain: "CKErrorDomain", code: 9, userInfo: [NSLocalizedDescriptionKey: "Not Authenticated"])
        let outcome = await CloudKitSchemaTool.run(environment(r, error: error))
        guard case .failed(let message) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("CKErrorDomain 9") && message.contains("Not Authenticated"))
        let url = try #require(r.storeURL)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
}

/// Bewusst ohne `@MainActor`: `initializeCloudKitSchema` blockiert und darf (wie im Werkzeug) nicht auf dem Main-Thread laufen.
@Suite struct CloudKitSchemaDryRunTests {
    /// Echter Aufruf von `initializeCloudKitSchema` als Trockenlauf (lädt nichts hoch). Braucht einen signierten Build
    /// mit iCloud-Berechtigung UND ein angemeldetes iCloud-Konto im Simulator oder auf dem Gerät, sonst läuft CloudKit nach 30 s
    /// in den Timeout. Beobachtet am 25.11. im Simulator „CarbStock iPhone“: CKAccountStatus 3 (kein Konto). Deshalb nur auf Wunsch:
    /// `TEST_RUNNER_CARBSTOCK_SCHEMA_DRYRUN=1` plus `CODE_SIGNING_ALLOWED=YES CARBSTOCK_CLOUDKIT=YES`.
    @Test(.enabled(if: Stores.cloudKitEnabledInBuild && ProcessInfo.processInfo.environment["CARBSTOCK_SCHEMA_DRYRUN"] == "1",
                   "nur auf Wunsch, im signierten Build mit iCloud-Konto"))
    func dryRunWithTheRealCloudKitContainer() async throws {
        let account = try await CKContainer(identifier: Stores.cloudContainerID).accountStatus()
        try #require(account == .available, "Kein nutzbares iCloud-Konto (CKAccountStatus \(account.rawValue))")
        let folder = FileManager.default.temporaryDirectory.appending(path: "SchemaDryRun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try CloudKitSchemaTool.initializeSchema(model: CloudKitSchemaTool.inventoryModel(),
                                                storeURL: folder.appending(path: "Schema.store"),
                                                options: [.dryRun, .printSchema])
    }
}
#endif
