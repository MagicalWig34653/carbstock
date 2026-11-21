import CarbStockCore
import SwiftData
import Testing
@testable import CarbStock

@MainActor
@Suite struct StoresTests {
    @Test func inMemoryContainerHoldsBothStores() throws {
        let built = Stores.make(inMemory: true)
        #expect(built.syncMode == .inMemory)
        let context = built.container.mainContext
        let gel = Product(name: "Gel", category: .gel, baseUnit: .piece, carbsPerPortionG: 25)
        let batch = Batch(product: gel, purchaseDay: CalendarDay(year: 2026, month: 11, day: 21), quantityPurchased: 10)
        context.insert(gel)
        context.insert(StockMovement(batch: batch, type: .purchase, delta: 10, idempotencyKey: "purchase:\(batch.id)"))
        context.insert(TrainingSession(day: CalendarDay(year: 2026, month: 11, day: 22), type: .long, durationMinutes: 240))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<StockMovement>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TrainingSession>()) == 1)
        #expect(batch.info?.productID == gel.id)
    }
}
