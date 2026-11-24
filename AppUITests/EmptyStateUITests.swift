import XCTest

/// M4b: Frisch installiert, ohne Daten und ohne Vorbelegung: jedes Tab zeigt einen neutralen Leerzustand, keine Zahlen.
final class EmptyStateUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory"]   // ohne -CarbStockSampleData: leerer Speicher
        app.launch()
        return app
    }

    func testEveryTabShowsANeutralEmptyState() {
        let app = launch()

        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 10), "Bestand: Leerzustand fehlt")
        app.tabBars.buttons["Zuerst"].tap()
        XCTAssertTrue(app.staticTexts["Nichts zu verbrauchen"].waitForExistence(timeout: 5), "Zuerst: Leerzustand fehlt")

        app.tabBars.buttons["Bedarf"].tap()
        XCTAssertTrue(app.staticTexts["Bedarf unbekannt"].waitForExistence(timeout: 5), "Bedarf: Leerzustand fehlt")
        XCTAssertTrue(app.buttons["Zum Training"].exists)
        // Keine Tabelle aus Nullen: weder Zeiträume noch Mengen ohne Bedarf und Vorrat.
        XCTAssertFalse(app.staticTexts["Bedarf und nutzbarer Bestand"].exists, "Bedarf zeigt Prognose-Zeilen ohne Daten")
        XCTAssertFalse(app.staticTexts["1 Woche"].exists, "Bedarf zeigt Zeitraum-Zeilen ohne Daten")
        XCTAssertFalse(app.staticTexts["Nutzbarer Bestand"].exists, "Bedarf zeigt Mengen ohne Daten")

        app.tabBars.buttons["Einkauf"].tap()
        XCTAssertTrue(app.staticTexts["Kauf-Entscheider"].exists || app.buttons["Kauf-Entscheider"].exists || app.segmentedControls.firstMatch.exists, "Einkauf: Auswahl fehlt")

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 5), "Training: Leerzustand fehlt")
    }
}
