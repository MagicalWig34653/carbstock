import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// Fake source: keine HealthKit-Zugriffe in Tests.
private struct FakeSource: WorkoutSource {
    let source: ActivitySource = .health
    var isAvailable = true
    var access: WorkoutSourceError?
    var fetch: Result<[ExternalActivity], WorkoutSourceError> = .success([])
    func requestAccess() async throws { if let access { throw access } }
    func cyclingWorkouts(since: Date) async throws -> [ExternalActivity] { try fetch.get() }
}

@MainActor
@Suite struct ActivityServiceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let container: ModelContainer // muss am Leben bleiben, sonst stürzt der Kontext ab
    let context: ModelContext
    let service: ActivityService
    let training: TrainingService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        let n = Date(timeIntervalSince1970: 1_800_000_000)
        service = ActivityService(context: context, now: { n })
        let day = CalendarDay(n, in: TimeZone(identifier: "Europe/Berlin")!)
        training = TrainingService(context: context, today: { day })
    }

    func ride(_ id: String, start: Double = 0, minutes: Double = 60, source: ActivitySource = .health) -> ExternalActivity {
        ExternalActivity(source: source, externalID: id, start: now.addingTimeInterval(start),
                         movingSeconds: minutes * 60, elapsedSeconds: minutes * 60, sport: .cycling)
    }

    @Test func refreshImportsAndIsIdempotent() async {
        let source = FakeSource(fetch: .success([ride("A"), ride("B", start: 7200)]))
        let first = await service.refresh(from: source)
        #expect(first == .imported(ActivityImportReport(inserted: 2), fetched: 2))
        let second = await service.refresh(from: source)
        #expect(second == .imported(ActivityImportReport(unchanged: 2), fetched: 2))
        #expect(service.activities().count == 2)
        #expect(try! context.fetch(FetchDescriptor<ImportedActivity>()).count == 2)
    }

    @Test func emptyResultIsNeutralNotAnError() async {
        #expect(await service.refresh(from: FakeSource()) == .nothingFound)
        #expect(service.activities().isEmpty)
    }

    @Test func sourceProblemsAreMapped() async {
        #expect(await service.refresh(from: FakeSource(isAvailable: false)) == .unavailable)
        #expect(await service.refresh(from: FakeSource(fetch: .failure(.deviceLocked))) == .deviceLocked)
        #expect(await service.refresh(from: FakeSource(access: .failed)) == .failed)
        #expect(service.activities().isEmpty)
    }

    @Test func changedWorkoutUpdatesKeepsIgnoredFlag() async throws {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("A", minutes: 60)])))
        let id = service.activities()[0].id
        try service.setIgnored(true, group: service.grouping().groups[0])
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("A", minutes: 70)])))
        let a = service.activities()
        #expect(a.count == 1 && a[0].id == id && a[0].isIgnored && a[0].elapsedSeconds == 70 * 60)
        #expect(service.grouping().counted.isEmpty)
    }

    @Test func duplicatesFromWatchAndStravaViaHealthCountOnce() async {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("W", start: 0), ride("S", start: 90)])))
        let g = service.grouping()
        #expect(g.groups.count == 1 && g.counted.count == 1)
    }

    @Test func userDecisionOverridesRuleAndPersists() async throws {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("W", start: 0), ride("S", start: 360)])))
        #expect(service.grouping().maybePairs.count == 1)
        let ids = service.activities().map(\.id)
        try service.confirmSame(ids[0], ids[1])
        #expect(service.grouping().groups.count == 1 && service.grouping().maybePairs.isEmpty)
        try service.confirmDifferent(ids[1], ids[0]) // Umentscheiden, Reihenfolge egal
        #expect(service.grouping().groups.count == 2 && service.grouping().maybePairs.isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActivityPairDecision>()).count == 1)
    }

    @Test func acceptingSuggestionMarksSessionDoneAndBooksNothing() async throws {
        let day = CalendarDay(now, in: berlin)
        var draft = SessionDraft(day: day); draft.type = .z2; draft.durationMinutes = 60
        let session = try training.addSession(draft)
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("A", minutes: 58)])))
        let suggestions = service.suggestions(sessions: training.sessions().compactMap(\.info), timeZone: berlin)
        #expect(suggestions.count == 1 && suggestions[0].sessionID == session.id)

        try service.accept(suggestions[0], training: training)
        #expect(session.statusRaw == SessionStatus.done.rawValue)
        #expect(try context.fetch(FetchDescriptor<StockMovement>()).isEmpty)
        #expect(service.suggestions(sessions: training.sessions().compactMap(\.info), timeZone: berlin).isEmpty)
    }

    @Test func dismissedSuggestionStaysGoneEvenWhenSecondSourceArrives() async throws {
        let day = CalendarDay(now, in: berlin)
        var draft = SessionDraft(day: day); draft.durationMinutes = 60
        try training.addSession(draft)
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("A")])))
        let s = service.suggestions(sessions: training.sessions().compactMap(\.info), timeZone: berlin)
        try service.dismiss(s[0])
        // dieselbe Fahrt kommt aus einer zweiten Quelle und wird der Gruppe zugeordnet
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("A"), ride("B", start: 45)])))
        #expect(service.suggestions(sessions: training.sessions().compactMap(\.info), timeZone: berlin).isEmpty)
    }

    @Test func deleteAllRemovesImportsAndDecisions() async throws {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("W"), ride("S", start: 360)])))
        let ids = service.activities().map(\.id)
        try service.confirmSame(ids[0], ids[1])
        try BackupService(context: context).deleteAllData()
        #expect(service.activities().isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActivityPairDecision>()).isEmpty)
    }

    @Test func ignoringAMergedRideHidesTheWholeRide() async throws {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("W", start: 0), ride("S", start: 90)])))
        let group = try #require(service.grouping().groups.first)
        #expect(group.members.count == 2)
        try service.setIgnored(true, group: group)
        let hidden = service.grouping()
        #expect(hidden.groups.count == 1 && hidden.counted.isEmpty && hidden.groups[0].primary.isIgnored)
        try service.setIgnored(false, group: hidden.groups[0])
        #expect(service.grouping().counted.count == 1)
    }

    @Test func deleteAllForgetsThatHealthWasConnected() async throws {
        let suite = "carbstock.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ActivityService.connectedKey)
        try BackupService(context: context, defaults: defaults).deleteAllData()
        #expect(defaults.bool(forKey: ActivityService.connectedKey) == false)
    }

    @Test func exportDoesNotContainImportedWorkouts() async throws {
        _ = await service.refresh(from: FakeSource(fetch: .success([ride("SECRET-ID-123")])))
        let data = try BackupService(context: context).exportData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("SECRET-ID-123") && !text.lowercased().contains("health"))
    }
}
