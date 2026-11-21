import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// A ModelContext does not keep its container alive; tests hold the containers until the process ends.
@MainActor private var retainedContainers: [ModelContainer] = []

@MainActor
@Suite struct BackupServiceTests {
    let day = CalendarDay(year: 2026, month: 11, day: 23)

    func make() -> (ModelContext, InventoryService, TrainingService, BackupService) {
        let container = Stores.make(inMemory: true).container
        retainedContainers.append(container)
        let context = container.mainContext
        let d = CalendarDay(year: 2026, month: 11, day: 23)
        return (context, InventoryService(context: context, today: { d }), TrainingService(context: context, today: { d }),
                BackupService(context: context))
    }

    @discardableResult
    func product(_ inv: InventoryService, _ name: String, qty: Int = 10, carbs: Double = 25) throws -> Product {
        var d = ProductDraft()
        d.name = name; d.brand = "Maurten"; d.category = .gel; d.baseUnit = .piece; d.carbsPerPortionG = carbs; d.quantity = qty
        return try inv.createProduct(d)
    }

    func seed(_ inv: InventoryService, _ training: TrainingService) throws {
        let p = try product(inv, "Gel")
        try inv.removeFEFO(quantity: 2, from: p)
        var s = SessionDraft(day: day); s.type = .long; s.durationMinutes = 240
        _ = try training.addSession(s)
        try training.setRate(85, for: .long)
    }

    // AC-S7: Export und Import auf einem leeren Gerät ergeben denselben Stand
    @Test func exportThenImportRestoresEverything() throws {
        let (_, inv, training, backup) = make()
        try seed(inv, training)
        let data = try backup.exportData()

        let (ctx2, inv2, training2, backup2) = make()
        let result = try backup2.importBackup(data)
        #expect(result.products == 1 && result.batches == 1 && result.movements == 2 && result.sessions == 1 && result.rates == 1)
        let p = try #require(try ctx2.fetch(FetchDescriptor<Product>()).first)
        #expect(inv2.stock(of: p) == 8)
        #expect(training2.sessions().count == 1 && training2.userRates()[.long] == 85)
        #expect(try backup2.exportData() == data || backup2.document().products == backup.document().products)
    }

    // Import ist idempotent
    @Test func secondImportAddsNothing() throws {
        let (_, inv, training, backup) = make()
        try seed(inv, training)
        let data = try backup.exportData()
        let (ctx2, inv2, _, backup2) = make()
        try backup2.importBackup(data)
        #expect(backup2.preview(data) == .ok(newItems: 0))
        let again = try backup2.importBackup(data)
        #expect(again.total == 0)
        let p = try #require(try ctx2.fetch(FetchDescriptor<Product>()).first)
        #expect(inv2.stock(of: p) == 8, "Bestand darf sich durch den zweiten Import nicht verdoppeln")
    }

    @Test func importingIntoSameDeviceChangesNothing() throws {
        let (_, inv, training, backup) = make()
        try seed(inv, training)
        let data = try backup.exportData()
        #expect(try backup.importBackup(data).total == 0)
    }

    @Test func rejectsGarbageAndNewerVersions() throws {
        let (_, _, _, backup) = make()
        #expect(backup.preview(Data("kein json".utf8)) == .invalid(.notABackup))
        var doc = backup.document()
        doc.version = BackupDocument.currentVersion + 1
        #expect(throws: BackupService.Failure.newerVersion(BackupDocument.currentVersion + 1)) { try backup.importBackup(try doc.encoded()) }
    }

    @Test func brokenBackupImportsNothing() throws {
        let (ctx, inv, training, backup) = make()
        try seed(inv, training)
        var doc = backup.document()
        doc.batches[0].productID = UUID()
        let (ctx2, _, _, backup2) = make()
        #expect(throws: BackupService.Failure.brokenReferences(1)) { try backup2.importBackup(try doc.encoded()) }
        #expect(try ctx2.fetch(FetchDescriptor<Product>()).isEmpty)
        _ = ctx
    }

    // AC-S4: Zusammenführen
    @Test func mergeMovesBatchesAndArchivesSource() throws {
        let (ctx, inv, _, backup) = make()
        let a = try product(inv, "Energy Gel", qty: 5)
        let b = try product(inv, "energy  gel", qty: 7)
        let groups = backup.duplicateGroups()
        #expect(groups.count == 1 && groups[0].count == 2)
        try backup.merge(b, into: a)
        #expect(inv.stock(of: a) == 12 && inv.stock(of: b) == 0)
        #expect(b.isArchived && !a.isArchived)
        #expect(backup.duplicateGroups().isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<StockMovement>()).count == 2, "Buchungen bleiben unverändert")
    }

    @Test func mergeRefusesDifferentCarbs() throws {
        let (_, inv, _, backup) = make()
        let a = try product(inv, "Gel", carbs: 25)
        let b = try product(inv, "Gel", carbs: 40)
        #expect(throws: BackupService.Failure.cannotMerge) { try backup.merge(b, into: a) }
        #expect(!b.isArchived)
    }

    // AC-D3
    @Test func deleteAllRemovesEveryRecord() throws {
        let (ctx, inv, training, backup) = make()
        try seed(inv, training)
        try backup.deleteAllData()
        #expect(try ctx.fetch(FetchDescriptor<Product>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<StockMovement>()).isEmpty)
        #expect(training.sessions().isEmpty && training.userRates().isEmpty)
        #expect(backup.document().products.isEmpty)
    }
}

@Suite struct SyncPresentationTests {
    // AC-S2: ohne iCloud-Konto klare Anzeige, kein Absturz
    @Test func accountProblemsAreShown() {
        func p(_ a: AccountState) -> SyncPresentation { .make(mode: .iCloud, account: a, lastSync: nil, lastError: nil) }
        #expect(p(.noAccount).isProblem && p(.noAccount).title.contains("iCloud angemeldet"))
        #expect(p(.restricted).isProblem && p(.temporarilyUnavailable).isProblem && p(.unknown).isProblem)
        #expect(!p(.available).isProblem && !p(.notChecked).isProblem)
    }

    @Test func localAndTestModes() {
        let local = SyncPresentation.make(mode: .localOnly(reason: "x"), account: .notChecked, lastSync: nil, lastError: nil)
        #expect(local.isProblem && local.symbol == "icloud.slash")
        #expect(!SyncPresentation.make(mode: .inMemory, account: .notChecked, lastSync: nil, lastError: nil).isProblem)
    }

    @Test func errorAndLastSync() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ok = SyncPresentation.make(mode: .iCloud, account: .available, lastSync: now.addingTimeInterval(-3600), lastError: nil, now: now)
        #expect(!ok.isProblem && ok.detail?.hasPrefix("Letzte Änderung abgeglichen") == true)
        let none = SyncPresentation.make(mode: .iCloud, account: .available, lastSync: nil, lastError: nil)
        #expect(none.detail == "Noch keine Änderung abgeglichen.")
        let bad = SyncPresentation.make(mode: .iCloud, account: .available, lastSync: now, lastError: "Fehler")
        #expect(bad.isProblem && bad.detail == "Fehler")
    }
}
