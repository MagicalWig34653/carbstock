import CarbStockCore
import SwiftData
import SwiftUI

/// Wochenvorlage (O-08): wiederkehrende Sessions je Wochentag mit Gültigkeitszeitraum.
struct WeeklyTemplateView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [WeeklyTemplateRecord]
    @Query private var rates: [CarbRateOverride]

    @State private var editing: TemplateTarget?
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        let today = Fmt.today()
        let userRates = service.userRates()
        let entries = records.sorted { ($0.weekdayIndex, $0.validFrom) < ($1.weekdayIndex, $1.validFrom) }
        let perWeek = weekDemand(entries, on: today, userRates: userRates)
        List {
            Section {
                LabeledContent("Bedarf laut Vorlage", value: "\(Fmt.grams(perWeek)) pro Woche")
            } footer: {
                Text("Eingetragene Sessions gelten an ihrem Tag. Für alle anderen Tage greift die Vorlage; ein Wochentag ohne Eintrag zählt als Ruhetag.")
            }
            ForEach(0..<7, id: \.self) { index in
                Section(Weekday.name(index)) {
                    ForEach(entries.filter { $0.weekdayIndex == index }) { r in
                        if let e = r.info {
                            Button { editing = TemplateTarget(record: r, weekday: index) } label: {
                                TemplateRow(entry: e, today: today, userRates: userRates)
                            }
                            .buttonStyle(.plain)
                            .swipeActions { Button("Löschen", systemImage: "trash", role: .destructive) { delete(r) } }
                        }
                    }
                    Button("Eintrag hinzufügen", systemImage: "plus") { editing = TemplateTarget(record: nil, weekday: index) }
                }
            }
        }
        .navigationTitle("Wochenvorlage")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { TemplateFormView(target: $0) }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    /// Demand per week of the entries valid on `day` (7 days of the template).
    private func weekDemand(_ entries: [WeeklyTemplateRecord], on day: CalendarDay, userRates: [SessionType: Int]) -> Double {
        let series = DemandSeries.build(from: day, maxDays: 7, sessions: [], template: entries.compactMap(\.info), userRates: userRates)
        return series.demandG(firstDays: 7)
    }

    private func delete(_ r: WeeklyTemplateRecord) {
        do { try service.delete(r) } catch { errorText = "Löschen hat nicht geklappt." }
    }
}

struct TemplateTarget: Identifiable {
    let id = UUID()
    let record: WeeklyTemplateRecord?
    let weekday: Int
}

struct TemplateRow: View {
    let entry: WeeklyTemplateEntry
    let today: CalendarDay
    let userRates: [SessionType: Int]

    private var validity: String {
        let from = entry.validFrom > today ? "ab \(Fmt.date(entry.validFrom))" : nil
        let until = entry.validUntil.map { "bis \(Fmt.date($0))" }
        return [from, until].compactMap { $0 }.joined(separator: " ")
    }
    private var ended: Bool { entry.validUntil.map { $0 < today } ?? false }

    var body: some View {
        let rate = DemandCalculator.carbsPerHour(type: entry.type, sessionOverride: entry.carbsPerHourOverride, userRates: userRates)
        HStack {
            Image(systemName: entry.type.symbol).frame(width: 28).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.title)
                Text("\(Fmt.duration(minutes: entry.durationMinutes)) · \(rate) g/h" + (validity.isEmpty ? "" : " · \(validity)"))
                    .font(.footnote).foregroundStyle(.secondary)
                if ended { Text("Beendet – zählt nicht mehr").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Text(Fmt.grams(DemandCalculator.sessionDemandG(durationMinutes: entry.durationMinutes, carbsPerHour: rate)))
                .font(.body.monospacedDigit())
        }
        .opacity(ended ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TemplateFormView: View {
    let target: TemplateTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TemplateDraft(weekdayIndex: 0, validFrom: Fmt.today())
    @State private var loaded = false
    @State private var customRate = false
    @State private var hasEnd = false
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        let userRates = service.userRates()
        NavigationStack {
            Form {
                Section(Weekday.name(draft.weekdayIndex)) {
                    Picker("Art", selection: $draft.type) {
                        ForEach(SessionType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $draft.durationMinutes, in: TrainingLimits.durationMinutes, step: 15) {
                        LabeledContent("Dauer", value: Fmt.duration(minutes: draft.durationMinutes))
                    }
                }
                Section {
                    Toggle("Eigener Wert", isOn: $customRate)
                    if customRate {
                        Stepper(value: rateBinding(userRates), in: TrainingLimits.carbsPerHour) {
                            LabeledContent("Carbs pro Stunde", value: "\(draft.carbsPerHourOverride ?? 0) g/h")
                        }
                    } else {
                        LabeledContent("Carbs pro Stunde", value: "\(DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates)) g/h")
                    }
                    LabeledContent("Bedarf je Termin", value: Fmt.grams(draft.demandG(userRates: userRates))).fontWeight(.semibold)
                } header: { Text("Carbs") }
                Section("Gültigkeit") {
                    DatePicker("Gilt ab", selection: dateBinding(\.validFrom), displayedComponents: .date)
                    Toggle("Endet am", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Letzter Tag", selection: untilBinding, displayedComponents: .date)
                    }
                }
                if draft.problems.contains(.endBeforeStart) {
                    Section { Text("Das Ende liegt vor dem Beginn.").foregroundStyle(.red) }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle(target.record == nil ? "Neuer Eintrag" : "Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern", action: save).disabled(!draft.problems.isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let record = target.record, let d = TemplateDraft(record) { draft = d }
                else { draft = TemplateDraft(weekdayIndex: target.weekday, validFrom: Fmt.today()) }
                customRate = draft.carbsPerHourOverride != nil
                hasEnd = draft.validUntil != nil
            }
            .onChange(of: customRate) { _, on in
                if !on { draft.carbsPerHourOverride = nil } else if draft.carbsPerHourOverride == nil {
                    draft.carbsPerHourOverride = DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates)
                }
            }
            .onChange(of: hasEnd) { _, on in
                if !on { draft.validUntil = nil } else if draft.validUntil == nil { draft.validUntil = draft.validFrom.adding(days: 84) }
            }
        }
    }

    private func dateBinding(_ key: WritableKeyPath<TemplateDraft, CalendarDay>) -> Binding<Date> {
        Binding(get: { Fmt.date(from: draft[keyPath: key]) }, set: { draft[keyPath: key] = CalendarDay($0, in: .current) })
    }

    private var untilBinding: Binding<Date> {
        Binding(get: { Fmt.date(from: draft.validUntil ?? draft.validFrom) }, set: { draft.validUntil = CalendarDay($0, in: .current) })
    }

    private func rateBinding(_ userRates: [SessionType: Int]) -> Binding<Int> {
        Binding(get: { draft.carbsPerHourOverride ?? DemandCalculator.carbsPerHour(type: draft.type, userRates: userRates) },
                set: { draft.carbsPerHourOverride = $0 })
    }

    private func save() {
        do {
            if let record = target.record { try service.update(record, with: draft) } else { try service.addTemplateEntry(draft) }
            dismiss()
        } catch { errorText = "Das Eintragen hat nicht geklappt. Bitte prüfe die Angaben." }
    }
}
