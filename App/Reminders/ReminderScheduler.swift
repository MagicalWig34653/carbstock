import CarbStockCore
import Foundation
import SwiftData
import UserNotifications

/// Geräteeinstellungen der Erinnerungen. Bewusst nur `UserDefaults` (lokal), NICHT iCloud/Key-Value-Store (AC-N7).
struct ReminderSettings {
    static let enabledKey = "reminders.enabledOnThisDevice"
    static let hourKey = "reminders.hour"
    static let minuteKey = "reminders.minute"

    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Standard 09:00.
    var hour: Int {
        get { defaults.object(forKey: Self.hourKey) as? Int ?? 9 }
        nonmutating set { defaults.set(newValue, forKey: Self.hourKey) }
    }

    var minute: Int {
        get { defaults.object(forKey: Self.minuteKey) as? Int ?? 0 }
        nonmutating set { defaults.set(newValue, forKey: Self.minuteKey) }
    }
}

enum NotificationPermission: Equatable, Sendable {
    case notDetermined, denied, allowed
}

/// What the scheduler needs from `UNUserNotificationCenter`; faked in tests.
protocol NotificationCentering: Sendable {
    func permission() async -> NotificationPermission
    func requestPermission() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(_ identifiers: [String]) async
    func add(id: String, title: String, body: String, at: DateComponents) async
}

struct SystemNotificationCenter: NotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }

    func removePending(_ identifiers: [String]) async { center.removePendingNotificationRequests(withIdentifiers: identifiers) }

    func add(id: String, title: String, body: String, at: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: at, repeats: false))
        try? await center.add(request)
    }
}

/// Plans local expiry reminders (spec 8): rebuilds idempotently — remove all own pending requests, plan anew.
/// No network, no push server. The permission is only asked in `enable()`, never at launch (AC-N1).
@MainActor
final class ReminderScheduler {
    static let idPrefix = "carbstock.expiry."

    private let center: any NotificationCentering
    private let settings: ReminderSettings

    init(center: any NotificationCentering = SystemNotificationCenter(), settings: ReminderSettings = ReminderSettings()) {
        self.center = center
        self.settings = settings
    }

    /// Switch on: asks for the permission now (and only now). Returns whether reminders are active.
    @discardableResult
    func enable(context: ModelContext) async -> Bool {
        let granted: Bool
        switch await center.permission() {
        case .allowed: granted = true
        case .notDetermined: granted = await center.requestPermission()
        case .denied: granted = false
        }
        settings.isEnabled = true // the switch stays on; the settings show the way to system settings if denied
        await rebuild(context: context)
        return granted
    }

    func disable(context: ModelContext) async {
        settings.isEnabled = false
        await rebuild(context: context)
    }

    /// Idempotent rebuild: app start, foreground, after booking/batch changes, after settings changes.
    func rebuild(context: ModelContext, now: Date = .now, calendar: Calendar = .current) async {
        await removeOwn()
        guard settings.isEnabled, await center.permission() == .allowed else { return }
        let service = InventoryService(context: context, today: { CalendarDay(now, in: calendar.timeZone) }, now: { now })
        let plans = service.reminderPlan(hour: settings.hour, minute: settings.minute, now: now, calendar: calendar)
        for plan in plans {
            let c = plan.fireDay
            await center.add(id: Self.idPrefix + plan.id, title: plan.title, body: plan.body,
                             at: DateComponents(year: c.year, month: c.month, day: c.day, hour: plan.hour, minute: plan.minute))
        }
    }

    private func removeOwn() async {
        let own = await center.pendingIdentifiers().filter { $0.hasPrefix(Self.idPrefix) }
        if !own.isEmpty { await center.removePending(own) }
    }
}
