import SwiftData
import SwiftUI
import UserNotifications

@main
struct CarbStockApp: App {
    private let stores: Stores.Built

    init() {
        // Tests and UI tests pass -CarbStockInMemory so nothing touches iCloud or the real store.
        var inMemory = ProcessInfo.processInfo.arguments.contains("-CarbStockInMemory")
        #if DEBUG
        // Schema-Werkzeug (G1): nie auf dem echten Speicher.
        if CloudKitSchemaTool.isRequested(ProcessInfo.processInfo.arguments) { inMemory = true }
        #endif
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
            #if DEBUG
            if CloudKitSchemaTool.isRequested(ProcessInfo.processInfo.arguments) {
                CloudKitSchemaToolView()
            } else {
                RootView(syncMode: stores.syncMode)
            }
            #else
            RootView(syncMode: stores.syncMode)
            #endif
        }
        .modelContainer(stores.container)
    }
}
