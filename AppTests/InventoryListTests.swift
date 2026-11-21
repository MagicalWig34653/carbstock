import CarbStockCore
import Foundation
import Testing
@testable import CarbStock

@Suite struct InventoryListTests {
    let today = CalendarDay(year: 2026, month: 11, day: 21)

    func row(_ name: String, brand: String? = nil, _ cat: ProductCategory = .gel,
             expiries: [CalendarDay?] = [], archived: Bool = false) -> ProductSummary {
        ProductSummary(id: UUID(), name: name, brand: brand, category: cat, baseUnit: .piece, isArchived: archived,
                       stock: expiries.count, carbsTotalG: 0, earliestExpiry: expiries.compactMap { $0 }.min(),
                       batchesWithStock: expiries)
    }

    // AC-B5
    @Test func searchIsCaseInsensitiveOverNameAndBrand() {
        let rows = [row("Maurten Gel 100"), row("Riegel", brand: "GELato"), row("Drink Mix", .drink)]
        let found = InventoryList.apply(InventoryFilter(search: "gel"), to: rows, today: today)
        #expect(found.map(\.name) == ["Maurten Gel 100", "Riegel"])
        #expect(InventoryList.apply(InventoryFilter(search: "GEL"), to: rows, today: today).count == 2)
    }

    @Test func categoryAndExpiryFilters() {
        let soon = row("Bald", expiries: [today.adding(days: 60)])
        let later = row("Spät", expiries: [today.adding(days: 61)])
        let expired = row("Alt", .bar, expiries: [today.adding(days: -1), nil])
        let none = row("Ohne", .drink, expiries: [nil])
        let all = [soon, later, expired, none]
        func names(_ f: InventoryFilter) -> [String] { InventoryList.apply(f, to: all, today: today).map(\.name) }
        #expect(names(InventoryFilter(mode: .expiringSoon)) == ["Bald"])
        #expect(names(InventoryFilter(mode: .expired)) == ["Alt"])
        #expect(names(InventoryFilter(mode: .noExpiry)) == ["Alt", "Ohne"])
        #expect(names(InventoryFilter(category: .drink)) == ["Ohne"])
        #expect(names(InventoryFilter()) == ["Alt", "Bald", "Ohne", "Spät"])
    }
}
