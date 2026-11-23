import Foundation
import Testing
@testable import CarbStockCore

/// Externe Aktivitäten, Idempotenz, Duplikate (AC-X1…X5, docs/TRAININGSQUELLEN.md §6.3).
@Suite struct ExternalActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000) // feste Basis, keine Systemuhr
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func act(_ source: ActivitySource = .health, _ id: String = UUID().uuidString, start: Double = 0,
             minutes: Double = 60, sport: ActivitySport = .cycling, title: String? = nil) -> ExternalActivity {
        ExternalActivity(source: source, externalID: id, start: t0.addingTimeInterval(start),
                         movingSeconds: minutes * 60, elapsedSeconds: minutes * 60, sport: sport, title: title)
    }

    // MARK: Identität und Idempotenz (AC-X2)

    @Test func importIsIdempotentPerSourceAndExternalID() {
        let a = act(.health, "H1")
        let first = ActivityStore.apply(incoming: [a], to: [])
        #expect(first.activities.count == 1 && first.report.inserted == 1)
        let again = ActivityStore.apply(incoming: [a], to: first.activities)
        #expect(again.activities.count == 1)
        #expect(again.report == ActivityImportReport(inserted: 0, updated: 0, unchanged: 1))
    }

    @Test func sameExternalIDInDifferentSourcesAreDifferentActivities() {
        let r = ActivityStore.apply(incoming: [act(.health, "42"), act(.strava, "42")], to: [])
        #expect(r.activities.count == 2)
    }

    @Test func changedActivityIsUpdatedKeepingLocalID() {
        let a = act(.strava, "S1", minutes: 60, title: "Morgenfahrt")
        let stored = ActivityStore.apply(incoming: [a], to: []).activities
        var edited = a
        edited.id = UUID() // Quelle kennt die lokale ID nicht
        edited.title = "Morgenfahrt Z2"
        edited.elapsedSeconds = 65 * 60
        let r = ActivityStore.apply(incoming: [edited], to: stored)
        #expect(r.activities.count == 1)
        #expect(r.activities[0].id == a.id)
        #expect(r.activities[0].title == "Morgenfahrt Z2" && r.activities[0].elapsedSeconds == 65 * 60)
        #expect(r.report == ActivityImportReport(inserted: 0, updated: 1, unchanged: 0))
    }

    @Test func nothingIsDeletedByImport() {
        let stored = ActivityStore.apply(incoming: [act(.health, "H1"), act(.health, "H2", start: 7200)], to: []).activities
        let r = ActivityStore.apply(incoming: [act(.health, "H1")], to: stored)
        #expect(r.activities.count == 2)
    }

    @Test func userChoicesSurviveReimport() {
        var stored = ActivityStore.apply(incoming: [act(.health, "H1")], to: []).activities
        stored[0].isIgnored = true
        let r = ActivityStore.apply(incoming: [act(.health, "H1", minutes: 61)], to: stored)
        #expect(r.activities[0].isIgnored)
    }

    @Test func missingAtStravaIsMarkedNotRemoved() {
        let stored = ActivityStore.apply(incoming: [act(.strava, "S1"), act(.strava, "S2", start: 7200), act(.health, "H1", start: 14_400)], to: []).activities
        let marked = ActivityStore.markMissing(source: .strava, presentIDs: ["S1"], in: stored)
        #expect(marked.count == 3)
        #expect(marked.first { $0.externalID == "S2" }!.isMissingAtSource)
        #expect(!marked.first { $0.externalID == "S1" }!.isMissingAtSource)
        #expect(!marked.first { $0.externalID == "H1" }!.isMissingAtSource) // andere Quelle unberührt
        // taucht sie wieder auf, verschwindet die Markierung
        let back = ActivityStore.apply(incoming: [act(.strava, "S2", start: 7200)], to: marked)
        #expect(!back.activities.first { $0.externalID == "S2" }!.isMissingAtSource)
    }

    // MARK: Duplikatregel (AC-X3), Grenzfälle

    @Test func startOffsetBoundary() {
        let base = act(.health, "H", start: 0, minutes: 60)
        let ok = act(.strava, "S", start: 299, minutes: 60)      // 4:59
        let exactly = act(.strava, "S2", start: 300, minutes: 60) // 5:00 gilt noch
        let late = act(.strava, "S3", start: 301, minutes: 60)   // 5:01
        #expect(ActivityMatcher.compare(base, ok) == .duplicate)
        #expect(ActivityMatcher.compare(base, exactly) == .duplicate)
        #expect(ActivityMatcher.compare(base, late) == .maybe)
    }

    @Test func overlapBoundary() {
        // 100 Minuten Fenster, gleicher Start; die andere Aktivität ist kürzer: Überlappung = kürzere / längere.
        let long = act(.health, "H", minutes: 100)
        #expect(ActivityMatcher.compare(long, act(.strava, "S80", minutes: 80)) == .duplicate)   // 80 %
        #expect(ActivityMatcher.compare(long, act(.strava, "S79", minutes: 79)) == .maybe)       // 79 %
        #expect(ActivityMatcher.compare(long, act(.strava, "S40", minutes: 40)) == .distinct)    // klar weniger
    }

    @Test func overlapWithOffsetStart() {
        // Start 4 Minuten später, gleiche Länge 60: Überlappung 56/60 = 93 %
        #expect(ActivityMatcher.compare(act(.health, "H", minutes: 60), act(.strava, "S", start: 240, minutes: 60)) == .duplicate)
        // Start 5 Minuten später, Länge 20: Überlappung 15/20 = 75 % → unsicher
        #expect(ActivityMatcher.compare(act(.health, "H", minutes: 20), act(.strava, "S", start: 300, minutes: 20)) == .maybe)
    }

    @Test func sportMustBeCompatible() {
        let ride = act(.health, "H", sport: .cycling)
        #expect(ActivityMatcher.compare(ride, act(.strava, "S", sport: .running)) == .distinct)
        #expect(ActivityMatcher.compare(ride, act(.strava, "S", sport: .other)) == .duplicate) // unbekannte Sportart ist vereinbar
        #expect(ActivityMatcher.compare(act(.health, "H", sport: .running), act(.strava, "S", sport: .running)) == .duplicate)
    }

    @Test func farApartOrNonOverlappingAreDistinct() {
        let a = act(.health, "H", start: 0, minutes: 60)
        #expect(ActivityMatcher.compare(a, act(.strava, "S", start: 3600, minutes: 60)) == .distinct) // direkt danach
        #expect(ActivityMatcher.compare(a, act(.strava, "S", start: 3 * 3600, minutes: 60)) == .distinct)
    }

    @Test func compareIsSymmetric() {
        let a = act(.health, "H", start: 0, minutes: 60)
        let b = act(.strava, "S", start: 200, minutes: 55)
        #expect(ActivityMatcher.compare(a, b) == ActivityMatcher.compare(b, a))
        let c = act(.strava, "S", start: 301, minutes: 60)
        #expect(ActivityMatcher.compare(a, c) == ActivityMatcher.compare(c, a))
    }

    @Test func sameSourceWithSameWindowIsTheSameRide() {
        // Uhr und Radcomputer-App schreiben beide nach Health: gleiche Quelle, gleiche Fahrt.
        let a = act(.health, "H1"), b = act(.health, "H2", start: 20)
        #expect(ActivityMatcher.compare(a, b) == .duplicate)
        #expect(ActivityGrouper.group([a, b]).groups.count == 1)
        // Zwei Fahrten nacheinander bleiben getrennt.
        let c = act(.health, "H3", start: 2 * 3600)
        #expect(ActivityGrouper.group([a, c]).groups.count == 2)
    }

    // MARK: Gruppen und Zählung (AC-X3, AC-X4)

    @Test func duplicatesFormOneGroupWithSeveralSources() {
        let h = act(.health, "H", start: 0), s = act(.strava, "S", start: 60)
        let result = ActivityGrouper.group([h, s])
        #expect(result.groups.count == 1)
        #expect(Set(result.groups[0].members.map(\.id)) == [h.id, s.id])
        #expect(result.groups[0].sources == [.strava, .health]) // Reihenfolge nach Priorität
        #expect(result.groups[0].primary.source == .strava)     // Standardpriorität: Strava vor Health (O-29)
        #expect(result.counted.count == 1)
    }

    @Test func threeSourcesForSameRide() {
        // Uhr → Health, Strava-API, Strava → Health: drei Einträge, eine Fahrt
        let watch = act(.health, "H1", start: 0)
        let stravaAPI = act(.strava, "S1", start: 30)
        let stravaViaHealth = act(.health, "H2", start: 120) // zweiter Health-Eintrag derselben Fahrt
        let result = ActivityGrouper.group([watch, stravaAPI, stravaViaHealth])
        #expect(result.groups.count == 1)
        #expect(result.groups[0].members.count == 3)
        #expect(result.counted.count == 1)
    }

    @Test func orderOfInputDoesNotChangeResult() {
        let items = [act(.health, "H1", start: 0), act(.strava, "S1", start: 30), act(.health, "H2", start: 7200),
                     act(.strava, "S2", start: 7230)]
        let ref = ActivityGrouper.group(items)
        for perm in [items.reversed(), [items[2], items[0], items[3], items[1]]] {
            let r = ActivityGrouper.group(Array(perm))
            #expect(r.groups.map { Set($0.members.map(\.id)) } == ref.groups.map { Set($0.members.map(\.id)) })
            #expect(r.groups.map(\.primary.id) == ref.groups.map(\.primary.id))
        }
    }

    @Test func priorityCanBeChanged() {
        let h = act(.health, "H", start: 0), s = act(.strava, "S", start: 60)
        let r = ActivityGrouper.group([h, s], priority: [.health, .strava])
        #expect(r.groups[0].primary.source == .health)
    }

    @Test func ignoredActivitiesDoNotCountButStayVisible() {
        var h = act(.health, "H")
        h.isIgnored = true
        let r = ActivityGrouper.group([h, act(.health, "H2", start: 10_000)])
        #expect(r.groups.count == 2)
        #expect(r.counted.count == 1 && r.counted[0].primary.externalID == "H2")
    }

    @Test func maybeDuplicatesAreReportedNotMerged() {
        let h = act(.health, "H", start: 0), s = act(.strava, "S", start: 360) // 6 Minuten
        let r = ActivityGrouper.group([h, s])
        #expect(r.groups.count == 2)
        #expect(r.counted.count == 2) // bis der Nutzer bestätigt, zählen beide
        #expect(r.maybePairs.count == 1)
        #expect(Set([r.maybePairs[0].first.id, r.maybePairs[0].second.id]) == [h.id, s.id])
    }

    @Test func userDecisionsOverrideTheRule() {
        let h = act(.health, "H", start: 0), s = act(.strava, "S", start: 360)
        // Nutzer bestätigt „ist dieselbe Fahrt“
        var decisions = ActivityDecisions()
        decisions.confirmSame(h.id, s.id)
        let merged = ActivityGrouper.group([h, s], decisions: decisions)
        #expect(merged.groups.count == 1 && merged.maybePairs.isEmpty)
        // Nutzer trennt zwei Aktivitäten, die die Regel verbinden würde
        let h2 = act(.health, "H2", start: 0), s2 = act(.strava, "S2", start: 30)
        var apart = ActivityDecisions()
        apart.confirmDifferent(h2.id, s2.id)
        let split = ActivityGrouper.group([h2, s2], decisions: apart)
        #expect(split.groups.count == 2 && split.maybePairs.isEmpty)
    }

    @Test func countedDurationUsesPrimaryOnce() {
        let h = act(.health, "H", minutes: 60), s = act(.strava, "S", start: 30, minutes: 62)
        let r = ActivityGrouper.group([h, s])
        #expect(r.counted.count == 1)
        #expect(r.counted[0].primary.elapsedSeconds == 62 * 60)
        #expect(r.countedSeconds == 62 * 60)
    }

    // MARK: Vorschlag „erledigt“ (AC-X5)

    @Test func suggestsDoneForMatchingPlannedSessionNeverBooks() {
        // t0 = 2027-01-15 08:00 UTC, in Berlin 09:00
        let day = CalendarDay(t0, in: berlin)
        let session = PlannedSession(day: day, type: .z2, durationMinutes: 90)
        let other = PlannedSession(day: day.adding(days: 1), type: .z2, durationMinutes: 90)
        let ride = act(.health, "H", minutes: 85)
        let groups = ActivityGrouper.group([ride]).groups
        let s = CompletionSuggester.suggestions(groups: groups, sessions: [session, other], timeZone: berlin)
        #expect(s.count == 1)
        #expect(s[0].sessionID == session.id && s[0].activityID == ride.id)
        #expect(s[0].durationDifferenceMinutes == -5)
    }

    @Test func noSuggestionForDoneSkippedIgnoredOrOtherSport() {
        let day = CalendarDay(t0, in: berlin)
        let done = PlannedSession(day: day, type: .z2, durationMinutes: 60, status: .done)
        let skipped = PlannedSession(day: day, type: .z2, durationMinutes: 60, status: .skipped)
        let planned = PlannedSession(day: day, type: .z2, durationMinutes: 60)
        let ride = act(.health, "H")
        #expect(CompletionSuggester.suggestions(groups: ActivityGrouper.group([ride]).groups, sessions: [done, skipped], timeZone: berlin).isEmpty)
        var ignored = ride; ignored.isIgnored = true
        #expect(CompletionSuggester.suggestions(groups: ActivityGrouper.group([ignored]).groups, sessions: [planned], timeZone: berlin).isEmpty)
        let run = act(.health, "R", sport: .running)
        #expect(CompletionSuggester.suggestions(groups: ActivityGrouper.group([run]).groups, sessions: [planned], timeZone: berlin).isEmpty)
    }

    @Test func oneActivityFitsOnlyOneSessionAndClosestDurationWins() {
        let day = CalendarDay(t0, in: berlin)
        let short = PlannedSession(day: day, type: .vo2, durationMinutes: 45)
        let long = PlannedSession(day: day, type: .long, durationMinutes: 180)
        let ride = act(.health, "H", minutes: 170)
        let s = CompletionSuggester.suggestions(groups: ActivityGrouper.group([ride]).groups, sessions: [short, long], timeZone: berlin)
        #expect(s.count == 1 && s[0].sessionID == long.id)
    }

    @Test func localDayDecidesNotUTC() {
        // 23:30 UTC am 15.1. ist in Berlin schon der 16.1.
        let late = ExternalActivity(source: .health, externalID: "L", start: Date(timeIntervalSince1970: 1_800_000_000 + 15.5 * 3600),
                                    movingSeconds: 3600, elapsedSeconds: 3600, sport: .cycling)
        let berlinDay = CalendarDay(late.start, in: berlin)
        let session = PlannedSession(day: berlinDay, type: .z2, durationMinutes: 60)
        let s = CompletionSuggester.suggestions(groups: ActivityGrouper.group([late]).groups, sessions: [session], timeZone: berlin)
        #expect(s.count == 1)
    }

    @Test func alreadySuggestedLinkIsNotRepeated() {
        let day = CalendarDay(t0, in: berlin)
        let session = PlannedSession(day: day, type: .z2, durationMinutes: 60)
        let ride = act(.health, "H")
        let s = CompletionSuggester.suggestions(groups: ActivityGrouper.group([ride]).groups, sessions: [session], timeZone: berlin,
                                                handledActivityIDs: [ride.id])
        #expect(s.isEmpty)
    }

    @Test func summerTimeSwitchAndMidnightDecideTheLocalDay() {
        // Berlin: Sommerzeit beginnt am 28.3.2027 um 2:00 (UTC+1 → UTC+2).
        func ride(_ iso: String, minutes: Double = 60) -> ExternalActivity {
            let start = ISO8601DateFormatter().date(from: iso)!
            return ExternalActivity(source: .health, externalID: iso, start: start, movingSeconds: minutes * 60,
                                    elapsedSeconds: minutes * 60, sport: .cycling)
        }
        func day(_ a: ExternalActivity) -> CalendarDay {
            let session = PlannedSession(day: CalendarDay(a.start, in: berlin), type: .z2, durationMinutes: 60)
            let wrong = PlannedSession(day: CalendarDay(a.start, in: berlin).adding(days: -1), type: .z2, durationMinutes: 60)
            let s = CompletionSuggester.suggestions(groups: ActivityGrouper.group([a]).groups, sessions: [wrong, session], timeZone: berlin)
            #expect(s.count == 1 && s[0].sessionID == session.id)
            return session.day
        }
        // 23:30 UTC am 27.3. = 0:30 Winterzeit am 28.3.; 22:30 UTC am 28.3. = 0:30 Sommerzeit am 29.3.
        #expect(day(ride("2027-03-27T23:30:00Z")) == CalendarDay(year: 2027, month: 3, day: 28))
        #expect(day(ride("2027-03-28T22:30:00Z")) == CalendarDay(year: 2027, month: 3, day: 29))
        // Fahrt über Mitternacht (23:30 → 0:30 Ortszeit) gehört zum Starttag.
        #expect(day(ride("2027-03-27T22:30:00Z", minutes: 120)) == CalendarDay(year: 2027, month: 3, day: 27))
    }

    @Test func duplicateRuleIgnoresTimeZonesAndSummerTime() {
        // Dieselbe Fahrt über die Zeitumstellung: Absolutzeit zählt, nicht die Ortszeit.
        let f = ISO8601DateFormatter()
        func ride(_ s: ActivitySource, _ iso: String) -> ExternalActivity {
            ExternalActivity(source: s, externalID: iso, start: f.date(from: iso)!, movingSeconds: 3600, elapsedSeconds: 3600, sport: .cycling)
        }
        let a = ride(.health, "2027-03-28T00:30:00Z"), b = ride(.strava, "2027-03-28T00:33:00+00:00")
        #expect(ActivityMatcher.compare(a, b) == .duplicate)
        let c = ride(.strava, "2027-03-28T01:30:00+01:00") // gleicher Zeitpunkt wie 00:30Z
        #expect(ActivityMatcher.compare(a, c) == .duplicate)
    }
}
