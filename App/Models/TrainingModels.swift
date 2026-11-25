import CarbStockCore
import Foundation
import SwiftData

// Training store: LOCAL ONLY, never mirrored to CloudKit (spec 11.5, O-01 option B).
// Session planning data is a grey zone under App Review 5.1.3(ii) / DPLA 3.3.3(D).
// Until Lino decides O-01 (or Apple answers in writing), these records stay on the device.
//
// Records here must not have relationships into the inventory store (spec 9.2.3);
// they point at products, batches and sessions by UUID only.
// The same CloudKit-compatible rules apply anyway, so a later switch to option A
// is a configuration change, not a migration.

@Model
final class TrainingSession {
    var id: UUID = UUID()
    var day: String = ""
    var startTime: Date?
    var typeRaw: String = SessionType.z2.rawValue
    var durationMinutes: Int = 60
    var carbsPerHourOverride: Int?
    var statusRaw: String = SessionStatus.planned.rawValue
    var title: String?
    var note: String?
    var sourceRaw: String = "manual"
    var createdAt: Date = Date.now
    var schemaVersion: Int = 1

    init(day: CalendarDay, type: SessionType, durationMinutes: Int, carbsPerHourOverride: Int? = nil, title: String? = nil) {
        self.day = day.isoString
        self.typeRaw = type.rawValue
        self.durationMinutes = durationMinutes
        self.carbsPerHourOverride = carbsPerHourOverride
        self.title = title
    }

    var info: PlannedSession? {
        guard let day = CalendarDay(isoString: day), let type = SessionType(rawValue: typeRaw) else { return nil }
        return PlannedSession(id: id, day: day, type: type, durationMinutes: durationMinutes,
                              carbsPerHourOverride: carbsPerHourOverride,
                              status: SessionStatus(rawValue: statusRaw) ?? .planned,
                              title: title, note: note, startTime: startTime)
    }
}

@Model
final class WeeklyTemplateRecord {
    var id: UUID = UUID()
    var weekdayIndex: Int = 0
    var typeRaw: String = SessionType.z2.rawValue
    var durationMinutes: Int = 60
    var carbsPerHourOverride: Int?
    var validFrom: String = ""
    var validUntil: String?
    var schemaVersion: Int = 1

    init(weekdayIndex: Int, type: SessionType, durationMinutes: Int, validFrom: CalendarDay) {
        self.weekdayIndex = weekdayIndex
        self.typeRaw = type.rawValue
        self.durationMinutes = durationMinutes
        self.validFrom = validFrom.isoString
    }

    var info: WeeklyTemplateEntry? {
        guard let type = SessionType(rawValue: typeRaw), let from = CalendarDay(isoString: validFrom),
              (0...6).contains(weekdayIndex) else { return nil }
        return WeeklyTemplateEntry(id: id, weekdayIndex: weekdayIndex, type: type, durationMinutes: durationMinutes,
                                   carbsPerHourOverride: carbsPerHourOverride, validFrom: from,
                                   validUntil: validUntil.flatMap(CalendarDay.init(isoString:)))
    }
}

/// Only user deviations from the built-in carbs/h table are stored (spec 5.5).
@Model
final class CarbRateOverride {
    var typeRaw: String = SessionType.z2.rawValue
    var carbsPerHour: Int = 60
    var schemaVersion: Int = 1
    /// Wann der Wert zuletzt geändert wurde: bei zwei Datensätzen für dieselbe Art gewinnt der jüngere (M4b).
    /// Additiv mit Vorgabewert; bestehende Datensätze bleiben gültig.
    var updatedAt: Date = Date.now

    init(type: SessionType, carbsPerHour: Int, updatedAt: Date = Date.now) {
        self.typeRaw = type.rawValue
        self.carbsPerHour = carbsPerHour
        self.updatedAt = updatedAt
    }
}

/// Pack lists mirror session dates, so they follow O-01 (local). The "packed" state is
/// derived from `pack`/`reversal` movements with referenceID = item id (spec 5.6).
@Model
final class PackList {
    var id: UUID = UUID()
    var sessionID: UUID?
    var title: String = ""
    var targetCarbsG: Double = 0
    var reservePercent: Int = 10
    var stateRaw: String = "draft" // draft · packing · done
    var createdAt: Date = Date.now
    var schemaVersion: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \PackListItem.packList)
    var items: [PackListItem]? = []

    init(title: String, targetCarbsG: Double, reservePercent: Int, sessionID: UUID? = nil) {
        self.title = title
        self.targetCarbsG = targetCarbsG
        self.reservePercent = reservePercent
        self.sessionID = sessionID
    }
}

@Model
final class PackListItem {
    var id: UUID = UUID()
    var packList: PackList?
    var productID: UUID?
    var batchID: UUID?
    var plannedQuantity: Int = 0
    var plannedCarbsG: Double = 0
    var schemaVersion: Int = 1

    init(productID: UUID, batchID: UUID, plannedQuantity: Int, plannedCarbsG: Double) {
        self.productID = productID
        self.batchID = batchID
        self.plannedQuantity = plannedQuantity
        self.plannedCarbsG = plannedCarbsG
    }
}
