import CarbStockCore
import SwiftUI

/// Bestätigung „Gekauft“: legt Charge + Kaufbuchung an (AC-K5). Menge, Preis und MHD sind vorbelegt.
struct BoughtSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let products: [Product]
    let onConfirm: (BoughtDraft) throws -> Void

    @State private var draft: BoughtDraft
    @State private var priceEuro: Double?
    @State private var confirming = false
    @State private var errorText: String?

    init(title: String, initial: BoughtDraft, products: [Product], onConfirm: @escaping (BoughtDraft) throws -> Void) {
        self.title = title
        self.products = products
        self.onConfirm = onConfirm
        _draft = State(initialValue: initial)
        _priceEuro = State(initialValue: initial.totalPriceCents.map { Double($0) / 100 })
    }

    private var current: BoughtDraft {
        var d = draft
        d.totalPriceCents = Money.cents(fromEuro: priceEuro)
        return d
    }

    private var unit: BaseUnit {
        draft.productID.flatMap { id in products.first { $0.id == id }?.baseUnit } ?? draft.newProduct.baseUnit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produkt") {
                    Picker("Produkt", selection: $draft.productID) {
                        Text("Neues Produkt").tag(UUID?.none)
                        ForEach(products) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    if draft.productID == nil { NewProductFields(draft: $draft.newProduct) }
                }
                Section("Kauf") {
                    LabeledContent(unit == .gram ? "Menge (g)" : "Menge (Stück)") {
                        TextField("Pflicht", value: Binding(get: { draft.quantity > 0 ? draft.quantity : nil },
                                                            set: { draft.quantity = $0 ?? 0 }), format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Gesamtpreis (€)") {
                        TextField("optional", value: $priceEuro, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    ExpiryFields(expiry: $draft.expiry)
                }
                let problems = current.problems
                if !problems.isEmpty {
                    Section("Noch nötig") {
                        ForEach(problems, id: \.self) { Label($0.message, systemImage: "exclamationmark.circle") }
                    }
                }
                Section {
                    Text("Beim Bestätigen entsteht eine Charge mit Zugangsbuchung. Buchungen lassen sich nicht ändern, nur per Storno oder Korrektur ausgleichen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gekauft") { confirming = true }.disabled(!current.problems.isEmpty)
                }
            }
            .confirmationDialog("Kauf buchen?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Ja, gekauft und einbuchen") { confirm() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\(Fmt.quantity(current.quantity, unit: unit)) kommen in den Bestand.")
            }
        }
    }

    private func confirm() {
        do {
            try onConfirm(current)
            dismiss()
        } catch {
            errorText = "Der Kauf konnte nicht gebucht werden."
        }
    }
}
