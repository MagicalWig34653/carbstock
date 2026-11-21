import CarbStockCore
import Foundation
import SwiftData

/// Writes and reads of the Training store (sessions, weekly template, carbs/h overrides) and the combined
/// forecast. Training records live in the local configuration (O-01 B); they refer to nothing in the
/// inventory store, the forecast merely reads both (spec 9.2.3).
@MainActor
final class TrainingService {
    enum Failure: Error, Equatable {
        case invalidSession([SessionDraft.Problem])
        case invalidTemplate([TemplateDraft.Problem])
        case rateOutOfRange
    }

    private let context: ModelContext
    private let today: () -> CalendarDay

    init(context: ModelContext, today: @escaping () -> CalendarDay = { CalendarDay(Date.now, in: .current) }) {
        self.context = context
        self.today = today
    }

    // MARK: Sessions

    func sessions() -> [TrainingSession] {
        let all = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
        return all.sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
    }

    @discardableResult
    func addSession(_ draft: SessionDraft) throws -> TrainingSession {
        guard draft.problems.isEmpty else { throw Failure.invalidSession(draft.problems) }
        let s = TrainingSession(day: draft.day, type: draft.type, durationMinutes: draft.durationMinutes,
                                carbsPerHourOverride: draft.carbsPerHourOverride)
        apply(draft, to: s)
        context.insert(s)
        try context.save()
        return s
    }

    func update(_ session: TrainingSession, with draft: SessionDraft) throws {
        guard draft.problems.isEmpty else { throw Failure.invalidSession(draft.problems) }
        session.day = draft.day.isoString
        session.typeRaw = draft.type.rawValue
        session.durationMinutes = draft.durationMinutes
        session.carbsPerHourOverride = draft.carbsPerHourOverride
        apply(draft, to: session)
        try context.save()
    }

    private func apply(_ draft: SessionDraft, to s: TrainingSession) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = title.isEmpty ? nil : title
        s.note = note.isEmpty ? nil : note
    }

    func setStatus(_ status: SessionStatus, on session: TrainingSession) throws {
        session.statusRaw = status.rawValue
        try context.save()
    }

    func delete(_ session: TrainingSession) throws {
        context.delete(session)
        try context.save()
    }

    // MARK: Weekly template

    func templateRecords() -> [WeeklyTemplateRecord] {
        let all = (try? context.fetch(FetchDescriptor<WeeklyTemplateRecord>())) ?? []
        return all.sorted { ($0.weekdayIndex, $0.validFrom) < ($1.weekdayIndex, $1.validFrom) }
    }

    @discardableResult
    func addTemplateEntry(_ draft: TemplateDraft) throws -> WeeklyTemplateRecord {
        guard draft.problems.isEmpty else { throw Failure.invalidTemplate(draft.problems) }
        let r = WeeklyTemplateRecord(weekdayIndex: draft.weekdayIndex, type: draft.type,
                                     durationMinutes: draft.durationMinutes, validFrom: draft.validFrom)
        r.carbsPerHourOverride = draft.carbsPerHourOverride
        r.validUntil = draft.validUntil?.isoString
        context.insert(r)
        try context.save()
        return r
    }

    func update(_ record: WeeklyTemplateRecord, with draft: TemplateDraft) throws {
        guard draft.problems.isEmpty else { throw Failure.invalidTemplate(draft.problems) }
        record.weekdayIndex = draft.weekdayIndex
        record.typeRaw = draft.type.rawValue
        record.durationMinutes = draft.durationMinutes
        record.carbsPerHourOverride = draft.carbsPerHourOverride
        record.validFrom = draft.validFrom.isoString
        record.validUntil = draft.validUntil?.isoString
        try context.save()
    }

    func delete(_ record: WeeklyTemplateRecord) throws {
        context.delete(record)
        try context.save()
    }

    // MARK: Carbs per hour (spec 5.5: only deviations are stored)

    func userRates() -> [SessionType: Int] {
        let all = (try? context.fetch(FetchDescriptor<CarbRateOverride>())) ?? []
        var out: [SessionType: Int] = [:]
        for r in all { if let t = SessionType(rawValue: r.typeRaw) { out[t] = r.carbsPerHour } }
        return out
    }

    /// `nil` (or the built-in value) removes the deviation, so no record is stored for the default.
    func setRate(_ perHour: Int?, for type: SessionType) throws {
        if let perHour, !TrainingLimits.carbsPerHour.contains(perHour) { throw Failure.rateOutOfRange }
        let all = (try? context.fetch(FetchDescriptor<CarbRateOverride>())) ?? []
        let mine = all.filter { $0.typeRaw == type.rawValue }
        // Heal duplicates (should not happen locally, but two records for one type must not survive).
        for extra in mine.dropFirst() { context.delete(extra) }
        let isDefault = perHour == nil || perHour == CarbRate.builtIn(type).defaultPerHour
        if isDefault {
            if let first = mine.first { context.delete(first) }
        } else if let first = mine.first {
            first.carbsPerHour = perHour!
        } else {
            context.insert(CarbRateOverride(type: type, carbsPerHour: perHour!))
        }
        try context.save()
    }

    // MARK: Forecast (spec 4.3, 7.2)

    /// Demand series, windows 7/28/84 and runway over inventory + training.
    func report(windows: [Int] = [7, 28, 84]) -> ForecastReport {
        let (products, batches) = inventorySnapshot()
        return Forecast.run(today: today(), products: products, batches: batches,
                            ledger: InventoryService(context: context, today: today).ledger(),
                            sessions: sessions().compactMap(\.info),
                            template: templateRecords().compactMap(\.info),
                            userRates: userRates(), windows: windows)
    }

    func inventorySnapshot() -> (products: [ProductInfo], batches: [BatchInfo]) {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        return (products.map(\.info), products.flatMap { $0.batches ?? [] }.compactMap(\.info))
    }

    func stockBreakdown() -> [StockBreakdown.Share] {
        let (products, batches) = inventorySnapshot()
        return StockBreakdown.carbsByCategory(products: products, batches: batches,
                                              ledger: InventoryService(context: context, today: today).ledger())
    }
}
