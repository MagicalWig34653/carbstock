import Foundation
import Testing
@testable import CarbStockCore

/// Abhaken, Haken entfernen und wieder setzen (AC-L2, AC-L3, AC-L6). Der Haken ist nie gespeichert, nur abgeleitet.
@Suite struct PackToggleTests {
    let item = UUID(), batch = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func pack(_ key: String, at s: Double = 0, id: UUID = UUID()) -> Movement {
        Movement(id: id, batchID: batch, type: .pack, delta: -3, occurredAt: t0, createdAt: t0.addingTimeInterval(s),
                 idempotencyKey: key, referenceID: item)
    }
    func reversal(of m: Movement, at s: Double) -> Movement {
        Movement(batchID: batch, type: .reversal, delta: -m.delta, occurredAt: t0, createdAt: t0.addingTimeInterval(s),
                 reversesMovementID: m.id, referenceID: item)
    }

    @Test func firstPackUsesLegacyKeyThenGenerations() {
        #expect(IdempotencyKey.pack(itemID: item, generation: 0) == IdempotencyKey.pack(itemID: item))
        #expect(IdempotencyKey.pack(itemID: item, generation: 2) == "pack:\(item.uuidString):2")
    }

    @Test func toggleSequenceKeepsStockConsistent() {
        let empty = Ledger([])
        #expect(empty.nextPackAction(itemID: item, wantPacked: true) == .pack(key: IdempotencyKey.pack(itemID: item, generation: 0)))
        #expect(empty.nextPackAction(itemID: item, wantPacked: false) == .none) // nichts zu entfernen

        let p0 = pack(IdempotencyKey.pack(itemID: item, generation: 0))
        let l1 = Ledger([p0])
        #expect(l1.isPacked(itemID: item))
        #expect(l1.nextPackAction(itemID: item, wantPacked: true) == .none) // schon gepackt: kein Doppelbuchen
        #expect(l1.nextPackAction(itemID: item, wantPacked: false) == .reverse(movementID: p0.id))

        let r0 = reversal(of: p0, at: 1)
        let l2 = Ledger([p0, r0])
        #expect(!l2.isPacked(itemID: item) && l2.quantity(ofBatch: batch) == 0)
        // Wieder packen braucht einen neuen Schlüssel, sonst würde der Ledger die Buchung als Duplikat ignorieren
        #expect(l2.nextPackAction(itemID: item, wantPacked: true) == .pack(key: IdempotencyKey.pack(itemID: item, generation: 1)))

        let p1 = pack(IdempotencyKey.pack(itemID: item, generation: 1), at: 2)
        let l3 = Ledger([p0, r0, p1])
        #expect(l3.isPacked(itemID: item) && l3.quantity(ofBatch: batch) == -3)
        #expect(l3.nextPackAction(itemID: item, wantPacked: false) == .reverse(movementID: p1.id))
        let l4 = Ledger([p0, r0, p1, reversal(of: p1, at: 3)])
        #expect(!l4.isPacked(itemID: item) && l4.quantity(ofBatch: batch) == 0)
        #expect(l4.nextPackAction(itemID: item, wantPacked: true) == .pack(key: IdempotencyKey.pack(itemID: item, generation: 2)))
    }

    /// AC-L3: zwei Geräte haken denselben Posten ab → gleicher Schlüssel → eine Buchung zählt.
    @Test func twoDevicesPackingTheSameItemBookOnce() {
        let key = Ledger([]).nextPackAction(itemID: item, wantPacked: true)
        guard case .pack(let k) = key else { Issue.record("expected pack"); return }
        let a = pack(k, at: 0), b = pack(k, at: 1)
        let l = Ledger([a, b])
        #expect(l.quantity(ofBatch: batch) == -3 && l.ignoredMovementIDs == [b.id])
    }

    /// AC-L6: zurückgelegte Menge je Posten; Netto-Verbrauch = gepackt − zurückgelegt.
    @Test func returnedQuantityIsNetAgainstPacked() {
        let p = pack(IdempotencyKey.pack(itemID: item))
        let ret = Movement(batchID: batch, type: .return, delta: 1, occurredAt: t0, createdAt: t0.addingTimeInterval(5), referenceID: item)
        let other = Movement(batchID: batch, type: .return, delta: 9, occurredAt: t0, createdAt: t0, referenceID: UUID())
        let l = Ledger([p, ret, other])
        #expect(l.returnedQuantity(itemID: item) == 1)
        #expect(l.packedQuantity(itemID: item) == 3)
        #expect(l.netConsumedQuantity(itemID: item) == 2)
    }
}
