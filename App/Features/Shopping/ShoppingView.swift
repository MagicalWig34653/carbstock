import SwiftUI

enum ShoppingSection: String, CaseIterable, Identifiable {
    case decide, list, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .decide: "Entscheiden"
        case .list: "Liste"
        case .history: "Verlauf"
        }
    }
}

/// Tab „Einkauf“ (Spec 4.4): Kauf-Entscheider, Einkaufsliste und Verlauf.
struct ShoppingView: View {
    @State private var section: ShoppingSection = .decide
    @State private var addingEntry = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Bereich", selection: $section) {
                        ForEach(ShoppingSection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                switch section {
                case .decide: OfferDeciderView()
                case .list: ShoppingListView(adding: $addingEntry)
                case .history: PurchaseHistoryView()
                }
            }
            .keyboardDoneToolbar()
            .navigationTitle("Einkauf")
            .toolbar {
                if section == .list {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Eintrag hinzufügen", systemImage: "plus") { addingEntry = true }
                    }
                }
            }
            .sheet(isPresented: $addingEntry) { ShoppingEntryFormView() }
        }
    }
}
