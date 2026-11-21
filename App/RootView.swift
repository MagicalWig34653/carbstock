import SwiftData
import SwiftUI

/// The five main tabs; settings sit behind the gear button of the inventory.
struct RootView: View {
    let syncMode: Stores.SyncMode
    @Environment(\.modelContext) private var context
    // Observed so the badge follows every booking.
    @Query private var movements: [StockMovement]
    @Query private var batches: [Batch]
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared
    private let scheduler = ReminderScheduler()

    var body: some View {
        let attention = UseFirstSections(InventoryService(context: context).useFirst()).attentionCount
        TabView(selection: $router.selectedTab) {
            Tab("Bestand", systemImage: "shippingbox", value: AppTab.inventory) { InventoryListView(syncMode: syncMode) }
            Tab("Zuerst", systemImage: "clock.badge.exclamationmark", value: AppTab.useFirst) { UseFirstView() }
                .badge(attention)
            Tab("Bedarf", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.demand) { DemandView() }
            Tab("Einkauf", systemImage: "cart", value: AppTab.shopping) { ShoppingView() }
            Tab("Training", systemImage: "bicycle", value: AppTab.training) { TrainingView() }
        }
        // Rebuild the reminders at launch, on return to the foreground and after booking/batch changes (8.3).
        .task { await scheduler.rebuild(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await scheduler.rebuild(context: context) } }
        }
        .onChange(of: changeToken) { _, _ in Task { await scheduler.rebuild(context: context) } }
    }

    /// Changes whenever a movement or a batch's expiry/archive state changes.
    private var changeToken: Int {
        var h = Hasher()
        h.combine(movements.count)
        for b in batches { h.combine(b.id); h.combine(b.expiryDay); h.combine(b.isArchived) }
        return h.finalize()
    }
}

struct PlaceholderView: View {
    let title: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hammer", description: Text("Kommt in einer der nächsten Stufen."))
                .navigationTitle(title)
        }
    }
}

struct SettingsPlaceholderView: View {
    let syncMode: Stores.SyncMode
    var onClose: (() -> Void)?
    var body: some View {
        NavigationStack {
            List {
                DataSettingsSection(syncMode: syncMode)
                ReminderSettingsSection()
                Section("Hinweis") {
                    Text("Carbs/h-Werte sind Planungs-Voreinstellungen, keine medizinische oder ernährungsberatende Empfehlung.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                if let onClose { ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: onClose) } }
            }
        }
    }
}
