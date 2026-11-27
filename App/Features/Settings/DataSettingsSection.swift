import CarbStockCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Die Sicherung als Datei für den Dateien-Dialog.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension BackupService.Failure {
    var message: String {
        switch self {
        case .notABackup: "Das ist keine CarbStock-Sicherung."
        case .newerVersion: "Diese Sicherung stammt aus einer neueren Version der App. Bitte aktualisiere CarbStock."
        case .brokenReferences: "Die Sicherung ist unvollständig oder beschädigt. Es wurde nichts importiert."
        case .cannotMerge: "Diese Produkte lassen sich nicht zusammenführen: Einheit und Kohlenhydrate müssen gleich sein."
        }
    }
}

/// Einstellungen: Abgleichstatus, Sicherung, doppelte Produkte, alles löschen.
struct DataSettingsSection: View {
    let syncMode: Stores.SyncMode
    @Environment(\.modelContext) private var context
    @State private var monitor: SyncMonitor
    @State private var exportFile: BackupFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var message: String?

    init(syncMode: Stores.SyncMode) {
        self.syncMode = syncMode
        _monitor = State(initialValue: SyncMonitor(mode: syncMode))
    }

    private var service: BackupService { BackupService(context: context) }

    var body: some View {
        let sync = monitor.presentation
        Section {
            Label(sync.title, systemImage: sync.symbol).foregroundStyle(sync.isProblem ? Color.warning : Color.primary)
            if let detail = sync.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            Text("Trainingsdaten (Sessions, Wochenvorlage, Packlisten) bleiben auf diesem Gerät.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("iCloud") }
            .task { await monitor.start() }

        Section {
            Button("Sicherung exportieren", systemImage: "square.and.arrow.up") {
                do { exportFile = BackupFile(data: try service.exportData()); exporting = true } catch { message = "Der Export hat nicht geklappt." }
            }
            Button("Sicherung importieren", systemImage: "square.and.arrow.down") { importing = true }
            NavigationLink { DuplicateProductsView() } label: { Label("Doppelte Produkte", systemImage: "square.on.square") }
        } header: { Text("Daten") } footer: {
            Text("Die Sicherung ist eine JSON-Datei mit Vorrat, Buchungen, Einkaufsliste, Einkaufsverlauf, Sessions, Wochenvorlage und Packlisten. Ein Import fügt nur hinzu, was fehlt.")
        }

        Section {
            Button("Alle Daten löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } footer: {
            Text("Löscht Vorrat, Buchungen und Trainingsdaten auf diesem Gerät und in deiner iCloud. Das lässt sich nicht rückgängig machen.")
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: "CarbStock-Sicherung") { result in
            if case .failure = result { message = "Die Sicherung konnte nicht gespeichert werden." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { message = "Die Datei konnte nicht gelesen werden."; return }
            do {
                let r = try service.importBackup(data)
                message = CountText.importSummary(r)
            } catch let f as BackupService.Failure { message = f.message } catch { message = "Der Import hat nicht geklappt." }
        }
        .confirmationDialog("Wirklich alle Daten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Alle Daten löschen", role: .destructive) {
                do { try service.deleteAllData(); message = "Alle Daten wurden gelöscht." } catch { message = "Das Löschen hat nicht geklappt." }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Exportiere vorher eine Sicherung, wenn du die Daten behalten willst.")
        }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

/// Doppelte Produkte zusammenführen (AC-S4): Bestand wandert in das gewählte Produkt, das andere wird archiviert.
struct DuplicateProductsView: View {
    @Environment(\.modelContext) private var context
    @Query private var products: [Product]
    @State private var errorText: String?

    var body: some View {
        let service = BackupService(context: context)
        let groups = products.isEmpty ? [] : service.duplicateGroups()
        List {
            if groups.isEmpty {
                ContentUnavailableView("Keine Doppelten", systemImage: "checkmark.circle",
                                       description: Text("Produkte mit gleichem Namen und gleicher Marke erscheinen hier."))
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section(group.first?.name ?? "") {
                    ForEach(group.dropFirst()) { source in
                        let target = group[0]
                        Button {
                            do { try service.merge(source, into: target) } catch { errorText = (error as? BackupService.Failure)?.message ?? "Das hat nicht geklappt." }
                        } label: {
                            Label("In „\(target.displayName)“ (\(Self.detail(target))) zusammenführen", systemImage: "arrow.triangle.merge")
                        }
                    }
                }
            }
        }
        .navigationTitle("Doppelte Produkte")
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private static func detail(_ p: Product) -> String {
        let parts: [String?] = [p.brand, p.flavor, p.hasCaffeine ? "mit Koffein" : nil, p.hasLactate ? "mit Laktat" : nil, p.category.title]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}
