import Foundation
import Testing
@testable import CarbStockCore

/// Sicherung als JSON (AC-S7) und Erkennung doppelter Produkte (AC-S4).
@Suite struct BackupTests {
    let day = CalendarDay(year: 2026, month: 11, day: 23)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func sample() -> BackupDocument {
        let p = ProductInfo(name: "Gel", brand: "Maurten", category: .gel, baseUnit: .piece, carbsPerPortionG: 25, glucoseFructoseRatio: 0.8)
        let b = BatchInfo(productID: p.id, purchaseDate: day, quantityPurchased: 12, totalPriceCents: 4200,
                          expiryDate: day.adding(days: 200), useDespiteExpiry: true)
        let m = Movement(batchID: b.id, type: .purchase, delta: 12, occurredAt: t0, createdAt: t0, idempotencyKey: "purchase:x", referenceID: nil)
        let s = PlannedSession(day: day, type: .long, durationMinutes: 240, carbsPerHourOverride: 90, status: .done)
        let w = WeeklyTemplateEntry(weekdayIndex: 6, type: .long, durationMinutes: 240, validFrom: day, validUntil: day.adding(days: 90))
        return BackupDocument(exportedAt: t0, products: [p], batches: [b], movements: [m], sessions: [s], template: [w],
                              carbRates: [.long: 85])
    }

    @Test func roundTripIsIdentical() throws {
        let doc = sample()
        let data = try doc.encoded()
        let back = try BackupDocument.decode(data)
        #expect(back == doc)
        // Stabile Ausgabe: gleiche Eingabe, gleiche Bytes (nachvollziehbar und diff-bar)
        #expect(try doc.encoded() == data)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\""))
    }

    @Test func validationFindsBrokenReferences() throws {
        var doc = sample()
        #expect(doc.problems.isEmpty)
        doc.batches[0].productID = UUID()
        #expect(doc.problems.contains(.batchWithoutProduct(doc.batches[0].id)))
        doc = sample()
        doc.movements.append(Movement(batchID: UUID(), type: .adjust, delta: 1, occurredAt: t0))
        #expect(doc.problems.contains(.movementWithoutBatch(doc.movements[1].id)))
    }

    @Test func newerVersionIsRejected() throws {
        var doc = sample()
        doc.version = BackupDocument.currentVersion + 1
        let data = try doc.encoded()
        #expect(throws: BackupDocument.DecodeFailure.newerVersion(BackupDocument.currentVersion + 1)) { try BackupDocument.decode(data) }
        #expect(throws: BackupDocument.DecodeFailure.notABackup) { try BackupDocument.decode(Data("{}".utf8)) }
    }

    /// Import ist idempotent: bekannte IDs werden nicht noch einmal angelegt.
    @Test func importPlanSkipsKnownIDs() {
        let doc = sample()
        let all = doc.importPlan(knownProducts: [], knownBatches: [], knownMovements: [], knownSessions: [], knownTemplate: [])
        #expect(all.products.count == 1 && all.batches.count == 1 && all.movements.count == 1 && all.sessions.count == 1 && all.template.count == 1)
        let again = doc.importPlan(knownProducts: Set(doc.products.map(\.id)), knownBatches: Set(doc.batches.map(\.id)),
                                   knownMovements: Set(doc.movements.map(\.id)), knownSessions: Set(doc.sessions.map(\.id)),
                                   knownTemplate: Set(doc.template.map(\.id)))
        #expect(again.isEmpty)
    }

    // AC-S4
    @Test func duplicateProductsIgnoreCaseSpacesAndAccents() {
        func p(_ name: String, _ brand: String?, archived: Bool = false) -> ProductInfo {
            ProductInfo(name: name, brand: brand, category: .gel, baseUnit: .piece, carbsPerPortionG: 25, isArchived: archived)
        }
        let a = p("Energy Gel", "Maurten"), b = p("  energy  gel ", "MAURTEN"), c = p("Énergie", nil), d = p("energie", "")
        let other = p("Riegel", "Maurten"), gone = p("Energy Gel", "Maurten", archived: true)
        let groups = DuplicateProducts.groups(in: [a, b, c, d, other, gone])
        #expect(groups.count == 2)
        #expect(Set(groups.map { Set($0.map(\.id)) }) == [[a.id, b.id], [c.id, d.id]])
        #expect(DuplicateProducts.groups(in: [a, other]).isEmpty)
    }

    @Test func mergeRequiresSameUnitAndCarbs() {
        let a = ProductInfo(name: "Pulver", category: .drink, baseUnit: .gram, portionAmount: 50, carbsPerPortionG: 40)
        let same = ProductInfo(name: "pulver", category: .drink, baseUnit: .gram, portionAmount: 100, carbsPerPortionG: 80) // 0,8 g/g gleich
        let otherCarbs = ProductInfo(name: "pulver", category: .drink, baseUnit: .gram, portionAmount: 50, carbsPerPortionG: 30)
        let otherUnit = ProductInfo(name: "pulver", category: .drink, baseUnit: .piece, carbsPerPortionG: 0.8)
        #expect(DuplicateProducts.canMerge(a, into: same))
        #expect(!DuplicateProducts.canMerge(a, into: otherCarbs))
        #expect(!DuplicateProducts.canMerge(a, into: otherUnit))
        #expect(!DuplicateProducts.canMerge(a, into: a))
    }
}
