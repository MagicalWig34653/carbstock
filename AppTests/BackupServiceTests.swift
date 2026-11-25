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

    // Geschmacksrichtungen: Export, Import, Doppelerkennung
    @Test func flavorSurvivesExportImportAndOldBackupsStillImport() throws {
        let (_, inv, _, backup) = make()
        var d = ProductDraft()
        d.name = "Gel"; d.brand = "Maurten"; d.flavor = "  Zitrone "; d.carbsPerPortionG = 25; d.quantity = 4
        let p = try inv.createProduct(d)
        #expect(p.flavor == "Zitrone")
        let data = try backup.exportData()
        #expect(String(decoding: data, as: UTF8.self).contains("Zitrone"))

        let (ctx2, _, _, backup2) = make()
        try backup2.importBackup(data)
        #expect(try ctx2.fetch(FetchDescriptor<Product>()).first?.flavor == "Zitrone")

        // Alte Sicherung: ohne Geschmack, Produkt wird ohne Geschmack angelegt
        let (_, inv3, _, backup3) = make()
        var plain = ProductDraft(); plain.name = "Riegel"; plain.carbsPerPortionG = 30; plain.quantity = 1
        try inv3.createProduct(plain)
        let old = try backup3.exportData()
        #expect(!String(decoding: old, as: UTF8.self).contains("flavor"))
        let (ctx4, _, _, backup4) = make()
        try backup4.importBackup(old)
        #expect(try ctx4.fetch(FetchDescriptor<Product>()).first?.flavor == nil)
    }

    @Test func additivesSurviveExportImportAndOldBackupsStillImport() throws {
        let (_, inv, _, backup) = make()
        var d = ProductDraft()
        d.name = "Gel"; d.carbsPerPortionG = 25; d.quantity = 4; d.hasCaffeine = true; d.hasLactate = true
        try inv.createProduct(d)
        var plain = ProductDraft(); plain.name = "Riegel"; plain.carbsPerPortionG = 30; plain.quantity = 1
        try inv.createProduct(plain)
        let data = try backup.exportData()
        let (ctx2, _, _, backup2) = make()
        try backup2.importBackup(data)
        let products = try ctx2.fetch(FetchDescriptor<Product>())
        #expect(products.first { $0.name == "Gel" }.map { $0.hasCaffeine && $0.hasLactate } == true)
        #expect(products.first { $0.name == "Riegel" }.map { !$0.hasCaffeine && !$0.hasLactate } == true)

        // Sicherung aus der Version ohne Zusätze: Felder fehlen, beide gelten als „nein“
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"hasCaffeine\"", with: "\"x1\"")
            .replacingOccurrences(of: "\"hasLactate\"", with: "\"x2\"")
        let (ctx3, _, _, backup3) = make()
        try backup3.importBackup(Data(text.utf8))
        #expect(try ctx3.fetch(FetchDescriptor<Product>()).allSatisfy { !$0.hasCaffeine && !$0.hasLactate })
    }

    // G1 / AC-S7: auch Bezugsquelle, Buchungsnotiz und Titel/Notiz/Startzeit der Session überleben die Sicherung
    @Test func freeTextFieldsSurviveExportImport() throws {
        let (ctx, inv, training, backup) = make()
        let p = try product(inv, "Gel")
        let batch = try #require(p.batches?.first)
        batch.source = "Black Friday"
        try inv.adjust(by: -1, on: batch, note: "Inventur")
        _ = try training.addSession(SessionDraft(day: day))
        let session = try #require(training.sessions().first)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.title = "Lange Runde"; session.note = "Flaschen vorbereiten"; session.startTime = start
        try ctx.save()
        let data = try backup.exportData()

        let (ctx2, _, training2, backup2) = make()
        try backup2.importBackup(data)
        #expect(try ctx2.fetch(FetchDescriptor<Batch>()).first?.source == "Black Friday")
        #expect(try ctx2.fetch(FetchDescriptor<StockMovement>()).compactMap(\.note) == ["Inventur"])
        let restored = try #require(training2.sessions().first)
        #expect(restored.title == "Lange Runde" && restored.note == "Flaschen vorbereiten" && restored.startTime == start)

        // Ältere Sicherung ohne diese Felder: importiert wie bisher, die Felder bleiben leer
        var text = String(decoding: data, as: UTF8.self)
        for key in ["source", "note", "title", "startTime"] { text = text.replacingOccurrences(of: "\"\(key)\"", with: "\"x_\(key)\"") }
        let (ctx3, _, training3, backup3) = make()
        try backup3.importBackup(Data(text.utf8))
        #expect(try ctx3.fetch(FetchDescriptor<Batch>()).first?.source == nil)
        #expect(training3.sessions().first?.title == nil)
    }

    @Test func twoFlavorsOfOneProductAreNoDuplicates() throws {
        let (_, inv, _, backup) = make()
        for f in ["Zitrone", "Cola"] {
            var d = ProductDraft(); d.name = "Gel"; d.brand = "Maurten"; d.flavor = f; d.carbsPerPortionG = 25; d.quantity = 2
            try inv.createProduct(d)
        }
        #expect(backup.duplicateGroups().isEmpty)
        var third = ProductDraft(); third.name = "Gel"; third.brand = "Maurten"; third.flavor = "zitrone"; third.carbsPerPortionG = 25; third.quantity = 1
        try inv.createProduct(third)
        #expect(backup.duplicateGroups().count == 1)
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
