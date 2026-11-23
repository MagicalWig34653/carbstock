import CarbStockCore
import SwiftData
import SwiftUI

/// Einkaufsliste (Spec 4.4): geplante Käufe. „Gekauft“ legt nach Bestätigung Charge + Kaufbuchung an.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingListItem.createdAt) private var items: [ShoppingListItem]
    @Query private var products: [Product]

    @Binding var adding: Bool
    @State private var buying: ShoppingListItem?
    @State private var errorText: String?

    private var service: PurchaseService { PurchaseService(context: context) }
    private var selectable: [Product] { products.filter { !$0.isArchived }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }

    var body: some View {
        let open = items.filter { $0.state == .open }
        let closed = items.filter { $0.state != .open }.sorted { $0.createdAt > $1.createdAt }
        Group {
            if items.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Die Einkaufsliste ist leer", systemImage: "cart")
                    } description: {
                        Text("Setz ein Angebot nach einem Urteil „kaufen“ auf die Liste oder trag etwas von Hand ein.")
                    } actions: {
                        Button("Eintrag hinzufügen") { adding = true }.buttonStyle(.borderedProminent).tint(Color.actionFill)
                    }
                }
            }
            if !open.isEmpty {
                Section("Offen") { ForEach(open) { row($0) } }
            }
            if !closed.isEmpty {
                Section("Erledigt") { ForEach(closed) { row($0) } }
            }
        }
        .sheet(item: $buying) { item in
            BoughtSheet(title: "Gekauft", initial: BoughtDraft(item: item), products: selectable) { draft in
                try service.markBought(item, with: draft)
            }
        }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func name(_ item: ShoppingListItem) -> String {
        if let id = item.productID, let p = products.first(where: { $0.id == id }) { return p.displayName }
        return item.freeText ?? "Eintrag"
    }

    private func unit(_ item: ShoppingListItem) -> BaseUnit {
        if let id = item.productID, let p = products.first(where: { $0.id == id }) { return p.baseUnit }
        return item.savedOffer?.offer.baseUnit ?? .piece
    }

    @ViewBuilder
    private func row(_ item: ShoppingListItem) -> some View {
        let isOpen = item.state == .open
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name(item)).font(.headline)
                Spacer()
                Text(Fmt.quantity(item.plannedQuantity, unit: unit(item))).monospacedDigit()
            }
            HStack(spacing: 8) {
                if let cents = item.estimatedTotalPriceCents { Text("ca. \(Fmt.euro(cents: cents))") }
                if let e = item.expiry { Text("MHD \(Fmt.date(e))") }
                if item.savedOffer != nil { Label("aus Urteil", systemImage: "scalemass") }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if !isOpen {
                Label(item.state == .bought ? "Gekauft" : "Verworfen",
                      systemImage: item.state == .bought ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.footnote).foregroundStyle(item.state == .bought ? .green : Color.warning)
            } else {
                Button("Gekauft …", systemImage: "checkmark.circle") { buying = item }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .swipeActions(edge: .trailing) {
            if isOpen {
                Button("Verwerfen", systemImage: "xmark") { drop(item) }.tint(Color.actionFill)
            } else {
                Button("Entfernen", systemImage: "trash", role: .destructive) { remove(item) }
            }
        }
        .swipeActions(edge: .leading) {
            if isOpen { Button("Gekauft", systemImage: "checkmark") { buying = item }.tint(.green) }
        }
    }

    private func drop(_ item: ShoppingListItem) {
        do { try service.drop(item) } catch { errorText = "Verwerfen hat nicht geklappt." }
    }

    private func remove(_ item: ShoppingListItem) {
        do { try service.remove(item) } catch { errorText = "Entfernen hat nicht geklappt." }
    }
}

/// Manueller Eintrag: Produkt aus dem Bestand oder Freitext, Menge, geschätzter Preis.
struct ShoppingEntryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [Product]
    @State private var draft = ShoppingEntryDraft()
    @State private var errorText: String?

    private var selectable: [Product] { products.filter { !$0.isArchived }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
    private var unit: BaseUnit { draft.productID.flatMap { id in products.first { $0.id == id }?.baseUnit } ?? .piece }

    var body: some View {
        NavigationStack {
            Form {
                Section("Was?") {
                    Picker("Produkt", selection: $draft.productID) {
                        Text("Freitext").tag(UUID?.none)
                        ForEach(selectable) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    if draft.productID == nil { TextField("Text (z. B. Gel Sorte X)", text: $draft.freeText) }
                    LabeledContent(unit == .gram ? "Menge (g)" : "Menge (Stück)") {
                        TextField("Pflicht", value: $draft.quantity, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Geschätzter Preis (€)") {
                        TextField("optional", value: $draft.estimatedPriceEuro, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                let problems = draft.problems
                if !problems.isEmpty, draft.quantity != nil || !draft.trimmedText.isEmpty {
                    Section("Noch nötig") {
                        ForEach(problems, id: \.self) { Label($0.message, systemImage: "exclamationmark.circle") }
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .keyboardDoneToolbar()
            .navigationTitle("Zur Einkaufsliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { save() }.disabled(!draft.problems.isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            try PurchaseService(context: context).addManually(draft)
            dismiss()
        } catch {
            errorText = "Der Eintrag konnte nicht gesichert werden."
        }
    }
}
