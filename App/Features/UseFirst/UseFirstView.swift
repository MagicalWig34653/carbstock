import CarbStockCore
import SwiftData
import SwiftUI

/// Gliederung der Verbrauch-zuerst-Liste (reine Logik, getestet): abgelaufen · läuft bald ab · weitere.
struct UseFirstSections: Equatable {
    /// "Läuft bald ab" gilt bis einschließlich 60 Tage vor MHD (wie Filter und Erinnerungen).
    static let soonDays = 60

    var expired: [UseFirstEntry]
    var soon: [UseFirstEntry]
    var rest: [UseFirstEntry]

    init(_ entries: [UseFirstEntry]) {
        expired = entries.filter { $0.status == .expired }
        soon = entries.filter { $0.status != .expired && ($0.remainingDays.map { $0 <= Self.soonDays } ?? false) }
        let handled = Set((expired + soon).map(\.id))
        rest = entries.filter { !handled.contains($0.id) }
    }

    /// Number shown as the tab badge: everything that needs a decision soon.
    var attentionCount: Int { expired.count + soon.count }
}

struct UseFirstView: View {
    @Environment(\.modelContext) private var context
    // Observing these makes the list refresh after every booking or batch change.
    @Query private var products: [Product]
    @Query private var movements: [StockMovement]

    @State private var pendingDisposal: Batch?
    @State private var errorText: String?

    private var service: InventoryService { InventoryService(context: context) }

    var body: some View {
        let entries = service.useFirst()
        let sections = UseFirstSections(entries)
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("Nichts zu verbrauchen", systemImage: "checkmark.circle",
                                           description: Text("Es gibt keine Charge mit Restmenge."))
                } else {
                    List {
                        if sections.attentionCount > 0 { banner(sections) }
                        if !sections.expired.isEmpty {
                            Section("Abgelaufen") { ForEach(sections.expired) { row($0) } }
                        }
                        if !sections.soon.isEmpty {
                            Section("Läuft bald ab") { ForEach(sections.soon) { row($0) } }
                        }
                        if !sections.rest.isEmpty {
                            Section("Danach") { ForEach(sections.rest) { row($0) } }
                        }
                        if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
                    }
                }
            }
            .navigationTitle("Verbrauch zuerst")
            .confirmationDialog("Charge entsorgen?", isPresented: Binding(get: { pendingDisposal != nil },
                                                                         set: { if !$0 { pendingDisposal = nil } }),
                                titleVisibility: .visible, presenting: pendingDisposal) { batch in
                Button("Entsorgen", role: .destructive) { dispose(batch) }
                Button("Abbrechen", role: .cancel) {}
            } message: { batch in
                Text("Die Restmenge (\(Fmt.quantity(service.stock(of: batch), unit: batch.product?.baseUnit ?? .piece))) wird als „abgelaufen“ abgebucht. Das lässt sich nur per Korrekturbuchung rückgängig machen.")
            }
        }
    }

    private func banner(_ s: UseFirstSections) -> some View {
        Section {
            var parts: [String] = []
            if !s.expired.isEmpty { parts.append("\(s.expired.count) abgelaufen") }
            if !s.soon.isEmpty { parts.append("\(s.soon.count) laufen in \(UseFirstSections.soonDays) Tagen ab") }
            return Label(parts.joined(separator: ", ") + " – Chargen prüfen", systemImage: "bell.badge")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func row(_ e: UseFirstEntry) -> some View {
        let badge = ExpiryBadge(status: e.status, days: e.remainingDays)
        let batch = products.lazy.flatMap { $0.batches ?? [] }.first { $0.id == e.batch.id }
        return VStack(alignment: .leading, spacing: 4) {
            Text(e.product.displayName).font(.headline)
            Text("\(Fmt.quantity(e.remainingQuantity, unit: e.product.baseUnit)) · \(Fmt.grams(e.carbsG)) Carbs")
                .font(.subheadline)
            StatusLabel(status: badge).fontWeight(e.status == .expired ? .bold : .regular)
            if let d = e.batch.expiryDate { Text("MHD \(Fmt.date(d))").font(.footnote).foregroundStyle(.secondary) }
            if e.status == .expired, let batch {
                if batch.useDespiteExpiry {
                    Label("Wird trotzdem genutzt", systemImage: "hand.thumbsup").font(.footnote)
                    Button("Nicht mehr nutzen") { setDespite(false, batch) }.buttonStyle(.bordered)
                } else {
                    HStack {
                        Button("Entsorgen", role: .destructive) { pendingDisposal = batch }
                        Button("Trotzdem nutzen") { setDespite(true, batch) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(e.status == .expired ? Color.red.opacity(0.12) : nil)
        .accessibilityElement(children: .contain)
    }

    private func dispose(_ batch: Batch) {
        do { try service.dispose(batch); errorText = nil } catch { errorText = "Entsorgen fehlgeschlagen." }
    }

    private func setDespite(_ value: Bool, _ batch: Batch) {
        do { try service.setUseDespiteExpiry(value, on: batch); errorText = nil } catch { errorText = "Aktion fehlgeschlagen." }
    }
}
