import CarbStockCore
import Foundation

// Pure drafts and labels for the training forms (no SwiftUI, no persistence), so they are unit-testable.

enum TrainingLimits {
    static let durationMinutes = 1...1440
    /// Plausibility bound for a carbs/h entry; it only catches typos, the app gives no advice (spec 10.2).
    static let carbsPerHour = 1...150
}

/// Editable copy of a session (spec 5.5).
struct SessionDraft: Equatable, Sendable {
    enum Problem: Error, Equatable, Sendable { case durationOutOfRange, rateOutOfRange }

    var day: CalendarDay
    var type: SessionType = .z2
    var durationMinutes: Int = 60
    /// Nil = use the value of the type (only this session deviates when set, AC-P1).
    var carbsPerHourOverride: Int?
    var title: String = ""
    var note: String = ""

    init(day: CalendarDay) { self.day = day }

    init(_ s: TrainingSession) {
        day = CalendarDay(isoString: s.day) ?? CalendarDay(Date.now, in: .current)
        type = SessionType(rawValue: s.typeRaw) ?? .z2
        durationMinutes = s.durationMinutes
        carbsPerHourOverride = s.carbsPerHourOverride
        title = s.title ?? ""
        note = s.note ?? ""
    }

    var problems: [Problem] {
        var p: [Problem] = []
        if !TrainingLimits.durationMinutes.contains(durationMinutes) { p.append(.durationOutOfRange) }
        if let r = carbsPerHourOverride, !TrainingLimits.carbsPerHour.contains(r) { p.append(.rateOutOfRange) }
        return p
    }

    /// Demand of this session with the current type rates (live preview in the form).
    func demandG(userRates: [SessionType: Int]) -> Double {
        DemandCalculator.sessionDemandG(durationMinutes: durationMinutes,
            carbsPerHour: DemandCalculator.carbsPerHour(type: type, sessionOverride: carbsPerHourOverride, userRates: userRates))
    }
}

/// Editable copy of a weekly-template entry (spec 5.5, O-08).
struct TemplateDraft: Equatable, Sendable {
    enum Problem: Error, Equatable, Sendable { case durationOutOfRange, rateOutOfRange, endBeforeStart }

    var weekdayIndex: Int
    var type: SessionType = .z2
    var durationMinutes: Int = 60
    var carbsPerHourOverride: Int?
    var validFrom: CalendarDay
    var validUntil: CalendarDay?

    init(weekdayIndex: Int, validFrom: CalendarDay) {
        self.weekdayIndex = weekdayIndex
        self.validFrom = validFrom
    }

    init?(_ r: WeeklyTemplateRecord) {
        guard let e = r.info else { return nil }
        weekdayIndex = e.weekdayIndex
        type = e.type
        durationMinutes = e.durationMinutes
        carbsPerHourOverride = e.carbsPerHourOverride
        validFrom = e.validFrom
        validUntil = e.validUntil
    }

    var problems: [Problem] {
        var p: [Problem] = []
        if !TrainingLimits.durationMinutes.contains(durationMinutes) { p.append(.durationOutOfRange) }
        if let r = carbsPerHourOverride, !TrainingLimits.carbsPerHour.contains(r) { p.append(.rateOutOfRange) }
        if let u = validUntil, u < validFrom { p.append(.endBeforeStart) }
        return p
    }

    func demandG(userRates: [SessionType: Int]) -> Double {
        DemandCalculator.sessionDemandG(durationMinutes: durationMinutes,
            carbsPerHour: DemandCalculator.carbsPerHour(type: type, sessionOverride: carbsPerHourOverride, userRates: userRates))
    }
}

extension SessionType {
    var title: String {
        switch self {
        case .vo2: "VO₂max"
        case .threshold: "Schwelle"
        case .z2: "Z2"
        case .long: "Longride"
        case .recovery: "Regeneration"
        }
    }

    var symbol: String {
        switch self {
        case .vo2, .threshold: "bolt.fill"
        case .z2: "figure.outdoor.cycle"
        case .long: "road.lanes"
        case .recovery: "leaf.fill"
        }
    }
}

extension SessionStatus {
    var title: String {
        switch self {
        case .planned: "Geplant"
        case .done: "Erledigt"
        case .skipped: "Ausgefallen"
        }
    }
}

enum Weekday {
    static let names = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static func name(_ index: Int) -> String { names.indices.contains(index) ? names[index] : "?" }
    static func short(_ index: Int) -> String { String(name(index).prefix(2)) }
}

extension Fmt {
    /// 240 → "4 h", 90 → "1 h 30 min", 45 → "45 min".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "Mo 23.11." style for session rows.
    static func weekdayDate(_ day: CalendarDay) -> String {
        "\(Weekday.short(day.isoWeekdayIndex)) \(date(from: day).formatted(.dateTime.day().month(.abbreviated)))"
    }

    static func weeks(_ w: Double) -> String { w.formatted(.number.precision(.fractionLength(1))) }
}
