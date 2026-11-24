import CarbStockCore
import Foundation
import SwiftData
import Testing
@testable import CarbStock

/// M4b: Ein frisch installiertes CarbStock ist neutral: keine Vorbelegung, keine festen Werte, und das Bedarf-Tab
/// zeigt statt einer Tabelle aus Nullen nur den Leerzustand.
@MainActor
@Suite struct EmptyStateTests {
    let container: ModelContainer
    let context: ModelContext
    let service: TrainingService

    init() {
        container = Stores.make(inMemory: true).container
        context = container.mainContext
        service = TrainingService(context: context)
    }

    @Test func freshStoreHoldsNoData() throws {
        #expect(try context.fetch(FetchDescriptor<Product>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Batch>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StockMovement>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrainingSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WeeklyTemplateRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CarbRateOverride>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PackList>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PurchaseEvaluation>()).isEmpty)
        #expect(service.userRates().isEmpty)
    }

    @Test func emptyDemandNamesNoRunwayAndShowsNoForecast() {
        let report = service.report()
        #expect(RunwayStatement(simulation: report.simulation, series: report.series) == .unknown)
        #expect(!DemandScreen.showsForecast(report), "Ohne Bedarf und ohne Vorrat gehört keine Tabelle aus Nullen auf den Bildschirm")
        #expect(service.stockBreakdown().isEmpty)
    }

    @Test func forecastAppearsAsSoonAsThereIsStockOrDemand() throws {
        var draft = ProductDraft()
        draft.name = "Testgel"
        draft.carbsPerPortionG = 40
        draft.quantity = 3
        _ = try InventoryService(context: context).createProduct(draft)
        #expect(DemandScreen.showsForecast(service.report()))
    }
}
