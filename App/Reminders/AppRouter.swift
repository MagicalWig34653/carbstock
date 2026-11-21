import Observation
import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case inventory, useFirst, demand, shopping, training
}

/// Which tab is open; a tap on a reminder switches to "Zuerst".
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: AppTab = .inventory
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// The center holds its delegate weakly, so keep one alive.
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppRouter.shared.selectedTab = .useFirst }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
