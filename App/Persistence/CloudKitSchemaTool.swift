#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData

/// DEBUG-Werkzeug (Gate G1): legt das Development-Schema des CloudKit-Containers vollständig an,
/// damit die Production-Promotion in der CloudKit-Konsole alle Satztypen und Felder findet.
/// Ohne diesen Schritt entstehen Satztypen nur durch tatsächlich gespeicherte Werte; nie belegte Felder fehlen.
///
/// Sicherungen gegen Fehlbedienung:
///  - nur im DEBUG-Build, nur mit Startargument `-CarbStockCloudKitSchema`, nie automatisch (erst Knopfdruck)
///  - nur die fünf Inventory-Typen (Training und Imports verlassen das Gerät nie)
///  - arbeitet auf einem Wegwerf-Speicher im temporären Ordner, nie auf dem echten Speicher; der Ordner wird danach gelöscht
///  - schreibt nur das Schema (Satztypen und Felder), keine Nutzerdaten
///  - ohne iCloud-Berechtigung (unsignierter Build) oder ohne iCloud-Konto wird abgelehnt
enum CloudKitSchemaTool {
    static let launchArgument = "-CarbStockCloudKitSchema"

    enum Outcome: Equatable, Sendable {
        case done(recordTypes: [String])
        case refused(String)
        case failed(String)
    }

    /// Alles, was von außen kommt, damit Tests es ersetzen können (kein echter CloudKit-Aufruf im Test).
    struct Environment: Sendable {
        var cloudKitEnabled: Bool
        var account: @Sendable () async -> AccountState
        var initialize: @Sendable (NSManagedObjectModel, URL) throws -> Void

        static var live: Environment {
            .init(cloudKitEnabled: Stores.cloudKitEnabledInBuild,
                  account: { AccountState((try? await CKContainer(identifier: Stores.cloudContainerID).accountStatus()) ?? .couldNotDetermine) },
                  initialize: { model, url in try CloudKitSchemaTool.initializeSchema(model: model, storeURL: url, options: []) })
        }
    }

    static func isRequested(_ arguments: [String]) -> Bool { arguments.contains(launchArgument) }

    /// Das Core-Data-Modell, das SwiftData für die Inventory-Konfiguration aufbaut: alle Felder, auch nie beschriebene.
    static func inventoryModel() throws -> NSManagedObjectModel {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: Stores.inventoryTypes) else {
            throw SchemaToolError.noModel
        }
        return model
    }

    enum SchemaToolError: Error, LocalizedError {
        case noModel
        var errorDescription: String? { "Das Modell konnte nicht aufgebaut werden." }
    }

    static func recordTypes(of model: NSManagedObjectModel) -> [String] {
        model.entities.compactMap(\.name).map { "CD_" + $0 }.sorted()
    }

    static func run(_ environment: Environment) async -> Outcome {
        guard environment.cloudKitEnabled else {
            return .refused("Dieser Build hat keine iCloud-Berechtigung (unsigniert oder CloudKit abgeschaltet). Mit Apple-ID signiert auf einem Gerät oder Simulator mit iCloud-Konto starten.")
        }
        switch await environment.account() {
        case .available: break
        case .noAccount: return .refused("Auf diesem Gerät ist kein iCloud-Konto angemeldet.")
        case .restricted: return .refused("Das iCloud-Konto ist auf diesem Gerät eingeschränkt.")
        case .temporarilyUnavailable: return .refused("iCloud ist vorübergehend nicht verfügbar. Später erneut versuchen.")
        case .unknown, .notChecked: return .refused("Der iCloud-Kontostatus ist nicht feststellbar. Später erneut versuchen.")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "CarbStockSchema-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let model = try inventoryModel()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try environment.initialize(model, folder.appending(path: "Schema.store"))
            return .done(recordTypes: recordTypes(of: model))
        } catch {
            let ns = error as NSError
            return .failed("\(ns.domain) \(ns.code): \(ns.localizedDescription)")
        }
    }

    /// Der eigentliche Aufruf. Blockiert, bis CloudKit fertig ist; `options` `.dryRun` lädt nichts hoch.
    static func initializeSchema(model: NSManagedObjectModel, storeURL: URL,
                                 options: NSPersistentCloudKitContainerSchemaInitializationOptions) throws {
        let container = NSPersistentCloudKitContainer(name: "CarbStockSchema", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Stores.cloudContainerID)
        container.persistentStoreDescriptions = [description]
        let loaded = LoadResult()
        container.loadPersistentStores { _, error in loaded.finish(error) }
        try loaded.wait()
        defer { container.persistentStoreCoordinator.persistentStores.forEach { try? container.persistentStoreCoordinator.remove($0) } }
        try container.initializeCloudKitSchema(options: options)
    }

    private final class LoadResult: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private var error: (any Error)?
        func finish(_ error: (any Error)?) { self.error = error; semaphore.signal() }
        func wait() throws {
            semaphore.wait()
            if let error { throw error }
        }
    }
}
#endif
