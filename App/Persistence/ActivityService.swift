import CarbStockCore
import Foundation
import SwiftData

/// Imported workouts (Imports store, local only). Reads from a `WorkoutSource`, keeps the import idempotent,
/// groups duplicates and offers "mark session as done" suggestions. Never books stock and never writes anywhere
/// but the local Imports store and the status of a session the user confirmed (AC-X4, AC-X5).
@MainActor
final class ActivityService {
    enum Outcome: Equatable {
        case imported(ActivityImportReport, fetched: Int)
        /// Nothing came back: either no cycling workouts or no permission. Apple does not tell which (docs §2).
        case nothingFound
        case unavailable
        case deviceLocked
        case failed
    }

    /// Device-local flag (UserDefaults): Health was read on this device, so opening "Fahrten" reads again on its own.
    nonisolated static let connectedKey = "healthConnectedOnThisDevice"

    /// How far back a refresh looks (the longest forecast window is 84 days).
    nonisolated static let lookbackDays = 90

    private let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = { Date.now }) {
        self.context = context
        self.now = now
    }

    // MARK: Import (AC-X2)

    func refresh(from source: some WorkoutSource) async -> Outcome {
        guard source.isAvailable else { return .unavailable }
        let since = now().addingTimeInterval(-Double(Self.lookbackDays) * 86_400)
        let fetched: [ExternalActivity]
        do {
            try await source.requestAccess()
            fetched = try await source.cyclingWorkouts(since: since)
        } catch WorkoutSourceError.deviceLocked {
            return .deviceLocked
        } catch WorkoutSourceError.unavailable {
            return .unavailable
        } catch {
            return .failed
        }
        guard !fetched.isEmpty else { return .nothingFound }
        do {
            let report = try store(fetched)
            return .imported(report, fetched: fetched.count)
        } catch {
            return .failed
        }
    }

    /// Idempotent upsert over (source, externalID). Nothing is removed.
    @discardableResult
    func store(_ incoming: [ExternalActivity]) throws -> ActivityImportReport {
        let records = try context.fetch(FetchDescriptor<ImportedActivity>())
        let existing = records.compactMap(\.info)
        let result = ActivityStore.apply(incoming: incoming, to: existing)
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for a in result.activities {
            if let record = byID[a.id] {
                record.copy(from: a)
            } else {
                context.insert(ImportedActivity(a, importedAt: now()))
            }
        }
        try context.save()
        return result.report
    }

    // MARK: Reading

    func activities() -> [ExternalActivity] {
        ((try? context.fetch(FetchDescriptor<ImportedActivity>())) ?? []).compactMap(\.info)
    }

    func decisions() -> ActivityDecisions {
        var d = ActivityDecisions()
        for r in (try? context.fetch(FetchDescriptor<ActivityPairDecision>())) ?? [] {
            if r.isSame { d.confirmSame(r.lowID, r.highID) } else { d.confirmDifferent(r.lowID, r.highID) }
        }
        return d
    }

    func grouping() -> GroupingResult {
        ActivityGrouper.group(activities(), decisions: decisions())
    }

    /// Open suggestions: planned sessions with a matching completed ride on the same day.
    func suggestions(sessions: [PlannedSession], timeZone: TimeZone = .current) -> [CompletionSuggestion] {
        let result = grouping()
        let handledMembers = Set(records().filter(\.suggestionHandled).map(\.id))
        let handledPrimaries = result.groups.filter { g in g.members.contains { handledMembers.contains($0.id) } }.map { $0.primary.id }
        return CompletionSuggester.suggestions(groups: result.groups, sessions: sessions, timeZone: timeZone,
                                               handledActivityIDs: Set(handledPrimaries))
    }

    // MARK: User actions

    /// The user confirmed: the session becomes "done". No booking, no stock change (AC-X5).
    func accept(_ suggestion: CompletionSuggestion, training: TrainingService) throws {
        guard let session = training.sessions().first(where: { $0.id == suggestion.sessionID }) else { return }
        try training.setStatus(.done, on: session)
        if let r = record(suggestion.activityID) {
            r.suggestionHandled = true
            r.linkedSessionID = session.id
        }
        try context.save()
    }

    func dismiss(_ suggestion: CompletionSuggestion) throws {
        record(suggestion.activityID)?.suggestionHandled = true
        try context.save()
    }

    /// Hides or shows a whole ride: every entry of the group, so a merged ride cannot keep counting through its
    /// other entries (the group's primary is the first entry that is not hidden).
    func setIgnored(_ ignored: Bool, group: ActivityGroup) throws {
        let ids = Set(group.members.map(\.id))
        for r in records() where ids.contains(r.id) { r.isIgnored = ignored }
        try context.save()
    }

    func confirmSame(_ a: UUID, _ b: UUID) throws { try decide(a, b, same: true) }
    func confirmDifferent(_ a: UUID, _ b: UUID) throws { try decide(a, b, same: false) }

    private func decide(_ a: UUID, _ b: UUID, same: Bool) throws {
        let pair = ActivityDecisions.Pair(a, b)
        for old in (try context.fetch(FetchDescriptor<ActivityPairDecision>())) where old.lowID == pair.low && old.highID == pair.high {
            context.delete(old)
        }
        context.insert(ActivityPairDecision(pair, isSame: same))
        try context.save()
    }

    /// Removes every imported workout and decision from this device. Health itself is untouched.
    func deleteAll() throws {
        try context.delete(model: ImportedActivity.self)
        try context.delete(model: ActivityPairDecision.self)
        try context.save()
    }

    private func records() -> [ImportedActivity] { (try? context.fetch(FetchDescriptor<ImportedActivity>())) ?? [] }
    private func record(_ id: UUID) -> ImportedActivity? { records().first { $0.id == id } }
}
