import Foundation

// Planung der Ablauf-Erinnerungen (Spec 8.2, 8.3): reine Funktion, kein UserNotifications, keine Uhr.

/// One planned local notification (collective for one trigger day).
public struct ReminderPlan: Hashable, Sendable, Identifiable {
    /// Stable per trigger day, so a rebuild is idempotent.
    public let id: String
    public let fireDay: CalendarDay
    public let hour: Int
    public let minute: Int
    public let title: String
    public let body: String
    public let batchCount: Int
}

public enum ReminderPlanner {
    /// Days before the best-before date at which reminders fire (O-11 working assumption).
    public static let leadDays = [60, 30]
    public static let maxNames = 3
    public static let defaultLimit = 50

    /// Plans the notifications from the current state.
    ///
    /// Only batches with remaining quantity > 0, a best-before date, not archived (batch or product) and not
    /// expired. Per trigger day ONE notification. Only future times (`today` + `minuteOfDay` is "now"), earliest
    /// first, at most `limit`. The text names at most three products and never gives nutrition advice.
    public static func plan(products: [ProductInfo], batches: [BatchInfo], ledger: Ledger, today: CalendarDay,
                            minuteOfDay: Int, hour: Int = 9, minute: Int = 0,
                            limit: Int = defaultLimit) -> [ReminderPlan] {
        guard limit > 0 else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let fireMinute = hour * 60 + minute
        var perDay: [CalendarDay: [(expiry: CalendarDay, name: String)]] = [:]
        for b in batches.sorted(by: BatchInfo.fefoPrecedes) {
            guard !b.isArchived, let expiry = b.expiryDate, expiry >= today,
                  let p = byID[b.productID], !p.isArchived, ledger.quantity(ofBatch: b.id) > 0 else { continue }
            for lead in leadDays {
                let day = expiry.adding(days: -lead)
                guard day > today || (day == today && fireMinute > minuteOfDay) else { continue }
                perDay[day, default: []].append((expiry, p.name))
            }
        }
        return perDay.keys.sorted().prefix(limit).map { day in
            // Names: earliest best-before first, then alphabetical (deterministic).
            let entries = (perDay[day] ?? []).sorted { ($0.expiry, $0.name) < ($1.expiry, $1.name) }.map(\.name)
            var names: [String] = []
            for name in entries where !names.contains(name) { names.append(name) }
            let shown = names.prefix(maxNames).joined(separator: ", ")
            let ending = names.count > maxNames ? " …" : "."
            let n = entries.count
            let text = n == 1 ? "1 Charge läuft bald ab: \(shown)" : "\(n) Chargen laufen bald ab: \(shown)"
            return ReminderPlan(id: "expiry-\(day.isoString)", fireDay: day, hour: hour, minute: minute,
                                title: "Läuft bald ab", body: text + ending + " Chargen prüfen.", batchCount: n)
        }
    }
}
