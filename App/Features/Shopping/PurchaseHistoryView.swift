import CarbStockCore
import SwiftData
import SwiftUI

/// Verlauf der bewerteten Angebote (`PurchaseEvaluation`, Spec 5.7): Snapshot mit Urteil und Begründungszeilen.
struct PurchaseHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PurchaseEvaluation.createdAt, order: .reverse) private var evaluations: [PurchaseEvaluation]
    @State private var errorText: String?

    var body: some View {
        Group {
            if evaluations.isEmpty {
                Section {
                    ContentUnavailableView("Noch kein Verlauf", systemImage: "clock.arrow.circlepath",
                        description: Text("Bewertete Angebote erscheinen hier, sobald du sie sicherst, kaufst oder verwirfst."))
                }
            } else {
                Section {
                    ForEach(evaluations) { e in
                        NavigationLink { PurchaseEvaluationDetailView(evaluation: e) } label: { HistoryRow(evaluation: e) }
                            .swipeActions {
                                Button("Löschen", systemImage: "trash", role: .destructive) { remove(e) }
                            }
                    }
                } footer: {
                    Text("Der Verlauf hält fest, was du bei einem Angebot wusstest. Er ändert den Bestand nicht.")
                }
            }
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func remove(_ e: PurchaseEvaluation) {
        do { try PurchaseService(context: context).remove(e) } catch { errorText = "Löschen hat nicht geklappt." }
    }
}

private struct HistoryRow: View {
    let evaluation: PurchaseEvaluation

    var body: some View {
        let offer = evaluation.offer
        let unit = offer?.baseUnit ?? .piece
        let outcome = PurchaseOutcome(evaluation.assessment, unit: unit, offeredQuantity: offer?.quantity)
        let decision = evaluation.userDecision
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(offer?.productName ?? "Angebot").font(.headline)
                Spacer()
                Text(evaluation.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(.secondary)
            }
            Label(outcome.title, systemImage: outcome.symbol).font(.subheadline).foregroundStyle(outcome.tone.color)
            HStack(spacing: 8) {
                if let offer { Text(Fmt.quantity(offer.quantity, unit: unit)) }
                if let p = evaluation.assessment.pricePer100gCarbs { Text("\(Fmt.euro(p)) je 100 g Carbs") }
            }
            .font(.footnote).foregroundStyle(.secondary)
            Label(decision.title, systemImage: decision.symbol).font(.footnote).foregroundStyle(decision.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct PurchaseEvaluationDetailView: View {
    @Environment(\.modelContext) private var context
    let evaluation: PurchaseEvaluation
    @State private var errorText: String?

    var body: some View {
        let offer = evaluation.offer
        let unit = offer?.baseUnit ?? .piece
        let outcome = PurchaseOutcome(evaluation.assessment, unit: unit, offeredQuantity: offer?.quantity)
        List {
            if let offer {
                Section("Angebot") {
                    LabeledContent("Produkt", value: offer.productName + (offer.isNewProduct ? " (neu)" : ""))
                    LabeledContent("Menge", value: Fmt.quantity(offer.quantity, unit: unit))
                    if let cents = offer.totalPriceCents { LabeledContent("Preis", value: Fmt.euro(cents: cents)) }
                    if let c = offer.discountCents, c > 0 { LabeledContent("davon Rabatt", value: Fmt.euro(cents: c)) }
                    if let c = offer.shippingCents, c > 0 { LabeledContent("davon Versand", value: Fmt.euro(cents: c)) }
                    if let e = offer.expiry { LabeledContent("MHD", value: Fmt.date(e)) }
                    LabeledContent("Kaufhorizont", value: CountText.weeks(offer.horizonDays / 7))
                    if offer.bargainRule { LabeledContent("Schnäppchenregel", value: "an") }
                }
            }
            OutcomeSections(outcome: outcome, pricePer100g: evaluation.assessment.pricePer100gCarbs)
            Section {
                Label(evaluation.userDecision.title, systemImage: evaluation.userDecision.symbol)
                    .foregroundStyle(evaluation.userDecision.color)
                if evaluation.userDecision == .none {
                    Button("Als nicht gekauft merken", systemImage: "xmark.circle") { skip() }
                }
            } header: { Text("Deine Entscheidung") } footer: {
                Text("Die Entscheidung setzt nur du. „Gekauft“ entsteht über die Einkaufsliste oder den Entscheider und bucht den Bestand.")
            }
            Section {
                Text("Stand vom \(evaluation.createdAt.formatted(date: .abbreviated, time: .shortened)). Spätere Änderungen an Bestand oder Training ändern diesen Verlaufseintrag nicht.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(offer?.productName ?? "Angebot")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func skip() {
        do { try PurchaseService(context: context).markSkipped(evaluation) } catch { errorText = "Das hat nicht geklappt." }
    }
}
