import CarbStockCore
import SwiftData
import SwiftUI

struct InventoryListView: View {
    let syncMode: Stores.SyncMode
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.name) private var products: [Product]

    @State private var filter = InventoryFilter()
    @State private var showingForm = false
    @State private var showingSettings = false
    @State private var errorText: String?

    var body: some View {
        let service = InventoryService(context: context)
        let ledger = service.ledger()
        let summaries = products.map { ($0, service.summary(of: $0, ledger: ledger)) }
        let today = Fmt.today()
        let visible = InventoryList.apply(filter, to: summaries.map(\.1), today: today)
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.1.id, $0.0) })
        NavigationStack {
            Group {
                if products.isEmpty {
                    ContentUnavailableView {
                        Label("Noch kein Vorrat", systemImage: "shippingbox")
                    } description: {
                        Text("Lege dein erstes Gel, Pulver oder deinen ersten Riegel an.")
                    } actions: {
                        Button("Produkt anlegen") { showingForm = true }.buttonStyle(.borderedProminent)
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: filter.search)
                } else {
                    List(visible) { row in
                        if let product = byID[row.id] {
                            NavigationLink { ProductDetailView(product: product) } label: {
                                ProductRowView(summary: row, today: today,
                                               onStep: { step($0, product, service) })
                            }
                            .swipeActions(edge: .trailing) {
                                Button("−1", systemImage: "minus.circle") { step(-1, product, service) }.tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button("+1", systemImage: "plus.circle") { step(+1, product, service) }.tint(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bestand")
            .searchable(text: $filter.search, prompt: "Name oder Marke")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Einstellungen", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterMenu
                    Button("Produkt anlegen", systemImage: "plus") { showingForm = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red).padding(8) }
            }
            .sheet(isPresented: $showingForm) { ProductFormView() }
            .sheet(isPresented: $showingSettings) {
                SettingsPlaceholderView(syncMode: syncMode, onClose: { showingSettings = false })
            }
        }
    }

    private var filterMenu: some View {
        Menu("Filter", systemImage: filter.category == nil && filter.mode == .all
             ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
            Picker("Ansicht", selection: $filter.mode) {
                ForEach(InventoryFilterMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Kategorie", selection: $filter.category) {
                Text("Alle Kategorien").tag(ProductCategory?.none)
                ForEach(ProductCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag(ProductCategory?.some($0)) }
            }
        }
    }

    private func step(_ direction: Int, _ product: Product, _ service: InventoryService) {
        do { try service.quickBook(direction, on: product); errorText = nil } catch { errorText = "Buchung nicht möglich (kein nutzbarer Bestand?)." }
    }
}

struct ProductRowView: View {
    let summary: ProductSummary
    let today: CalendarDay
    let onStep: (Int) -> Void

    var body: some View {
        let status = ExpiryBadge.of(summary.earliestExpiry, today: today)
        let unitStock = Fmt.quantity(summary.stock, unit: summary.baseUnit)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.category.symbol)
                .frame(width: 28).foregroundStyle(.tint)
                .accessibilityLabel(summary.category.title)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name).font(.headline)
                if let detail = summary.detailLine {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if summary.isConflict {
                    Label("Bestand \(summary.stock.formatted()) (Konflikt)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.subheadline)
                } else {
                    Text("\(unitStock) · \(Fmt.grams(summary.carbsTotalG)) Carbs").font(.subheadline)
                }
                if summary.hasStock { StatusLabel(status: status) }
            }
            Spacer(minLength: 4)
            if !summary.isArchived {
                HStack(spacing: 4) {
                    Button { onStep(-1) } label: { Image(systemName: "minus.circle.fill").imageScale(.large) }
                        .accessibilityLabel("Eins abbuchen")
                    Button { onStep(+1) } label: { Image(systemName: "plus.circle.fill").imageScale(.large) }
                        .accessibilityLabel("Eins zubuchen")
                }
                .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
