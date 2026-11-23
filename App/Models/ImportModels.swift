import CarbStockCore
import Foundation
import SwiftData

// Imports store: LOCAL ONLY, never mirrored to CloudKit, excluded from device backups and from the JSON export
// (docs/TRAININGSQUELLEN.md §2/§6, AC-X1, App Review 5.1.3(ii)).
//
// Holds only what AC-X1 allows: source, external id, start, duration, sport, title. No route, heart rate,
// power, calories or location. Records here refer to nothing else by relationship (UUIDs only).

@Model
final class ImportedActivity {
    var id: UUID = UUID()
    var sourceRaw: String = ActivitySource.health.rawValue
    var externalID: String = ""
    var start: Date = Date.distantPast
    var movingSeconds: Double = 0
    var elapsedSeconds: Double = 0
    var sportRaw: String = ActivitySport.cycling.rawValue
    var title: String?
    var isIgnored: Bool = false
    var isMissingAtSource: Bool = false
    /// The user answered the "mark session as done" suggestion (accepted or dismissed).
    var suggestionHandled: Bool = false
    var linkedSessionID: UUID?
    var importedAt: Date = Date.now
    var schemaVersion: Int = 1

    init(_ a: ExternalActivity, importedAt: Date = .now) {
        id = a.id
        sourceRaw = a.source.rawValue
        externalID = a.externalID
        start = a.start
        movingSeconds = a.movingSeconds
        elapsedSeconds = a.elapsedSeconds
        sportRaw = a.sport.rawValue
        title = a.title
        isIgnored = a.isIgnored
        isMissingAtSource = a.isMissingAtSource
        self.importedAt = importedAt
    }

    var info: ExternalActivity? {
        guard let source = ActivitySource(rawValue: sourceRaw) else { return nil }
        return ExternalActivity(id: id, source: source, externalID: externalID, start: start, movingSeconds: movingSeconds,
                                elapsedSeconds: elapsedSeconds, sport: ActivitySport(rawValue: sportRaw) ?? .other, title: title,
                                isIgnored: isIgnored, isMissingAtSource: isMissingAtSource)
    }

    func copy(from a: ExternalActivity) {
        start = a.start
        movingSeconds = a.movingSeconds
        elapsedSeconds = a.elapsedSeconds
        sportRaw = a.sport.rawValue
        title = a.title
        isIgnored = a.isIgnored
        isMissingAtSource = a.isMissingAtSource
    }
}

/// The user's answer for a pair of activities ("same ride" or "different"); overrides the matching rule.
@Model
final class ActivityPairDecision {
    var lowID: UUID = UUID()
    var highID: UUID = UUID()
    var isSame: Bool = false
    var createdAt: Date = Date.now
    var schemaVersion: Int = 1

    init(_ pair: ActivityDecisions.Pair, isSame: Bool) {
        lowID = pair.low
        highID = pair.high
        self.isSame = isSame
    }
}
