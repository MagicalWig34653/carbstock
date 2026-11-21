import CarbStockCore
import SwiftData
import SwiftUI

/// Carbs pro Stunde je Art (Spec 5.5): eingebaute Voreinstellung, nur Abweichungen werden gespeichert.
struct CarbRatesView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [CarbRateOverride]
    @State private var errorText: String?

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        let userRates = service.userRates()
        List {
            Section {
                ForEach(SessionType.allCases, id: \.self) { type in
                    let builtIn = CarbRate.builtIn(type)
                    let current = userRates[type] ?? builtIn.defaultPerHour
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper(value: Binding(get: { current }, set: { set($0, type) }), in: TrainingLimits.carbsPerHour) {
                            LabeledContent {
                                Text("\(current) g/h").monospacedDigit()
                            } label: {
                                Label(type.title, systemImage: type.symbol)
                            }
                        }
                        HStack {
                            Text(hint(builtIn)).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            if userRates[type] != nil {
                                Button("Zurücksetzen") { reset(type) }.font(.footnote).buttonStyle(.borderless)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            } footer: {
                Text("Planungswerte für den Bedarf, keine medizinische oder ernährungsberatende Empfehlung. Z2 ist eine ungeprüfte Annahme; bitte setze deinen eigenen Wert.")
            }
        }
        .navigationTitle("Carbs pro Stunde")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func hint(_ r: CarbRate) -> String {
        let base = "Voreinstellung \(r.defaultPerHour) g/h"
        return r.range.map { "\(base) (üblicher Bereich \($0.lowerBound)–\($0.upperBound))" } ?? base
    }

    private func set(_ value: Int, _ type: SessionType) {
        do { try service.setRate(value, for: type) } catch { errorText = "Der Wert wurde nicht übernommen." }
    }

    private func reset(_ type: SessionType) {
        do { try service.setRate(nil, for: type) } catch { errorText = "Zurücksetzen hat nicht geklappt." }
    }
}
