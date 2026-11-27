import Testing
@testable import CarbStock

/// Zählertexte: Einzahl bei 1, Mehrzahl bei 0 und ab 2 (deutsche Pluralregel aus dem String Catalog).
@Suite struct CountTextTests {
    private func importText(sessions: Int) -> String {
        var r = BackupService.ImportResult()
        r.sessions = sessions
        r.products = 1 // total > 0, damit auch bei 0 Sessions die Zusammenfassung erscheint
        return CountText.importSummary(r)
    }

    @Test func importSummaryCountsSessions() {
        #expect(importText(sessions: 0).contains("0 Sessions."))
        #expect(importText(sessions: 1).contains("1 Session."))
        #expect(importText(sessions: 2).contains("2 Sessions."))
    }

    @Test func importSummaryCountsEveryNoun() {
        var r = BackupService.ImportResult()
        (r.products, r.batches, r.movements, r.sessions) = (1, 1, 1, 1)
        #expect(CountText.importSummary(r).hasPrefix("Importiert: 1 Produkt, 1 Charge, 1 Buchung, 1 Session."))
        (r.products, r.batches, r.movements, r.sessions) = (2, 3, 0, 5)
        #expect(CountText.importSummary(r).hasPrefix("Importiert: 2 Produkte, 3 Chargen, 0 Buchungen, 5 Sessions."))
    }

    @Test func importSummaryWithoutNews() {
        #expect(CountText.importSummary(.init()) == "Nichts Neues: alles aus der Sicherung ist schon vorhanden.")
    }

    @Test(arguments: [
        (0, "0 Tage", "0 Wochen"), (1, "1 Tag", "1 Woche"), (2, "2 Tage", "2 Wochen"),
    ])
    func daysAndWeeks(n: Int, days: String, weeks: String) {
        #expect(CountText.days(n) == days)
        #expect(CountText.weeks(n) == weeks)
    }

    @Test func inventoryAndPacking() {
        #expect(CountText.differencesToBook(1) == "1 Differenz buchen")
        #expect(CountText.differencesToBook(2) == "2 Differenzen buchen")
        #expect(CountText.correctionsToBook(1) == "1 Korrektur buchen?")
        #expect(CountText.correctionsToBook(3) == "3 Korrekturen buchen?")
        #expect(CountText.missingUnits(1) == "Von dieser Charge fehlt 1 Einheit.")
        #expect(CountText.missingUnits(4) == "Von dieser Charge fehlen 4 Einheiten.")
    }

    @Test func expiringSoon() {
        #expect(CountText.expiringSoon(1, days: 60) == "1 läuft in 60 Tagen ab")
        #expect(CountText.expiringSoon(2, days: 60) == "2 laufen in 60 Tagen ab")
    }
}
