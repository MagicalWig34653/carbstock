import CarbStockCore
import SwiftData
import SwiftUI

/// "Produkt anlegen": product + first batch in one go (spec 4.1).
struct ProductFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var flavor = ""
    @State private var hasCaffeine = false
    @State private var hasLactate = false
    @State private var category: ProductCategory = .gel
    @State private var baseUnit: BaseUnit = .piece
    @State private var portion: Double?
    @State private var carbs: Double?
    @State private var ratio: Double?
    @State private var batch = BatchInput()
    @State private var saveError: String?

    private var draft: ProductDraft {
        var d = ProductDraft()
        d.name = name; d.brand = brand; d.flavor = flavor; d.hasCaffeine = hasCaffeine; d.hasLactate = hasLactate; d.category = category; d.baseUnit = baseUnit
        d.portionAmount = portion ?? 0
        d.carbsPerPortionG = carbs ?? 0
        d.glucoseFructoseRatio = ratio
        d.quantity = batch.quantity ?? 0
        d.totalPriceCents = batch.priceCents
        d.expiry = batch.expiryDay
        d.purchaseDay = batch.purchaseDay
        d.source = batch.source
        return d
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produkt") {
                    TextField("Name (Pflicht)", text: $name)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Geschmack (optional)", text: $flavor)
                    Picker("Kategorie", selection: $category) {
                        ForEach(ProductCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if category == .gel {
                        Toggle("Mit Koffein", isOn: $hasCaffeine)
                        Toggle("Mit Laktat", isOn: $hasLactate)
                    }
                    Picker("Basiseinheit", selection: $baseUnit) {
                        ForEach(BaseUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if baseUnit == .gram {
                        LabeledContent("Portionsgröße (g)") {
                            TextField("z. B. 40", value: $portion, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent(baseUnit == .gram ? "Carbs je Portion (g)" : "Carbs je Stück (g)") {
                        TextField("z. B. 25", value: $carbs, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fruktose je 1 Glukose") {
                        TextField("optional, z. B. 0,8", value: $ratio, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                BatchFieldsSection(input: $batch, unit: baseUnit, quantityRequired: false)
                let problems = draft.problems
                if !problems.isEmpty, hasInput {
                    Section("Noch nötig") {
                        ForEach(problems, id: \.self) { Label($0.message, systemImage: "exclamationmark.circle") }
                    }
                }
                if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
            }
            .navigationTitle("Produkt anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!draft.problems.isEmpty)
                }
            }
        }
    }

    private var hasInput: Bool { !name.isEmpty || carbs != nil || batch.quantity != nil }

    private func save() {
        do {
            try InventoryService(context: context).createProduct(draft)
            dismiss()
        } catch {
            saveError = "Das Produkt konnte nicht gesichert werden."
        }
    }
}
