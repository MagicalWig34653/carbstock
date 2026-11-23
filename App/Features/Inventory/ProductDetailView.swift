import CarbStockCore
import SwiftData
import SwiftUI

struct ProductDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let product: Product

    @State private var addingBatch = false
    @State private var bookingBatch: Batch?
    @State private var confirmArchive = false
    @State private var errorText: String?
    @State private var editingFlavor = false
    @State private var flavorText = ""

    private var service: InventoryService { InventoryService(context: context) }
    private var today: CalendarDay { Fmt.today() }

    var body: some View {
        let service = service
        let ledger = service.ledger()
        let summary = service.summary(of: product, ledger: ledger)
        let batches = sortedBatches()
        List {
            Section("Bestand") {
                LabeledContent("Summe") {
                    Text(Fmt.quantity(summary.stock, unit: product.baseUnit))
                        .accessibilityLabel("Summe \(Fmt.quantity(summary.stock, unit: product.baseUnit))")
                }
                LabeledContent("Carbs gesamt", value: Fmt.grams(summary.carbsTotalG))
                if summary.isConflict {
                    Label("Bestand \(summary.stock.formatted()) (Konflikt)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                LabeledContent(product.baseUnit == .gram ? "Carbs je Portion (\(Fmt.grams(product.portionAmount)))" : "Carbs je Stück",
                               value: Fmt.grams(product.carbsPerPortionG))
                Button {
                    flavorText = product.flavor ?? ""
                    editingFlavor = true
                } label: {
                    LabeledContent("Geschmack") {
                        Text(product.flavor ?? "Keiner").foregroundStyle(product.flavor == nil ? .secondary : .primary)
                    }
                    .contentShape(Rectangle()) // ganze Zeile tippbar, nicht nur der Text
                }
                .buttonStyle(.plain)
                .accessibilityHint("Geschmack ändern")
                if product.category == .gel {
                    Toggle("Mit Koffein", isOn: Binding(get: { product.hasCaffeine },
                        set: { v in run { try service.setAdditives(caffeine: v, lactate: product.hasLactate, on: product) } }))
                    Toggle("Mit Laktat", isOn: Binding(get: { product.hasLactate },
                        set: { v in run { try service.setAdditives(caffeine: product.hasCaffeine, lactate: v, on: product) } }))
                }
                if let r = product.glucoseFructoseRatio {
                    LabeledContent("Glukose : Fruktose", value: "1 : \(r.formatted())")
                }
                if product.isArchived {
                    Label("Archiviert", systemImage: "archivebox").foregroundStyle(.secondary)
                }
            }
            Section("Chargen") {
                if batches.isEmpty { Text("Noch keine Charge.").foregroundStyle(.secondary) }
                ForEach(batches) { batch in
                    BatchRow(batch: batch, product: product, stock: ledger.quantity(ofBatch: batch.id), today: today,
                             onTap: { bookingBatch = batch },
                             onCorrect: { run { try service.correctNegative(batch) } })
                        .swipeActions {
                            Button(batch.isArchived ? "Wiederherstellen" : "Archivieren",
                                   systemImage: batch.isArchived ? "arrow.uturn.backward" : "archivebox") {
                                run { try service.setArchived(!batch.isArchived, batch: batch) }
                            }.tint(.gray)
                        }
                }
                Button("Charge hinzufügen", systemImage: "plus.circle") { addingBatch = true }
            }
            if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            Section {
                if product.isArchived {
                    Button("Wiederherstellen", systemImage: "arrow.uturn.backward") { run { try service.restore(product) } }
                } else {
                    Button("Archivieren", systemImage: "archivebox", role: .destructive) { confirmArchive = true }
                }
            }
        }
        .navigationTitle(product.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Geschmack", isPresented: $editingFlavor) {
            TextField("z. B. Zitrone", text: $flavorText)
            Button("Sichern") { run { try service.setFlavor(flavorText, on: product) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Leer lassen, wenn das Produkt keinen Geschmack hat.") }
        .sheet(isPresented: $addingBatch) { AddBatchView(product: product) }
        .sheet(item: $bookingBatch) { BookingSheet(batch: $0, product: product) }
        .confirmationDialog("Produkt archivieren?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archivieren", role: .destructive) {
                run { try service.remove(product) }
                dismiss()
            }
        } message: {
            Text("Buchungen bleiben erhalten. Im Filter „Archiv“ lässt sich das Produkt wiederherstellen.")
        }
    }

    /// Active batches in Core FEFO order, then archived ones.
    private func sortedBatches() -> [Batch] {
        let all = product.batches ?? []
        let active = all.filter { !$0.isArchived }.compactMap { b in b.info.map { (b, $0) } }
            .sorted { BatchInfo.fefoPrecedes($0.1, $1.1) }.map(\.0)
        return active + all.filter(\.isArchived)
    }

    private func run(_ action: () throws -> some Any) {
        do { _ = try action(); errorText = nil } catch { errorText = "Aktion fehlgeschlagen." }
    }
}

private struct BatchRow: View {
    let batch: Batch
    let product: Product
    let stock: Int
    let today: CalendarDay
    let onTap: () -> Void
    let onCorrect: () -> Void

    var body: some View {
        let status = ExpiryBadge.of(batch.expiryDay.flatMap(CalendarDay.init(isoString:)), today: today)
        let per100 = batch.info.flatMap { PriceMetrics.pricePer100gCarbs(batch: $0, product: product.info) }
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Fmt.quantity(stock, unit: product.baseUnit)).font(.headline)
                        Text("von \(Fmt.quantity(batch.quantityPurchased, unit: product.baseUnit))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    StatusLabel(status: status)
                    if let expiry = batch.expiryDay.flatMap(CalendarDay.init(isoString:)) {
                        Text("MHD \(Fmt.date(expiry))").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let per100 {
                        Text("\(Fmt.euro(per100)) je 100 g Carbs").font(.footnote).foregroundStyle(.secondary)
                    }
                    if batch.isArchived { Label("Archiviert", systemImage: "archivebox").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die Buchung für diese Charge")
            if stock < 0 {
                Label("Bestand \(stock.formatted()) (Konflikt)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.subheadline)
                Button("Korrektur buchen", action: onCorrect).buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct AddBatchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var input = BatchInput()

    var body: some View {
        NavigationStack {
            Form {
                BatchFieldsSection(input: $input, unit: product.baseUnit)
            }
            .keyboardDoneToolbar()
            .navigationTitle("Charge hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if (try? InventoryService(context: context).addBatch(
                            to: product, quantity: input.quantity ?? 0, totalPriceCents: input.priceCents,
                            purchaseDay: input.purchaseDay, expiry: input.expiryDay, source: input.source)) != nil {
                            dismiss()
                        }
                    }
                    .disabled((input.quantity ?? 0) <= 0)
                }
            }
        }
    }
}

/// Targeted booking on one batch (outflow with reason, inflow).
struct BookingSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case consume, discard, adjustDown, inflow, adjustUp
        var id: String { rawValue }
        var title: String {
            switch self {
            case .consume: "Verbraucht"
            case .discard: "Entsorgt"
            case .adjustDown: "Korrektur −"
            case .inflow: "Zugang"
            case .adjustUp: "Korrektur +"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let batch: Batch
    let product: Product
    @State private var kind: Kind = .consume
    @State private var quantity = 1

    var body: some View {
        NavigationStack {
            Form {
                Picker("Art", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $quantity, in: 1...100_000) {
                    Text("Menge: \(Fmt.quantity(quantity, unit: product.baseUnit))")
                }
            }
            .navigationTitle("Buchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Buchen") { book() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func book() {
        let service = InventoryService(context: context)
        do {
            switch kind {
            case .consume: try service.book(.consume, quantity: quantity, on: batch)
            case .discard: try service.book(.discard, quantity: quantity, on: batch)
            case .inflow: try service.book(.return, quantity: quantity, on: batch)
            case .adjustDown: try service.adjust(by: -quantity, on: batch)
            case .adjustUp: try service.adjust(by: quantity, on: batch)
            }
            dismiss()
        } catch {}
    }
}
