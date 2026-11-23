import Foundation

// Externe Aktivitäten (Apple Health, Strava) und Duplikaterkennung.
// Spec/Plan: docs/TRAININGSQUELLEN.md §6.3 (AC-X1…X5).
//
// Reine Logik, keine Systemuhr, keine Persistenz. Gespeichert wird nur, was AC-X1 erlaubt:
// Quelle, externe ID, Start, Dauer, Sportart, Titel. Keine Route, kein Puls, keine Leistung,
// keine Kalorien. Nichts wird hier gelöscht: Duplikate werden zu Gruppen zusammengefasst.

public enum ActivitySource: String, CaseIterable, Codable, Sendable {
    case strava, health

    /// Standardpriorität bei Duplikaten (O-29): Strava vor Health.
    public static let defaultPriority: [ActivitySource] = [.strava, .health]
}

public enum ActivitySport: String, CaseIterable, Codable, Sendable {
    case cycling, running, walking, swimming, other
}

public struct ExternalActivity: Hashable, Sendable, Codable, Identifiable {
    /// Lokale ID. Identität gegenüber der Quelle ist (source, externalID), nicht diese ID.
    public var id: UUID
    public var source: ActivitySource
    /// Health: UUID des `HKWorkout` (nur auf diesem Gerät belegt); Strava: Aktivitäts-ID.
    public var externalID: String
    public var start: Date
    public var movingSeconds: Double
    public var elapsedSeconds: Double
    public var sport: ActivitySport
    public var title: String?
    /// Vom Nutzer ausgeblendet: zählt nicht, bleibt sichtbar und überlebt jeden erneuten Import.
    public var isIgnored: Bool
    /// Bei Strava gelöscht (AC-X2): lokal behalten, aber markiert.
    public var isMissingAtSource: Bool

    public init(id: UUID = UUID(), source: ActivitySource, externalID: String, start: Date,
                movingSeconds: Double, elapsedSeconds: Double, sport: ActivitySport, title: String? = nil,
                isIgnored: Bool = false, isMissingAtSource: Bool = false) {
        self.id = id
        self.source = source
        self.externalID = externalID
        self.start = start
        self.movingSeconds = movingSeconds
        self.elapsedSeconds = elapsedSeconds
        self.sport = sport
        self.title = title
        self.isIgnored = isIgnored
        self.isMissingAtSource = isMissingAtSource
    }

    public var end: Date { start.addingTimeInterval(elapsedSeconds) }

    /// Gleichheit der Inhalte, die eine Quelle liefert (ohne lokale Zustände).
    func sameSourceContent(as other: ExternalActivity) -> Bool {
        start == other.start && movingSeconds == other.movingSeconds && elapsedSeconds == other.elapsedSeconds
            && sport == other.sport && title == other.title
    }
}

// MARK: - Import (AC-X2)

public struct ActivityImportReport: Hashable, Sendable {
    public var inserted: Int
    public var updated: Int
    public var unchanged: Int
    public init(inserted: Int = 0, updated: Int = 0, unchanged: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
    }
}

public enum ActivityStore {
    /// Idempotenter Abgleich über (Quelle, externe ID). Bekannte werden aktualisiert (lokale ID und Nutzerzustand
    /// bleiben), neue angelegt. Es wird nichts entfernt. Kommt eine Aktivität nochmals vor, verschwindet ihre
    /// „bei der Quelle gelöscht“-Markierung.
    public static func apply(incoming: [ExternalActivity], to existing: [ExternalActivity])
        -> (activities: [ExternalActivity], report: ActivityImportReport) {
        var result = existing
        var index: [Key: Int] = [:]
        for (i, a) in result.enumerated() { index[Key(a)] = i }
        var report = ActivityImportReport()
        // Kommt ein Schlüssel im selben Abruf zweimal vor, gilt der letzte.
        var latest: [Key: ExternalActivity] = [:]
        var order: [Key] = []
        for a in incoming {
            let k = Key(a)
            if latest[k] == nil { order.append(k) }
            latest[k] = a
        }
        for k in order {
            let a = latest[k]!
            if let i = index[k] {
                let old = result[i]
                if old.sameSourceContent(as: a) && !old.isMissingAtSource {
                    report.unchanged += 1
                } else {
                    var merged = a
                    merged.id = old.id
                    merged.isIgnored = old.isIgnored
                    merged.isMissingAtSource = false
                    result[i] = merged
                    report.updated += 1
                }
            } else {
                var fresh = a
                fresh.isMissingAtSource = false
                index[k] = result.count
                result.append(fresh)
                report.inserted += 1
            }
        }
        return (result, report)
    }

    /// Markiert Aktivitäten einer Quelle, die im letzten vollständigen Abruf nicht mehr vorkamen. Löscht nichts.
    /// Nur nach einem **vollständigen** Abruf aufrufen (nicht nach Fehler oder Teilabruf).
    public static func markMissing(source: ActivitySource, presentIDs: Set<String>, in activities: [ExternalActivity])
        -> [ExternalActivity] {
        activities.map { a in
            guard a.source == source, !presentIDs.contains(a.externalID), !a.isMissingAtSource else { return a }
            var m = a
            m.isMissingAtSource = true
            return m
        }
    }

