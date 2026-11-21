import SwiftData
import SwiftUI
import UserNotifications

@main
struct CarbStockApp: App {
    private let stores: Stores.Built

    init() {
        // Tests and UI tests pass -CarbStockInMemory so nothing touches iCloud or the real store.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-CarbStockInMemory")
        stores = Stores.make(inMemory: inMemory)
        // Delegate only: asking for the permission happens in the settings switch (AC-N1).
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CarbStockSampleData") {
            SampleData.insert(into: stores.container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(syncMode: stores.syncMode)
        }
        .modelContainer(stores.container)
    }
}
