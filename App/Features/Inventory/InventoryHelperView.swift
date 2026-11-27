import CarbStockCore
import SwiftData
import SwiftUI

/// Inventarisierungshelfer (Spec 4.6): „Erstaufnahme“ für Neues (Produkt, Menge, MHD, mehrere Chargen am Stück) und
/// „Zählen“ für Vorhandenes (gezählter Ist-Bestand gegen Soll, gebucht wird nur die Differenz als Korrektur).
/// Beides nutzt die vorhandenen Buchungen (`addBatch`, `adjust`); es gibt kein neues Datenfeld.
struct InventoryHelperView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case intake = "Erstaufnahme", count = "Zählen"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .count

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                switch mode {
                case .intake: IntakeView()
                case .count: CountView()
                }
            }
            .keyboardDoneToolbar()
            .navigationTitle("Inventur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: Erstaufnahme

private struct IntakeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.name) private var allProducts: [Product]

    @State private var selected: UUID?
    @State private var quantity: Int?
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var recorded: [String] = []
    @State private var showingNewProduct = false
    @State private var idsBeforeNew: Set<UUID> = []
    @State private var errorText: String?

    private var products: [Product] { allProducts.filter { !$0.isArchived } }
    private var product: Product? { products.first { $0.id == selected } }

    var body: some View {
        Form {
            Section {
                Picker("Produkt", selection: $selected) {
                    Text("Wählen").tag(UUID?.none)
                    ForEach(products) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Button("Neues Produkt anlegen", systemImage: "plus") {
                    idsBeforeNew = Set(allProducts.map(\.id))
                    showingNewProduct = true
                }
            } footer: {
                Text("Für Vorrat, den CarbStock noch nicht kennt. Pro Charge ein Eintrag; das Produkt bleibt danach gewählt.")
            }

            if let product {
                Section("Charge") {
                    LabeledContent(product.baseUnit == .gram ? "Menge (g)" : "Menge (Stück)") {
                        TextField("Pflicht", value: $quantity, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("Mit MHD", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("MHD", selection: $expiry, displayedComponents: .date) }
                    Button("Charge erfassen", systemImage: "checkmark") { record(product) }
                        .disabled((quantity ?? 0) <= 0)
                    if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }
            }

            if !recorded.isEmpty {
                Section("Gerade erfasst") {
                    ForEach(Array(recorded.enumerated()), id: \.offset) { _, line in Text(line) }
                }
            }
        }
        .sheet(isPresented: $showingNewProduct, onDismiss: selectNewProduct) { ProductFormView() }
    }

    private func record(_ product: Product) {
        let day = hasExpiry ? CalendarDay(expiry, in: .current) : nil
        do {
            try InventoryService(context: context).addBatch(to: product, quantity: quantity ?? 0, expiry: day)
            recorded.insert("\(product.displayName): \(Fmt.quantity(quantity ?? 0, unit: product.baseUnit)) · "
                            + (day.map { "MHD \(Fmt.date($0))" } ?? "ohne MHD"), at: 0)
            quantity = nil
            errorText = nil
        } catch {
            errorText = "Das hat nicht geklappt. Bitte versuche es noch einmal."
        }
    }

    private func selectNewProduct() {
        if let new = allProducts.first(where: { !idsBeforeNew.contains($0.id) }) { selected = new.id }
    }
}

// MARK: Zählen

private struct CountSummary {
    var adjusted: [(name: String, delta: Int, unit: BaseUnit)]
    var unchanged: Int
    var notCounted: Int
}

private struct CountView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.name) private var allProducts: [Product]

    @State private var counts: [UUID: Int] = [:]
    @State private var confirming = false
    @State private var summary: CountSummary?
    @State private var errorText: String?

    private var service: InventoryService { InventoryService(context: context) }
    private var products: [Product] { allProducts.filter { !$0.isArchived && !service.activeBatches(of: $0).isEmpty } }

    var body: some View {
        let ledger = service.ledger()
        let rows = products.map { ($0, service.stock(of: $0, ledger: ledger)) }
        let differing = rows.filter { p, stock in counts[p.id].map { $0 != stock } ?? false }
        Form {
            if let summary {
                summarySection(summary)
            } else {
                Section {
                    if rows.isEmpty {
                        Text("Noch kein Vorrat zum Zählen. Neuen Vorrat legst du mit der Erstaufnahme an.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows, id: \.0.id) { product, stock in
                        CountRow(product: product, stock: stock, counted: binding(product.id))
                    }
                } footer: {
                    Text("Zähle, was wirklich da ist. Gebucht wird nur die Differenz, als Korrektur mit der Notiz „Inventur“. Leere Felder bleiben unberührt.")
                }
                if !rows.isEmpty {
                    Section {
                        Button(CountText.differencesToBook(differing.count), systemImage: "checkmark") { confirming = true }
                            .disabled(differing.isEmpty)
                        if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
                    }
                }
            }
        }
        .confirmationDialog(CountText.correctionsToBook(differing.count), isPresented: $confirming, titleVisibility: .visible) {
            Button("Buchen") { book(rows) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das lässt sich nur per Storno oder Korrektur rückgängig machen.")
        }
    }

    private func binding(_ id: UUID) -> Binding<Int?> {
        Binding(get: { counts[id] }, set: { counts[id] = $0 })
    }

    @ViewBuilder private func summarySection(_ s: CountSummary) -> some View {
        Section("Zusammenfassung") {
            if s.adjusted.isEmpty { Text("Keine Abweichungen, nichts gebucht.") }
            ForEach(Array(s.adjusted.enumerated()), id: \.offset) { _, a in
                LabeledContent(a.name) { Text((a.delta > 0 ? "+" : "−") + Fmt.quantity(abs(a.delta), unit: a.unit)) }
            }
            if s.unchanged > 0 { Text("\(s.unchanged) ohne Abweichung") }
            if s.notCounted > 0 { Text("\(s.notCounted) nicht gezählt").foregroundStyle(.secondary) }
        }
        Section {
            Button("Weiter zählen", systemImage: "arrow.counterclockwise") { summary = nil }
        }
    }

    private func book(_ rows: [(Product, Int)]) {
        var adjusted: [(name: String, delta: Int, unit: BaseUnit)] = []
        var unchanged = 0
        do {
            for (product, stock) in rows {
                guard let counted = counts[product.id] else { continue }
                if counted == stock { unchanged += 1; continue }
                let booked = try service.applyCount(counted, to: product)
                if !booked.isEmpty { adjusted.append((product.displayName, counted - stock, product.baseUnit)) }
            }
        } catch {
            errorText = "Das hat nicht geklappt. Bitte versuche es noch einmal."
            return
        }
        summary = CountSummary(adjusted: adjusted, unchanged: unchanged, notCounted: rows.count - counts.count)
        counts = [:]
        errorText = nil
    }
}

private struct CountRow: View {
    let product: Product
    let stock: Int
    @Binding var counted: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.displayName).font(.headline)
            Text("Erwartet: \(Fmt.quantity(stock, unit: product.baseUnit))").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                TextField("Gezählt", value: $counted, format: .number)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Gezählt, \(product.displayName)")
                if let counted {
                    Text(Self.differenceText(counted - stock)).font(.subheadline).monospacedDigit()
                }
            }
        }
    }

    static func differenceText(_ diff: Int) -> String {
        diff == 0 ? "stimmt" : (diff > 0 ? "+\(diff)" : "−\(abs(diff))")
    }
}