    private struct Key: Hashable {
        let source: ActivitySource
        let externalID: String
        init(_ a: ExternalActivity) { source = a.source; externalID = a.externalID }
    }
}

// MARK: - Duplikatregel (AC-X3)

public enum ActivityMatch: Hashable, Sendable {
    case duplicate   // sicher dieselbe Fahrt
    case maybe       // „Vielleicht doppelt“: eine Bedingung knapp verfehlt
    case distinct
}

public enum ActivityMatcher {
    /// Höchstens 5 Minuten Startabstand (einschließlich).
    public static let duplicateStartSeconds: Double = 300
    /// Bis 15 Minuten Startabstand gilt bei sonst passenden Werten als „vielleicht“.
    public static let maybeStartSeconds: Double = 900

    /// Überlappung = gemeinsames Zeitfenster geteilt durch das **längere** der beiden Fenster
    /// (strenger als durch das kürzere). Sicher ab 80 %, „vielleicht“ ab 60 %.
    public static func compare(_ a: ExternalActivity, _ b: ExternalActivity) -> ActivityMatch {
        guard compatible(a.sport, b.sport) else { return .distinct }
        let startDiff = abs(a.start.timeIntervalSince(b.start))
        let overlap = max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
        let longer = max(a.elapsedSeconds, b.elapsedSeconds)
        guard longer > 0 else { return .distinct }
        // Ganzzahl-Vergleich ohne Rundungsfehler: overlap/longer >= 0.8 ⇔ 5·overlap >= 4·longer
        let overlapSure = overlap * 5 >= longer * 4
        let overlapMaybe = overlap * 5 >= longer * 3
        if startDiff <= duplicateStartSeconds {
            if overlapSure { return .duplicate }
            if overlapMaybe { return .maybe }
        } else if startDiff <= maybeStartSeconds, overlapSure {
            return .maybe
        }
        return .distinct
    }

    /// Gleiche Sportart, oder eine Seite ist unbekannt („other“).
    static func compatible(_ a: ActivitySport, _ b: ActivitySport) -> Bool {
        a == b || a == .other || b == .other
    }
}

// MARK: - Nutzerentscheidungen

/// Entscheidungen des Nutzers zu Paaren; sie gehen der Regel vor. Wird lokal gespeichert (nie iCloud).
public struct ActivityDecisions: Hashable, Sendable, Codable {
    public struct Pair: Hashable, Sendable, Codable {
        public let low: UUID
        public let high: UUID
        public init(_ a: UUID, _ b: UUID) {
            if a.uuidString <= b.uuidString { low = a; high = b } else { low = b; high = a }
        }
    }
    public private(set) var same: Set<Pair> = []
    public private(set) var different: Set<Pair> = []
    public init() {}

    public mutating func confirmSame(_ a: UUID, _ b: UUID) {
        same.insert(Pair(a, b)); different.remove(Pair(a, b))
    }
    public mutating func confirmDifferent(_ a: UUID, _ b: UUID) {
        different.insert(Pair(a, b)); same.remove(Pair(a, b))
    }
    public mutating func clear(_ a: UUID, _ b: UUID) {
        same.remove(Pair(a, b)); different.remove(Pair(a, b))
    }
}

// MARK: - Gruppen und Zählung (AC-X3, AC-X4)

public struct ActivityGroup: Hashable, Sendable, Identifiable {
    /// Alle Einträge derselben Fahrt, nach Priorität geordnet (der erste ist `primary`).
    public let members: [ExternalActivity]
    public var id: UUID { primary.id }
    /// Maßgeblicher Eintrag (Dauer, Titel). Bevorzugt nicht ausgeblendet, nicht bei der Quelle gelöscht, dann Priorität.
    public var primary: ExternalActivity { members[0] }
    public var sources: [ActivitySource] {
        var seen: [ActivitySource] = []
        for m in members where !seen.contains(m.source) { seen.append(m.source) }
        return seen
    }
    /// Zählt für Verbrauch und Statistik (AC-X4): mindestens ein Eintrag ist nicht ausgeblendet.
    public var counts: Bool { !primary.isIgnored }
}

public struct MaybePair: Hashable, Sendable {
    public let first: ExternalActivity
    public let second: ExternalActivity
}

public struct GroupingResult: Sendable {
    public let groups: [ActivityGroup]
    public let maybePairs: [MaybePair]
    /// Gruppen, die einmal zählen (AC-X4).
    public var counted: [ActivityGroup] { groups.filter(\.counts) }
    /// Summe der verstrichenen Zeit der maßgeblichen Einträge aller zählenden Gruppen.
    public var countedSeconds: Double { counted.reduce(0) { $0 + $1.primary.elapsedSeconds } }
}

