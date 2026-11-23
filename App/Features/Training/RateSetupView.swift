import CarbStockCore
import SwiftData
import SwiftUI

/// Beim ersten Start: Carbs pro Stunde je Art festlegen. Überspringbar, später unter Training › Carbs pro Stunde änderbar.
struct RateSetupView: View {
    let onFinish: () -> Void
    @Environment(\.modelContext) private var context
    @State private var values: [SessionType: Int] = [:]
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("CarbStock rechnet deinen Bedarf aus geplanten Fahrten und deinen Carbs pro Stunde. Stell hier ein, was du üblicherweise pro Stunde zu dir nimmst. Du kannst das jederzeit ändern.")
                        .font(.callout)
                }
                Section {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        let builtIn = CarbRate.builtIn(type)
                        let current = values[type] ?? builtIn.defaultPerHour
                        VStack(alignment: .leading, spacing: 4) {
                            RateStepperRow(type: type, value: Binding(get: { current }, set: { values[type] = $0 }))
                            Text(builtIn.range.map { "Vorschlag \(builtIn.defaultPerHour) g/h, üblicher Bereich \($0.lowerBound)–\($0.upperBound)" }
                                 ?? "Vorschlag \(builtIn.defaultPerHour) g/h")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Planungswerte für den Bedarf, keine medizinische oder ernährungsberatende Empfehlung.")
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Überspringen", action: onFinish) }
                ToolbarItem(placement: .confirmationAction) { Button("Übernehmen", action: save) }
            }
            .onAppear { if values.isEmpty { values = RateSetup.initialValues(userRates: service.userRates()) } }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        do { try RateSetup.apply(values, using: service); onFinish() } catch { errorText = "Die Werte wurden nicht übernommen. Bitte versuche es noch einmal." }
    }
}
