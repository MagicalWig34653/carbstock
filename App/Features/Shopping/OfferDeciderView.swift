import CarbStockCore
import SwiftData
import SwiftUI

/// Kauf-Entscheider (Spec 4.4): Angebot eingeben, Urteil mit Begründung lesen. Das Urteil ist ein Gedankenspiel:
/// Es ändert nie den Bestand. Erst „Gekauft“ (nach Bestätigung) legt Charge und Kaufbuchung an.
struct OfferDeciderView: View {
    private enum Done: Equatable { case saved, listed, bought, skipped }

    @Environment(\.modelContext) private var context
    // Observed so the verdict follows bookings, sessions and rates.
    @Query private var products: [Product]
    @Query private var movements: [StockMovement]
    @Query private var sessions: [TrainingSession]
    @Query private var templates: [WeeklyTemplateRecord]
    @Query private var rates: [CarbRateOverride]

    @State private var draft = OfferDraft()
    @State private var evaluationID = UUID()
    @State private var done: Done?
    @State private var boughtDraft: BoughtDraft?
    @State private var errorText: String?

    private var service: PurchaseService { PurchaseService(context: context) }
    private var selectable: [Product] {
        products.filter { !$0.isArchived }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    private var selected: Product? { draft.existingProductID.flatMap { id in products.first { $0.id == id } } }
    private var unit: BaseUnit { selected?.baseUnit ?? draft.newProduct.baseUnit }
    private var hasInput: Bool { draft.existingProductID != nil || !draft.newProduct.name.isEmpty || draft.quantity != nil }

    var body: some View {
        let problems = draft.problems()
        let assessed = problems.isEmpty ? (try? service.assess(draft, id: evaluationID)) : nil
        Group {
            productSection
            offerSection
            horizonSection
            if !problems.isEmpty, hasInput {
                Section("Noch nötig") {
                    ForEach(problems, id: \.self) { Label($0.message, systemImage: "exclamationmark.circle") }
                }
            }
            if let assessed {
                priceSection(assessed)
                OutcomeSections(outcome: assessed.outcome, pricePer100g: assessed.assessment.offerPricePer100gCarbs)
                actionsSection(assessed)
            } else if problems.isEmpty {
                Section { Text("Für dieses Angebot konnte kein Urteil berechnet werden.").foregroundStyle(.secondary) }
            }
        }
        .onChange(of: draft) { _, _ in
            // Neue Eingabe = neue Bewertung: alte Rückmeldung weg, neuer Verlaufseintrag beim nächsten Sichern.
            evaluationID = UUID()
            done = nil
        }
        .sheet(item: Binding(get: { boughtDraft.map(BoughtTarget.init) }, set: { if $0 == nil { boughtDraft = nil } })) { target in
            BoughtSheet(title: "Gekauft", initial: target.draft, products: selectable) { confirmed in
                guard let assessed = try? service.assess(draft, id: evaluationID) else { throw PurchaseService.Failure.notBuyable }
                try service.markBought(assessed, with: confirmed)
                done = .bought
            }
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private struct BoughtTarget: Identifiable {
        let id = UUID()
        let draft: BoughtDraft
        init(_ draft: BoughtDraft) { self.draft = draft }
    }

    // MARK: Eingabe

    private var productSection: some View {
        Section {
            Picker("Produkt", selection: $draft.existingProductID) {
                Text("Neues Produkt").tag(UUID?.none)
                ForEach(selectable) { Text($0.displayName).tag(UUID?.some($0.id)) }
            }
            if let selected {
                LabeledContent("Carbs", value: "\(selected.carbsPerPortionG.formatted()) g je \(selected.baseUnit == .gram ? "Portion" : "Stück")")
            } else {
                NewProductFields(draft: $draft.newProduct)
            }
        } header: { Text("Produkt") } footer: {
            Text("Wähle ein Produkt aus deinem Bestand oder gib ein neues ein. Es wird erst beim Kauf angelegt.")
        }
    }

    private var offerSection: some View {
        Section("Angebot") {
            LabeledContent(unit == .gram ? "Menge (g)" : "Menge (Stück)") {
                TextField("Pflicht", value: $draft.quantity, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Picker("Preis als", selection: $draft.priceMode) {
                Text("Gesamtpreis").tag(OfferPriceMode.total)
                Text(unit == .gram ? "Preis je kg" : "Stückpreis").tag(OfferPriceMode.perUnit)
            }
            .pickerStyle(.segmented)
            LabeledContent(draft.priceMode == .total ? "Preis (€)" : (unit == .gram ? "Preis je kg (€)" : "Preis je Stück (€)")) {
                TextField("optional", value: $draft.priceEuro, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Versand (€)") {
                TextField("optional", value: $draft.shippingEuro, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Rabatt") {
                HStack {
                    TextField("optional", value: $draft.discountValue, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Picker("Rabattart", selection: $draft.discountKind) {
                        Text("%").tag(OfferDiscountKind.percent)
                        Text("€").tag(OfferDiscountKind.euro)
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
            }
            ExpiryFields(expiry: $draft.expiry, title: "MHD des Angebots")
        }
    }

    private var horizonSection: some View {
        Section {
            Stepper(value: $draft.horizonWeeks, in: OfferLimits.horizonWeeks) {
                Text("Kaufhorizont: \(draft.horizonWeeks) \(draft.horizonWeeks == 1 ? "Woche" : "Wochen")")
            }
            Toggle("Schnäppchenregel", isOn: $draft.bargainRule)
        } header: { Text("Bewertung") } footer: {
            Text("Der Bestand soll für den Kaufhorizont reichen. Mit der Schnäppchenregel kann ein Preis weit unter deinem Median auch dann zum Kauf raten, wenn der Bestand reicht. Sie ist standardmäßig aus.")
        }
    }

    // MARK: Ergebnis

    private func priceSection(_ a: PurchaseService.Assessed) -> some View {
        Group {
            if let p = a.price {
                Section("Preisrechnung") {
                    LabeledContent("Ware", value: Fmt.euro(cents: p.goodsCents))
                    if p.discountCents > 0 { LabeledContent("Rabatt", value: "− " + Fmt.euro(cents: p.discountCents)) }
                    if p.shippingCents > 0 { LabeledContent("Versand", value: "+ " + Fmt.euro(cents: p.shippingCents)) }
                    LabeledContent("Du zahlst", value: Fmt.euro(cents: p.totalCents)).fontWeight(.semibold)
                    LabeledContent(unit == .gram ? "Je kg" : "Je Stück",
                                   value: Fmt.euro(p.perUnitCents * (unit == .gram ? 1000 : 1) / 100))
                }
            }
        }
    }

    private func actionsSection(_ a: PurchaseService.Assessed) -> some View {
        Section {
            if let done {
                Label(doneText(done), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                if a.recommendedQuantity != nil {
                    Button("Auf die Einkaufsliste", systemImage: "cart.badge.plus") { perform { _ = try service.addToList(a); return .listed } }
                    Button("Gekauft …", systemImage: "checkmark.circle") { boughtDraft = a.boughtDraft(existingProductID: draft.existingProductID) }
                }
                Button("Im Verlauf sichern", systemImage: "clock.arrow.circlepath") { perform { try service.saveEvaluation(a); return .saved } }
                Button("Nicht kaufen (verwerfen)", systemImage: "xmark.circle", role: .destructive) { perform { try service.skip(a); return .skipped } }
            }
        } header: { Text("Und jetzt?") } footer: {
            Text("Das Urteil ändert nichts am Bestand. Im Verlauf landet ein Angebot nur, wenn du es sicherst, kaufst oder verwirfst.")
        }
    }

    private func doneText(_ d: Done) -> String {
        switch d {
        case .saved: "Im Verlauf gesichert."
        case .listed: "Auf der Einkaufsliste."
        case .bought: "Gekauft und eingebucht."
        case .skipped: "Verworfen und im Verlauf vermerkt."
        }
    }

    private func perform(_ action: () throws -> Done) {
        do { done = try action() } catch { errorText = "Das hat nicht geklappt. Bitte versuche es noch einmal." }
    }
}
