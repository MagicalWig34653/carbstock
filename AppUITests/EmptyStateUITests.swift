import XCTest

/// M4b: Frisch installiert, ohne Daten und ohne Vorbelegung: jedes Tab zeigt einen neutralen Leerzustand, keine Zahlen.
/// Die Läufe hell, dunkel und mit größter Schrift hängen je Tab ein Bild an (Abnahmebelege).
final class EmptyStateUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private enum Look {
        case light, dark, largeText
        var name: String { switch self { case .light: "hell"; case .dark: "dunkel"; case .largeText: "groesste-schrift" } }
        var arguments: [String] {
            switch self {
            case .light, .dark: []
            case .largeText: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
        }
    }

    /// Das Erscheinungsbild des Simulators folgt dem Lauf; danach wieder dunkel, wie der Simulator vorher stand.
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func launch(_ look: Look, extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.appearance = look == .dark ? .dark : .light
        let app = XCUIApplication()
        // Ohne -CarbStockSampleData: leerer Speicher.
        app.launchArguments = ["-CarbStockInMemory"] + look.arguments + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ look: Look, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "\(name)-\(look.name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func checkEveryTab(_ look: Look) {
        let app = launch(look)

        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 10), "Bestand: Leerzustand fehlt")
        shot(app, look, "01-bestand")
        app.tabBars.buttons["Zuerst"].tap()
        XCTAssertTrue(app.staticTexts["Nichts zu verbrauchen"].waitForExistence(timeout: 5), "Zuerst: Leerzustand fehlt")
        shot(app, look, "02-zuerst")

        app.tabBars.buttons["Bedarf"].tap()
        XCTAssertTrue(app.staticTexts["Bedarf unbekannt"].waitForExistence(timeout: 5), "Bedarf: Leerzustand fehlt")
        XCTAssertTrue(app.buttons["Zum Training"].exists)
        // Keine Tabelle aus Nullen: weder Zeiträume noch Mengen ohne Bedarf und Vorrat.
        XCTAssertFalse(app.staticTexts["Bedarf und nutzbarer Bestand"].exists, "Bedarf zeigt Prognose-Zeilen ohne Daten")
        XCTAssertFalse(app.staticTexts["1 Woche"].exists, "Bedarf zeigt Zeitraum-Zeilen ohne Daten")
        XCTAssertFalse(app.staticTexts["Nutzbarer Bestand"].exists, "Bedarf zeigt Mengen ohne Daten")
        shot(app, look, "03-bedarf")
        if look == .largeText {
            // Bei größter Schrift füllt der Leerzustand mehr als den Bildschirm: der Knopf muss erreichbar bleiben.
            let go = app.buttons["Zum Training"]
            var swipes = 0
            while !go.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
            XCTAssertTrue(go.isHittable, "Bedarf: „Zum Training“ ist bei größter Schrift nicht erreichbar")
            shot(app, look, "03b-bedarf-knopf")
        }

        app.tabBars.buttons["Einkauf"].tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5), "Einkauf: Auswahl fehlt")
        shot(app, look, "04-einkauf")

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 5), "Training: Leerzustand fehlt")
        shot(app, look, "05-training")
    }

    func testEveryTabShowsANeutralEmptyState() { checkEveryTab(.light) }
    func testEveryTabShowsANeutralEmptyStateDark() { checkEveryTab(.dark) }
    func testEveryTabShowsANeutralEmptyStateLargestText() { checkEveryTab(.largeText) }

    /// Die Ersteinrichtung nennt nur Vorschläge der App, keine persönlichen Werte, und lässt sich überspringen.
    private func checkSetupSheet(_ look: Look) {
        let app = launch(look, extra: ["-CarbStockShowSetup", "-rateSetupDone", "NO"])
        XCTAssertTrue(app.navigationBars["Willkommen"].waitForExistence(timeout: 10), "Ersteinrichtung erscheint nicht")
        XCTAssertTrue(app.buttons["Überspringen"].exists)
        shot(app, look, "06-ersteinrichtung")
        app.buttons["Überspringen"].tap()
        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 5), "Nach „Überspringen“ fehlt der Leerzustand")
    }

    func testSetupSheetLight() { checkSetupSheet(.light) }
    func testSetupSheetDark() { checkSetupSheet(.dark) }
    func testSetupSheetLargestText() { checkSetupSheet(.largeText) }
}
