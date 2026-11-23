import CarbStockCore
import SwiftUI

/// Locale-aware display helpers. Internally everything stays Int (base unit, cents) or Double (carbs).
enum Fmt {
    static func quantity(_ n: Int, unit: BaseUnit) -> String {
        "\(n.formatted()) \(unit == .gram ? "g" : "Stk")"
    }

    static func grams(_ g: Double) -> String { "\(g.formatted(.number.precision(.fractionLength(0)))) g" }

    static func euro(_ value: Double) -> String { value.formatted(.currency(code: "EUR")) }

    static func euro(cents: Int) -> String { euro(Double(cents) / 100) }

    static func date(_ day: CalendarDay) -> String { date(from: day).formatted(date: .abbreviated, time: .omitted) }

    static func date(from day: CalendarDay) -> Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
    }

    static func today() -> CalendarDay { CalendarDay(Date.now, in: .current) }
}

extension ProductCategory {
    var title: String {
        switch self {
        case .gel: "Gel"
        case .drink: "Drink"
        case .bar: "Riegel"
        case .jelly: "Jelly"
        case .homemade: "Selbstgemacht"
        }
    }

    var symbol: String {
        switch self {
        case .gel: "drop.fill"
        case .drink: "waterbottle.fill"
        case .bar: "rectangle.fill"
        case .jelly: "circle.hexagongrid.fill"
        case .homemade: "house.fill"
        }
    }
}

extension BaseUnit {
    var title: String { self == .gram ? "Gramm (Pulver)" : "Stück" }
}

extension ExpiryBadge {
    /// Color is never the only signal: every status also has a symbol and text.
    var color: Color {
        switch status {
        case .expired, .red: .red
        case .yellow: Color.warning
        case .green: .green
        case .noExpiry: .secondary
        }
    }
}

struct StatusLabel: View {
    let status: ExpiryBadge
    var body: some View {
        Label(status.text, systemImage: status.symbol)
            .foregroundStyle(status.color)
            .font(.subheadline)
    }
}

/// Form state shared by "Produkt anlegen" and "Charge hinzufügen".
struct BatchInput: Equatable {
    var quantity: Int?
    var priceEuro: Double?
    var hasExpiry = false
    var expiry = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    var purchase = Date.now
    var source = ""

    var priceCents: Int? { priceEuro.map { Int(($0 * 100).rounded()) } }
    var expiryDay: CalendarDay? { hasExpiry ? CalendarDay(expiry, in: .current) : nil }
    var purchaseDay: CalendarDay { CalendarDay(purchase, in: .current) }
}

struct BatchFieldsSection: View {
    @Binding var input: BatchInput
    let unit: BaseUnit
    var quantityRequired = true

    var body: some View {
        Section(quantityRequired ? "Menge und Kauf" : "Erste Charge (optional)") {
            LabeledContent(unit == .gram ? "Menge (g)" : "Menge (Stück)") {
                TextField(quantityRequired ? "Pflicht" : "optional", value: $input.quantity, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Gesamtpreis (€)") {
                TextField("optional", value: $input.priceEuro, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("Mit MHD", isOn: $input.hasExpiry)
            if input.hasExpiry { DatePicker("MHD", selection: $input.expiry, displayedComponents: .date) }
            DatePicker("Kaufdatum", selection: $input.purchase, displayedComponents: .date)
            TextField("Quelle (z. B. Shop, Aktion)", text: $input.source)
        }
    }
}
