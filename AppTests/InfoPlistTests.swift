import Foundation
import Testing

/// Upload-Prüfung: Mit der HealthKit-Berechtigung verlangt App Store Connect beide Nutzungstexte,
/// auch wenn die App nur liest (Upload von 0.1.0 (3) scheiterte am 24.11. am fehlenden Schreib-Text).
@Suite struct InfoPlistTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test func runsInsideTheApp() {
        #expect(Bundle.main.bundleIdentifier == "de.linolaske.carbstock")
    }

    @Test func healthPurposeStringsArePresent() {
        let share = info["NSHealthShareUsageDescription"] as? String ?? ""
        let update = info["NSHealthUpdateUsageDescription"] as? String ?? ""
        #expect(!share.isEmpty)
        #expect(!update.isEmpty)
        // Nur lesen (CLAUDE.md): der Schreib-Text sagt, dass nichts geschrieben wird.
        #expect(update.contains("schreibt keine"))
    }
}
