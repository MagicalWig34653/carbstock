#if DEBUG
import CarbStockCore
import Foundation
import SwiftData

/// Debug-only demo data (`-CarbStockSampleData`), used for screenshots.
@MainActor
enum SampleData {
    static func insert(into context: ModelContext) {
        let service = InventoryService(context: context)
        let today = CalendarDay(Date.now, in: .current)

        var gel = ProductDraft()
        gel.name = "Energy Gel 100"; gel.brand = "Maurten"; gel.category = .gel; gel.carbsPerPortionG = 25
        gel.glucoseFructoseRatio = 0.8; gel.quantity = 12; gel.totalPriceCents = 4200; gel.expiry = today.adding(months: 8)
        if let p = try? service.createProduct(gel) {
            _ = try? service.addBatch(to: p, quantity: 6, totalPriceCents: 2100, expiry: today.adding(days: 40), source: "Black Friday")
        }

        var powder = ProductDraft()
        powder.name = "Beta Fuel"; powder.brand = "SiS"; powder.category = .drink; powder.baseUnit = .gram
        powder.portionAmount = 40; powder.carbsPerPortionG = 36; powder.quantity = 1000; powder.totalPriceCents = 2500
        powder.expiry = today.adding(months: 4)
        _ = try? service.createProduct(powder)

        var bar = ProductDraft()
        bar.name = "Riegel Salz"; bar.category = .bar; bar.carbsPerPortionG = 30; bar.quantity = 5
        _ = try? service.createProduct(bar)

        // Training: Wochenvorlage (Di Schwelle, Do Z2, So Longride) und eine Einzel-Session.
        let training = TrainingService(context: context)
        for (weekday, type, minutes) in [(1, SessionType.threshold, 90), (3, .z2, 120), (6, .long, 240)] {
            var t = TemplateDraft(weekdayIndex: weekday, validFrom: today)
            t.type = type; t.durationMinutes = minutes
            _ = try? training.addTemplateEntry(t)
        }
        var s = SessionDraft(day: today.adding(days: 2)); s.type = .vo2; s.durationMinutes = 75; s.title = "Intervalle"
        _ = try? training.addSession(s)
    }
}
#endif
