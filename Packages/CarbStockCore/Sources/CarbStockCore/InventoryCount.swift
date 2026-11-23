import Foundation

/// Eine Korrekturbuchung aus dem Zähl-Durchgang (Typ `adjust`, Notiz „Inventur“).
public struct CountAdjustment: Hashable, Sendable {
    public let batchID: UUID
    public let delta: Int
    public init(batchID: UUID, delta: Int) {
        self.batchID = batchID
        self.delta = delta
    }
}

/// Zähl-Durchgang (Spec 4.6): Der Nutzer zählt ein Produkt, die App bucht nur die Differenz zum Soll.
public enum InventoryCount {
    /// Verteilt die Differenz zwischen `counted` und dem Soll (Summe der nicht archivierten Chargen) auf Chargen.
    ///
    /// - Mehr gezählt als erwartet: Zugang auf die erste nutzbare Charge in FEFO-Reihenfolge, sonst auf die erste Charge.
    /// - Weniger gezählt: Abzug in FEFO-Reihenfolge über Chargen mit Bestand. Abgelaufene Chargen kommen zuletzt,
    ///   weil sie die Prognose ohnehin nicht tragen. Welche Charge fehlt, ist unbekannt; das ist die vorsichtige Annahme.
    /// - Chargen mit negativem Bestand zählen in die Summe, werden aber nie weiter verringert.
    /// - Gleicher Stand, negative Zählung oder keine Charge: keine Buchung.
    public static func plan(counted: Int, batches: [BatchInfo], ledger: Ledger, today: CalendarDay) -> [CountAdjustment] {
        guard counted >= 0 else { return [] }
        let active = batches.filter { !$0.isArchived }.sorted(by: BatchInfo.fefoPrecedes)
        guard !active.isEmpty else { return [] }
        let expected = active.reduce(0) { $0 + ledger.quantity(ofBatch: $1.id) }
        let diff = counted - expected
        guard diff != 0 else { return [] }

        func usable(_ b: BatchInfo) -> Bool { b.useDespiteExpiry || !b.isExpired(on: today) }

        if diff > 0 {
            guard let target = active.first(where: usable) ?? active.first else { return [] }
            return [CountAdjustment(batchID: target.id, delta: diff)]
        }
        var open = -diff
        var result: [CountAdjustment] = []
        for b in active.filter(usable) + active.filter({ !usable($0) }) where open > 0 {
            let available = ledger.quantity(ofBatch: b.id)
            guard available > 0 else { continue }
            let take = min(available, open)
            result.append(CountAdjustment(batchID: b.id, delta: -take))
            open -= take
        }
        return result
    }
}
