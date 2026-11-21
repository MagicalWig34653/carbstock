import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// In-memory stand-in for the notification center. Appends on `add` (like a naive scheduler would),
/// so duplicates show up if the scheduler does not clean up first.
final class FakeCenter: NotificationCentering, @unchecked Sendable {
    var status: NotificationPermission
    var grantsOnRequest: Bool
    var requests = 0
    var pending: [(id: String, body: String, at: DateComponents)] = []

    init(status: NotificationPermission, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    func permission() async -> NotificationPermission { status }

    func requestPermission() async -> Bool {
        requests += 1
        status = grantsOnRequest ? .allowed : .denied
        return grantsOnRequest
    }

    func pendingIdentifiers() async -> [String] { pending.map(\.id) }
    func removePending(_ identifiers: [String]) async { pending.removeAll { identifiers.contains($0.id) } }
    func add(id: String, title: String, body: String, at: DateComponents) async { pending.append((id, body, at)) }
}

@MainActor
@Suite struct ReminderSchedulerTests {
    let container: ModelContainer
    let context: ModelContext
    var gmt: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        return c
    }
    /// 2026-11-21 06:00 GMT.
    let now = Date(timeIntervalSince1970: 1_795_240_800)
    let today = CalendarDay(year: 2026, month: 11, day: 21)

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
    }

    func settings() -> ReminderSettings {
        ReminderSettings(defaults: UserDefaults(suiteName: "reminder-test-\(UUID().uuidString)")!)
    }

    func product(expiringIn days: Int) throws -> (Product, Batch) {
        let service = InventoryService(context: context, today: { today })
        var d = ProductDraft()
        d.name = "Gel"; d.carbsPerPortionG = 25
        let p = try service.createProduct(d)
        let b = try service.addBatch(to: p, quantity: 4, expiry: today.adding(days: days))
        return (p, b)
    }

    // AC-N1: no permission request at launch / rebuild.
    @Test func rebuildNeverAsksForPermission() async throws {
        _ = try product(expiringIn: 100)
        let center = FakeCenter(status: .notDetermined)
        let scheduler = ReminderScheduler(center: center, settings: settings())
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        #expect(center.requests == 0 && center.pending.isEmpty)
    }

    @Test func enablingAsksOnceAndSchedules() async throws {
        _ = try product(expiringIn: 100)
        let center = FakeCenter(status: .notDetermined)
        let s = settings()
        let scheduler = ReminderScheduler(center: center, settings: s)
        #expect(await scheduler.enable(context: context))
        #expect(center.requests == 1 && s.isEnabled)
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        #expect(center.requests == 1) // not asked again
        #expect(center.pending.count == 2)
        #expect(center.pending.allSatisfy { $0.id.hasPrefix(ReminderScheduler.idPrefix) && $0.at.hour == 9 && $0.at.minute == 0 })
    }

    // AC-N2: denied → nothing scheduled, nothing breaks, switch state kept for the hint.
    @Test func deniedSchedulesNothing() async throws {
        _ = try product(expiringIn: 100)
        let center = FakeCenter(status: .notDetermined, grantsOnRequest: false)
        let s = settings()
        let scheduler = ReminderScheduler(center: center, settings: s)
        #expect(await scheduler.enable(context: context) == false)
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        #expect(center.pending.isEmpty)
        #expect(UseFirstSections(InventoryService(context: context, today: { today }).useFirst()).soon.isEmpty) // in-app list works regardless
    }

    // AC-N5: rebuild is idempotent, foreign requests stay untouched.
    @Test func rebuildIsIdempotentAndLeavesForeignRequests() async throws {
        _ = try product(expiringIn: 100)
        let center = FakeCenter(status: .allowed)
        let s = settings()
        s.isEnabled = true
        center.pending.append(("other.app.request", "x", DateComponents()))
        let scheduler = ReminderScheduler(center: center, settings: s)
        for _ in 0..<3 { await scheduler.rebuild(context: context, now: now, calendar: gmt) }
        #expect(center.pending.count == 3)
        #expect(Set(center.pending.map(\.id)).count == 3)
        #expect(center.pending.contains { $0.id == "other.app.request" })
    }

    // AC-N4: consuming the last unit removes the reminder at the next rebuild; time change moves it.
    @Test func lastUnitConsumedAndTimeChangeApplyOnRebuild() async throws {
        let (p, b) = try product(expiringIn: 100)
        let center = FakeCenter(status: .allowed)
        let s = settings()
        s.isEnabled = true
        s.hour = 7; s.minute = 15
        let scheduler = ReminderScheduler(center: center, settings: s)
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        #expect(center.pending.count == 2 && center.pending.allSatisfy { $0.at.hour == 7 && $0.at.minute == 15 })
        let service = InventoryService(context: context, today: { today })
        try service.book(.consume, quantity: 4, on: b)
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        #expect(center.pending.isEmpty)
        _ = p
    }

    @Test func disablingRemovesOwnRequests() async throws {
        _ = try product(expiringIn: 100)
        let center = FakeCenter(status: .allowed)
        let s = settings()
        let scheduler = ReminderScheduler(center: center, settings: s)
        await scheduler.enable(context: context)
        await scheduler.rebuild(context: context, now: now, calendar: gmt)
        await scheduler.disable(context: context)
        #expect(center.pending.isEmpty && !s.isEnabled)
    }

    // AC-N7: device switch lives in local UserDefaults only, never in iCloud key-value storage.
    @Test func deviceSwitchIsLocalOnly() {
        let name = "reminder-local-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let s = ReminderSettings(defaults: defaults)
        #expect(!s.isEnabled && s.hour == 9 && s.minute == 0) // default off, 09:00
        s.isEnabled = true
        #expect(defaults.bool(forKey: ReminderSettings.enabledKey))
        #expect(NSUbiquitousKeyValueStore.default.object(forKey: ReminderSettings.enabledKey) == nil)
        defaults.removePersistentDomain(forName: name)
    }
}
