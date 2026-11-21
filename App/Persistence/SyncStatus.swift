import CloudKit
import CoreData
import Foundation
import Observation

/// Zustand des iCloud-Kontos, losgelöst von CloudKit, damit die Darstellung ohne Konto testbar ist (Spec 9.5, AC-S2).
enum AccountState: Equatable, Sendable {
    case notChecked, available, noAccount, restricted, temporarilyUnavailable, unknown

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

/// Was die Einstellungen zum Abgleich anzeigen. Reine Funktion.
struct SyncPresentation: Equatable {
    var symbol: String
    var title: String
    var detail: String?
    var isProblem: Bool

    static func make(mode: Stores.SyncMode, account: AccountState, lastSync: Date?, lastError: String?,
                     now: Date = .now, formatter: RelativeDateTimeFormatter = .init()) -> SyncPresentation {
        switch mode {
        case .inMemory:
            return .init(symbol: "testtube.2", title: "Testmodus (nur im Speicher)", detail: nil, isProblem: false)
        case .localOnly:
            return .init(symbol: "icloud.slash", title: "Nicht synchronisiert",
                         detail: "iCloud ist in dieser Version der App nicht eingerichtet. Der Bestand bleibt auf diesem Gerät.",
                         isProblem: true)
        case .iCloud:
            switch account {
            case .noAccount:
                return .init(symbol: "icloud.slash", title: "Nicht bei iCloud angemeldet",
                             detail: "Melde dich in den iOS-Einstellungen bei iCloud an. Bis dahin bleibt alles auf diesem Gerät und wird später abgeglichen.",
                             isProblem: true)
            case .restricted:
                return .init(symbol: "exclamationmark.icloud", title: "iCloud ist eingeschränkt",
                             detail: "Auf diesem Gerät ist iCloud für Apps beschränkt (z. B. Bildschirmzeit oder Geräteverwaltung).",
                             isProblem: true)
            case .temporarilyUnavailable:
                return .init(symbol: "exclamationmark.icloud", title: "iCloud gerade nicht erreichbar",
                             detail: "Das ist meist vorübergehend. Die App versucht es später erneut.", isProblem: true)
            case .unknown:
                return .init(symbol: "exclamationmark.icloud", title: "iCloud-Status unbekannt",
                             detail: "Der Status konnte nicht ermittelt werden.", isProblem: true)
            case .notChecked, .available:
                if let lastError {
                    return .init(symbol: "exclamationmark.icloud", title: "Abgleich mit Fehler", detail: lastError, isProblem: true)
                }
                let detail = lastSync.map { "Letzte Änderung abgeglichen \(formatter.localizedString(for: $0, relativeTo: now))." }
                    ?? "Noch keine Änderung abgeglichen."
                return .init(symbol: "icloud", title: "Bestand wird über iCloud abgeglichen", detail: detail, isProblem: false)
            }
        }
    }
}

/// Fragt das iCloud-Konto nur ab, wenn die App mit iCloud läuft, und merkt sich die letzte Abgleichmeldung.
@MainActor @Observable
final class SyncMonitor {
    private(set) var account: AccountState = .notChecked
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    private let mode: Stores.SyncMode
    private var observer: NSObjectProtocol?

    init(mode: Stores.SyncMode) {
        self.mode = mode
    }

    func start() async {
        guard mode == .iCloud else { return }
        account = AccountState((try? await CKContainer(identifier: Stores.cloudContainerID).accountStatus()) ?? .couldNotDetermine)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            let finished = event?.endDate
            let failure = event?.error
            Task { @MainActor [weak self] in
                guard let self, let finished else { return }
                if failure == nil { self.lastSync = finished; self.lastError = nil }
                else { self.lastError = "Der letzte Abgleich ist fehlgeschlagen. Die App versucht es später erneut." }
            }
        }
    }

    var presentation: SyncPresentation {
        .make(mode: mode, account: account, lastSync: lastSync, lastError: lastError)
    }
}
