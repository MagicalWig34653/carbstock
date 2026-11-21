import CarbStockCore
import SwiftUI

// Gemeinsame Bausteine des Tabs „Einkauf“: Produktfelder, MHD-Feld, Urteil und Begründungszeilen.

extension VerdictTone {
    /// Farbe unterstützt nur; Titel und Symbol tragen das Urteil.
    var color: Color {
        switch self {
        case .buy: .green
        case .partial: .orange
        case .dontBuy: .red
        case .unknown: .secondary
        }
    }
}

extension UserDecision {
    var color: Color {
        switch self {
        case .none: .secondary
        case .bought: .green
        case .skipped: .orange
        }
    }
}

/// Eingabefelder „Neues Produkt“ (Name, Kategorie, Einheit, Carbs je Portion …) für Entscheider und Gekauft-Dialog.
struct NewProductFields: View {
    @Binding var draft: ProductDraft

    var body: some View {
        TextField("Name (Pflicht)", text: $draft.name)
        TextField("Marke (optional)", text: $draft.brand)
        Picker("Kategorie", selection: $draft.category) {
            ForEach(ProductCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        Picker("Basiseinheit", selection: $draft.baseUnit) {
            ForEach(BaseUnit.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if draft.baseUnit == .gram {
            LabeledContent("Portionsgröße (g)") {
                TextField("z. B. 40", value: positive($draft.portionAmount), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
        LabeledContent(draft.baseUnit == .gram ? "Carbs je Portion (g)" : "Carbs je Stück (g)") {
            TextField("z. B. 25", value: positive($draft.carbsPerPortionG), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
        LabeledContent("Fruktose je 1 Glukose") {
            TextField("optional, z. B. 0,8", value: $draft.glucoseFructoseRatio, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    /// Das Formular arbeitet mit „leer = 0“, die Felder zeigen dann den Platzhalter.
    private func positive(_ b: Binding<Double>) -> Binding<Double?> {
        Binding(get: { b.wrappedValue > 0 ? b.wrappedValue : nil }, set: { b.wrappedValue = $0 ?? 0 })
    }
}

/// „Mit MHD“ + Datum, gebunden an einen optionalen Kalendertag.
struct ExpiryFields: View {
    @Binding var expiry: CalendarDay?
    var title = "Mit MHD"

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { expiry != nil },
            set: { expiry = $0 ? (expiry ?? Fmt.today().adding(months: 12)) : nil }))
        if let current = expiry {
            DatePicker("MHD", selection: Binding(
                get: { Fmt.date(from: current) },
                set: { expiry = CalendarDay($0, in: .current) }), displayedComponents: .date)
        }
    }
}

/// Urteil mit Titel, Symbol und Begründungszeilen (je Zeile Regelnummer und Zahlen, AC-K7).
struct OutcomeSections: View {
    let outcome: PurchaseOutcome
    var pricePer100g: Double?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(outcome.title, systemImage: outcome.symbol)
                    .font(.title2.bold()).foregroundStyle(outcome.tone.color)
                if let detail = outcome.detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                if let pricePer100g {
                    Text("\(Fmt.euro(pricePer100g)) je 100 g Carbs").font(.headline).monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } header: { Text("Urteil") }
        Section("Begründung") {
            ForEach(outcome.lines) { ReasonRow(line: $0) }
        }
    }
}

struct ReasonRow: View {
    let line: ReasonLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(line.rule).font(.caption.bold().monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                Text(line.title).font(.subheadline.weight(.semibold))
            }
            Text(line.text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Regel \(line.rule), \(line.title). \(line.text)")
    }
}
