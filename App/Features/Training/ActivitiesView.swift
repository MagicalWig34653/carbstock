import CarbStockCore
import SwiftData
import SwiftUI

extension ActivityService.Outcome {
    /// Neutral wording: Apple does not tell the app whether reading was denied, so "nothing found" covers both.
    var message: String {
        switch self {
        case .imported(let r, _):
            r.inserted + r.updated == 0 ? "Alles aktuell." : "\(r.inserted) neu, \(r.updated) aktualisiert."
        case .nothingFound:
            "Keine Radfahrten gefunden. Entweder gibt es in den letzten \(ActivityService.lookbackDays) Tagen keine, oder CarbStock darf sie nicht lesen. Prüfe das unter Einstellungen › Health › Datenzugriff & Geräte › CarbStock."
        case .unavailable: "Apple Health ist auf diesem Gerät nicht verfügbar."
        case .deviceLocked: "Das Gerät ist gesperrt, Health ist dann verschlüsselt. Entsperre es und versuche es noch einmal."
        case .failed: "Das Einlesen hat nicht geklappt. Bitte versuche es später noch einmal."
        }
    }
}

/// Fahrten aus Apple Health: einlesen, Duplikate, Vorschläge „erledigt“. Alles bleibt auf diesem Gerät.
struct ActivitiesView: View {
    @Environment(\.modelContext) private var context
    @Query private var imported: [ImportedActivity]
    @Query private var decisions: [ActivityPairDecision]
    @Query private var sessions: [TrainingSession]

    @AppStorage(ActivityService.connectedKey) private var connected = false
    @State private var loading = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var errorText: String?

    private let source = HealthKitWorkoutSource()
    private var service: ActivityService { ActivityService(context: context) }

    var body: some View {
        let grouping = service.grouping()
        let suggestions = service.suggestions(sessions: sessions.compactMap(\.info))
        let sessionByID = Dictionary(sessions.compactMap { s in s.info.map { ($0.id, $0) } }, uniquingKeysWith: { f, _ in f })
        let activityByID = Dictionary(grouping.groups.flatMap(\.members).map { ($0.id, $0) }, uniquingKeysWith: { f, _ in f })
        List {
            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Label(connected ? "Neu einlesen" : "Aus Apple Health einlesen", systemImage: "arrow.triangle.2.circlepath")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading || !source.isAvailable)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("CarbStock liest nur deine Radfahrten der letzten \(ActivityService.lookbackDays) Tage (Beginn und Dauer), schreibt nichts nach Health und speichert nichts in iCloud. Der Stand gilt für dieses Gerät: Fahrten von einem anderen Gerät erscheinen erst, wenn Health sie abgeglichen hat.")
            }

            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.activityID) { s in
                        if let session = sessionByID[s.sessionID], let activity = activityByID[s.activityID] {
                            SuggestionRow(session: session, activity: activity, difference: s.durationDifferenceMinutes,
                                          accept: { run { try service.accept(s, training: TrainingService(context: context)) } },
                                          dismiss: { run { try service.dismiss(s) } })
                        }
                    }
                } header: { Text("Als erledigt markieren?") } footer: {
                    Text("Das ändert nur den Status der Session. Es wird nichts im Vorrat gebucht.")
                }
            }

            if !grouping.maybePairs.isEmpty {
                Section {
                    ForEach(Array(grouping.maybePairs.enumerated()), id: \.offset) { _, pair in
                        MaybePairRow(pair: pair,
                                     same: { run { try service.confirmSame(pair.first.id, pair.second.id) } },
                                     different: { run { try service.confirmDifferent(pair.first.id, pair.second.id) } })
                    }
                } header: { Text("Vielleicht doppelt") } footer: {
                    Text("Bis du entscheidest, zählen beide Einträge.")
                }
            }

            Section {
                if grouping.groups.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Fahrten", systemImage: "bicycle")
                    } description: {
                        Text("Lies deine Radfahrten aus Apple Health ein. Geplant wird weiter von Hand: Health kennt nur absolvierte Fahrten.")
                    }
                }
                ForEach(grouping.groups.reversed()) { group in
                    GroupRow(group: group)
                        .swipeActions {
                            if group.primary.isIgnored {
                                Button("Einblenden", systemImage: "eye") { run { try service.setIgnored(false, group: group) } }
                            } else {
                                Button("Ausblenden", systemImage: "eye.slash") { run { try service.setIgnored(true, group: group) } }.tint(Color.actionFill)
                            }
                        }
                }
            } header: { if !grouping.groups.isEmpty { Text("Fahrten") } }

            if !imported.isEmpty {
                Section {
                    Button("Eingelesene Fahrten löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Entfernt nur die Kopien in CarbStock auf diesem Gerät. Health bleibt unberührt. Den Zugriff selbst entziehst du unter Einstellungen › Health › Datenzugriff & Geräte.")
                }
            }
        }
        .navigationTitle("Fahrten")
        .navigationBarTitleDisplayMode(.inline)
        .task { if connected { await refresh(silent: true) } }
        .confirmationDialog("Eingelesene Fahrten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { run { try service.deleteAll(); connected = false; message = nil } }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func refresh(silent: Bool = false) async {
        loading = true
        let outcome = await service.refresh(from: source)
        loading = false
        if case .imported = outcome { connected = true }
        if !silent || outcome != .nothingFound { message = outcome.message }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = "Das hat nicht geklappt. Bitte versuche es noch einmal." }
    }
}

private extension ExternalActivity {
    var summary: String {
        "\(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(Fmt.duration(minutes: Int((elapsedSeconds / 60).rounded())))"
    }
}

private struct GroupRow: View {
    let group: ActivityGroup
    var body: some View {
        let a = group.primary
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "bicycle").foregroundStyle(.tint).accessibilityHidden(true)
                Text(a.title ?? "Radfahrt").strikethrough(a.isIgnored)
                Spacer()
                if a.isIgnored { Label("Ausgeblendet", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
            }
            Text(a.summary).font(.footnote).foregroundStyle(.secondary)
            if group.members.count > 1 {
                Text("\(group.members.count) Einträge zusammengefasst, zählt einmal").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SuggestionRow: View {
    let session: PlannedSession
    let activity: ExternalActivity
    let difference: Int
    let accept: () -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(session.type.title) am \(Fmt.date(session.day)), \(Fmt.duration(minutes: session.durationMinutes)) geplant")
            Text("Gefahren: \(activity.summary)" + (difference == 0 ? "" : " (\(difference > 0 ? "+" : "−")\(abs(difference)) min)"))
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Erledigt", systemImage: "checkmark", action: accept).buttonStyle(.borderedProminent).tint(Color.actionFill)
                Button("Nein", action: dismiss).buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }
}

private struct MaybePairRow: View {
    let pair: MaybePair
    let same: () -> Void
    let different: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pair.first.summary)
            Text(pair.second.summary)
            HStack {
                Button("Dieselbe Fahrt", action: same).buttonStyle(.borderedProminent).tint(Color.actionFill)
                Button("Verschieden", action: different).buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }
}
