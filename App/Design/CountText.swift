import Foundation

/// Texte mit Zahl und Hauptwort an einer Stelle. Einzahl und Mehrzahl kommen aus den Pluralregeln im
/// String Catalog (`Resources/Localizable.xcstrings`), nicht aus Handverkettung: „1 Session“, „0/2 Sessions“.
enum CountText {
    static func sessions(_ n: Int) -> String { String(localized: "\(n) Sessions") }
    static func products(_ n: Int) -> String { String(localized: "\(n) Produkte") }
    static func batches(_ n: Int) -> String { String(localized: "\(n) Chargen") }
    static func movements(_ n: Int) -> String { String(localized: "\(n) Buchungen") }
    static func days(_ n: Int) -> String { String(localized: "\(n) Tage") }
    static func weeks(_ n: Int) -> String { String(localized: "\(n) Wochen") }
    static func differencesToBook(_ n: Int) -> String { String(localized: "\(n) Differenzen buchen") }
    static func correctionsToBook(_ n: Int) -> String { String(localized: "\(n) Korrekturen buchen?") }
    static func missingUnits(_ n: Int) -> String { String(localized: "Von dieser Charge fehlen \(n) Einheiten.") }
    static func expiringSoon(_ n: Int, days: Int) -> String { String(localized: "\(n) laufen in \(days) Tagen ab") }

    /// Hinweis nach dem Import einer Sicherung.
    static func importSummary(_ r: BackupService.ImportResult) -> String {
        if r.total == 0 { return "Nichts Neues: alles aus der Sicherung ist schon vorhanden." }
        return """
        Importiert: \(products(r.products)), \(batches(r.batches)), \(movements(r.movements)), \(sessions(r.sessions)).
        Einkaufsliste: \(r.shoppingItems), Verlauf: \(r.purchaseEvaluations), Packlisten: \(r.packLists).
        """
    }
}