public enum ActivityGrouper {
    public static func group(_ activities: [ExternalActivity],
                             priority: [ActivitySource] = ActivitySource.defaultPriority,
                             decisions: ActivityDecisions = ActivityDecisions()) -> GroupingResult {
        // Feste Reihenfolge, damit das Ergebnis nicht von der Eingabereihenfolge abhängt.
        let sorted = activities.sorted(by: stableOrder)
        let n = sorted.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != c { let next = parent[c]; parent[c] = r; c = next }
            return r
        }
        func members(of root: Int) -> [Int] { (0..<n).filter { find($0) == root } }
        func wouldJoinDifferent(_ i: Int, _ j: Int) -> Bool {
            let ri = find(i), rj = find(j)
            if ri == rj { return false }
            for a in members(of: ri) {
                for b in members(of: rj) where decisions.different.contains(.init(sorted[a].id, sorted[b].id)) { return true }
            }
            return false
        }

        var maybe: [(Int, Int)] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                let pair = ActivityDecisions.Pair(sorted[i].id, sorted[j].id)
                if decisions.different.contains(pair) { continue }
                let verdict: ActivityMatch = decisions.same.contains(pair) ? .duplicate : ActivityMatcher.compare(sorted[i], sorted[j])
                switch verdict {
                case .duplicate:
                    if !wouldJoinDifferent(i, j) { parent[find(j)] = find(i) }
                case .maybe: maybe.append((i, j))
                case .distinct: break
                }
            }
        }

        var byRoot: [Int: [ExternalActivity]] = [:]
        for i in 0..<n { byRoot[find(i), default: []].append(sorted[i]) }
        let groups = byRoot.values
            .map { ActivityGroup(members: $0.sorted { primaryOrder($0, $1, priority) }) }
            .sorted { stableOrder($0.primary, $1.primary) }
        let maybePairs = maybe
            .filter { find($0.0) != find($0.1) }
            .map { MaybePair(first: sorted[$0.0], second: sorted[$0.1]) }
        return GroupingResult(groups: groups, maybePairs: maybePairs)
    }

    private static func stableOrder(_ a: ExternalActivity, _ b: ExternalActivity) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.source != b.source { return a.source.rawValue < b.source.rawValue }
        if a.externalID != b.externalID { return a.externalID < b.externalID }
        return a.id.uuidString < b.id.uuidString
    }

    private static func primaryOrder(_ a: ExternalActivity, _ b: ExternalActivity, _ priority: [ActivitySource]) -> Bool {
        if a.isIgnored != b.isIgnored { return !a.isIgnored }
        if a.isMissingAtSource != b.isMissingAtSource { return !a.isMissingAtSource }
        let pa = priority.firstIndex(of: a.source) ?? Int.max
        let pb = priority.firstIndex(of: b.source) ?? Int.max
        if pa != pb { return pa < pb }
        return stableOrder(a, b)
    }
}

// MARK: - Vorschlag „erledigt“ (AC-X5)

public struct CompletionSuggestion: Hashable, Sendable {
    public let activityID: UUID
    public let sessionID: UUID
    /// Dauer der Aktivität minus geplante Dauer, in Minuten (gerundet). Nur als Hinweis.
    public let durationDifferenceMinutes: Int
}

public enum CompletionSuggester {
    /// Schlägt vor, geplante Sessions als erledigt zu markieren. Bucht nie etwas: der Nutzer bestätigt.
    /// Passend = gleicher lokaler Tag, Session noch geplant, Aktivität zählt und ist Rad (oder unbekannt).
    /// Jede Aktivität und jede Session kommt höchstens einmal vor; kleinster Dauerunterschied zuerst.
    public static func suggestions(groups: [ActivityGroup], sessions: [PlannedSession], timeZone: TimeZone,
                                   handledActivityIDs: Set<UUID> = []) -> [CompletionSuggestion] {
        let planned = sessions.filter { $0.status == .planned }
        var candidates: [(diff: Int, abs: Int, start: Date, activity: UUID, session: UUID)] = []
        for g in groups where g.counts && !handledActivityIDs.contains(g.primary.id) {
            let a = g.primary
            guard a.sport == .cycling || a.sport == .other else { continue }
            let day = CalendarDay(a.start, in: timeZone)
            for s in planned where s.day == day {
                let diff = Int((a.elapsedSeconds / 60).rounded()) - s.durationMinutes
                candidates.append((diff, Swift.abs(diff), a.start, a.id, s.id))
            }
        }
        candidates.sort {
            if $0.abs != $1.abs { return $0.abs < $1.abs }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.session.uuidString < $1.session.uuidString
        }
        var usedActivities = Set<UUID>(), usedSessions = Set<UUID>()
        var out: [CompletionSuggestion] = []
        for c in candidates where !usedActivities.contains(c.activity) && !usedSessions.contains(c.session) {
            usedActivities.insert(c.activity)
            usedSessions.insert(c.session)
            out.append(CompletionSuggestion(activityID: c.activity, sessionID: c.session, durationDifferenceMinutes: c.diff))
        }
        return out
    }
}
