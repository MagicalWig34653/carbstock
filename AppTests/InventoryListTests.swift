import CarbStockCore
import Foundation
import SwiftUI
import Testing
@testable import CarbStock

@Suite struct InventoryListTests {
    let today = CalendarDay(year: 2026, month: 11, day: 21)

    func row(_ name: String, brand: String? = nil, flavor: String? = nil, _ cat: ProductCategory = .gel,
             expiries: [CalendarDay?] = [], archived: Bool = false) -> ProductSummary {
        ProductSummary(id: UUID(), name: name, brand: brand, flavor: flavor, category: cat, baseUnit: .piece, isArchived: archived,
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

    @Test func searchFindsFlavor() {
        let rows = [row("Gel", flavor: "Zitrone"), row("Gel", flavor: "Cola"), row("Riegel")]
        #expect(InventoryList.apply(InventoryFilter(search: "zitr"), to: rows, today: today).map(\.flavor) == ["Zitrone"])
        #expect(InventoryList.apply(InventoryFilter(search: "COLA"), to: rows, today: today).count == 1)
    }

    @Test func sameNameSortsByFlavorAndDisplayNameShowsIt() {
        let rows = [row("Gel", flavor: "Zitrone"), row("Gel", flavor: "Cola"), row("Gel")]
        let sorted = InventoryList.apply(InventoryFilter(), to: rows, today: today)
        #expect(sorted.map(\.displayName) == ["Gel", "Gel · Cola", "Gel · Zitrone"])
    }

    // M4b: Ist die Liste leer, obwohl es Produkte gibt, nennt die App den richtigen Grund.
    @Test func emptyListNamesTheRightReason() {
        let gel = row("Gel", expiries: [today.adding(days: 100)])
        let old = row("Alt", archived: true)
        func state(_ f: InventoryFilter, _ p: [ProductSummary]) -> InventoryEmptyState? {
            InventoryList.emptyState(f, in: p, today: today)
        }
        #expect(state(InventoryFilter(), []) == .noStock)
        #expect(state(InventoryFilter(search: "x"), []) == .noStock)
        #expect(state(InventoryFilter(), [gel, old]) == nil)
        #expect(state(InventoryFilter(mode: .archive), [old]) == nil)
        #expect(state(InventoryFilter(), [old]) == .allArchived)
        #expect(state(InventoryFilter(search: "  "), [old]) == .allArchived)
        #expect(state(InventoryFilter(mode: .expired), [gel]) == .filtered)
        #expect(state(InventoryFilter(category: .bar), [gel]) == .filtered)
        #expect(state(InventoryFilter(mode: .archive), [gel]) == .filtered)
        #expect(state(InventoryFilter(category: .bar), [old]) == .filtered)
        #expect(state(InventoryFilter(search: "xyz"), [gel]) == .noSearchResults)
        #expect(state(InventoryFilter(search: "xyz", mode: .expired), [gel]) == .noSearchResults)
    }

    @Test func rowNameShowsAdditives() {
        var r = row("Gel", flavor: "Zitrone")
        r.hasCaffeine = true
        #expect(r.displayName == "Gel · Zitrone · mit Koffein")
    }

    @Test func rowStacksControlsOnlyAtAccessibilitySizes() {
        // Bei größter Schrift bliebe neben dem Namen kein Platz: Knöpfe unter den Text, Name bricht an Wortgrenzen um.
        let normal: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
        for size in normal { #expect(!ProductRowView.stacksControls(at: size)) }
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            #expect(ProductRowView.stacksControls(at: size))
        }
    }
}
