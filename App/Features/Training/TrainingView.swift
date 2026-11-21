import CarbStockCore
import SwiftData
import SwiftUI

/// Gliederung der Session-Liste (reine Logik, getestet): heute und kommend · zuletzt (28 Tage) · älter.
struct SessionSections: Equatable {
    static let recentDays = 28

    var upcoming: [PlannedSession]
    var recent: [PlannedSession]
    var older: [PlannedSession]

    init(_ sessions: [PlannedSession], today: CalendarDay) {
        upcoming = sessions.filter { $0.day >= today }.sorted { $0.day < $1.day }
        let past = sessions.filter { $0.day < today }.sorted { $0.day > $1.day }
        let cutoff = today.adding(days: -Self.recentDays)
        recent = past.filter { $0.day >= cutoff }
        older = past.filter { $0.day < cutoff }
    }
}

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.day) private var sessions: [TrainingSession]
    // Observed so the list follows changes of the weekly template and the rates.
    @Query private var templates: [WeeklyTemplateRecord]
    @Query private var rates: [CarbRateOverride]

    @State private var editing: TrainingSession?
    @State private var adding = false
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }
    private var today: CalendarDay { Fmt.today() }

    var body: some View {
        let userRates = service.userRates()
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = SessionSections(sessions.compactMap(\.info), today: today)
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Noch keine Sessions", systemImage: "bicycle")
                        } description: {
                            Text("Trag Fahrten ein oder lege eine Wochenvorlage an, damit die Prognose den Bedarf kennt.")
                        } actions: {
                            Button("Session anlegen") { adding = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                Section {
                    NavigationLink { WeeklyTemplateView() } label: {
                        Label("Wochenvorlage", systemImage: "calendar")
                    }
                    NavigationLink { CarbRatesView() } label: {
                        Label("Carbs pro Stunde", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    NavigationLink { PackListsView() } label: {
                        Label("Packlisten", systemImage: "checklist")
                    }
                } footer: {
                    Text("Trainingsdaten bleiben auf diesem Gerät und werden nicht über iCloud abgeglichen.")
                }
                if !sections.upcoming.isEmpty {
                    Section("Heute und kommend") { ForEach(sections.upcoming) { row($0, byID, userRates) } }
                }
                if !sections.recent.isEmpty {
                    Section("Zuletzt") { ForEach(sections.recent) { row($0, byID, userRates) } }
                }
                if !sections.older.isEmpty {
                    Section("Älter") { ForEach(sections.older) { row($0, byID, userRates) } }
                }
            }
            .navigationTitle("Training")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Session hinzufügen", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $adding) { SessionFormView(session: nil) }
            .sheet(item: $editing) { SessionFormView(session: $0) }
            .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
    }

    @ViewBuilder
    private func row(_ info: PlannedSession, _ byID: [UUID: TrainingSession], _ userRates: [SessionType: Int]) -> some View {
        if let model = byID[info.id] {
            Button { editing = model } label: { SessionRow(model: model, info: info, userRates: userRates) }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    if info.status != .done { Button("Erledigt", systemImage: "checkmark") { set(.done, model) }.tint(.green) }
                    if info.status != .planned { Button("Geplant", systemImage: "arrow.uturn.backward") { set(.planned, model) }.tint(.blue) }
                }
                .swipeActions(edge: .trailing) {
                    Button("Löschen", systemImage: "trash", role: .destructive) { run { try service.delete(model) } }
                    if info.status != .skipped { Button("Ausgefallen", systemImage: "xmark") { set(.skipped, model) }.tint(.orange) }
                }
        }
    }

    private func set(_ status: SessionStatus, _ s: TrainingSession) { run { try service.setStatus(status, on: s) } }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = "Das hat nicht geklappt. Bitte versuche es noch einmal." }
    }
}

struct SessionRow: View {
    let model: TrainingSession
    let info: PlannedSession
    let userRates: [SessionType: Int]

    var body: some View {
        let demand = DemandCalculator.sessionDemandG(info, userRates: userRates)
        let rate = DemandCalculator.carbsPerHour(type: info.type, sessionOverride: info.carbsPerHourOverride, userRates: userRates)
        HStack(spacing: 12) {
            Image(systemName: info.type.symbol).frame(width: 28).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title ?? info.type.title).font(.body).strikethrough(info.status == .skipped)
                Text("\(Fmt.weekdayDate(info.day)) · \(Fmt.duration(minutes: info.durationMinutes)) · \(rate) g/h"
                     + (info.carbsPerHourOverride != nil ? " (eigener Wert)" : ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(info.status == .skipped ? "–" : Fmt.grams(demand)).font(.body.monospacedDigit())
                if info.status != .planned {
                    Label(info.status.title, systemImage: info.status == .done ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.caption).foregroundStyle(info.status == .done ? .green : .orange)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SessionFormView: View {
    let session: TrainingSession?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SessionDraft(day: Fmt.today())
    @State private var loaded = false
    @State private var customRate = false
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        let userRates = service.userRates()
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tag", selection: dayBinding, displayedComponents: .date)
                    Picker("Art", selection: $draft.type) {
                        ForEach(SessionType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $draft.durationMinutes, in: TrainingLimits.durationMinutes, step: 15) {
                        LabeledContent("Dauer", value: Fmt.duration(minutes: draft.durationMinutes))
                    }
                }
                Section {
                    Toggle("Eigener Wert für diese Session", isOn: $customRate)
                    if customRate {
                        Stepper(value: rateBinding(userRates), in: TrainingLimits.carbsPerHour) {
                            LabeledContent("Carbs pro Stunde", value: "\(draft.carbsPerHourOverride ?? 0) g/h")
                        }
                    } else {
                        LabeledContent("Carbs pro Stunde", value: "\(DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates)) g/h")
                    }
                    LabeledContent("Bedarf der Session", value: Fmt.grams(draft.demandG(userRates: userRates)))
                        .fontWeight(.semibold)
                } header: { Text("Carbs") } footer: {
                    Text("Der Wert der Art lässt sich unter „Carbs pro Stunde“ ändern. Ein eigener Wert gilt nur für diese Session.")
                }
                Section("Notiz") {
                    TextField("Titel (z. B. So-Langfahrt)", text: $draft.title)
                    TextField("Notiz", text: $draft.note, axis: .vertical)
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle(session == nil ? "Neue Session" : "Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern", action: save).disabled(!draft.problems.isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let session { draft = SessionDraft(session) }
                customRate = draft.carbsPerHourOverride != nil
            }
            .onChange(of: customRate) { _, on in
                if !on { draft.carbsPerHourOverride = nil } else if draft.carbsPerHourOverride == nil {
                    draft.carbsPerHourOverride = DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates)
                }
            }
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { Fmt.date(from: draft.day) }, set: { draft.day = CalendarDay($0, in: .current) })
    }

    private func rateBinding(_ userRates: [SessionType: Int]) -> Binding<Int> {
        Binding(get: { draft.carbsPerHourOverride ?? DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates) },
                set: { draft.carbsPerHourOverride = $0 })
    }

    private func save() {
        do {
            if let session { try service.update(session, with: draft) } else { try service.addSession(draft) }
            dismiss()
        } catch { errorText = "Das Eintragen hat nicht geklappt. Bitte prüfe Dauer und Wert." }
    }
}
