import XCTest

/// M4b: Der Leerzustand verschwindet nach dem ersten Eintrag (Bestand, Bedarf, Training) und kommt zurück,
/// wo das vorgesehen ist (Session löschen: Training und Bedarf). E2E über die echte Oberfläche.
/// Je Tab ein Test, hell und dunkel; Bilder vorher / während / nachher hängen als Belege am Lauf.
final class EmptyStateGoesAwayUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func launch(dark: Bool) -> XCUIApplication {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication()
        // Ohne -CarbStockSampleData: leerer Speicher.
        app.launchArguments = ["-CarbStockInMemory"]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String, dark: Bool) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "\(name)-\(dark ? "dunkel" : "hell")"
        a.lifetime = .keepAlways
        add(a)
    }

    private func gone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func type(_ text: String, into field: XCUIElement, app: XCUIApplication) throws {
        var swipes = 0
        while !field.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        field.tap()
        field.typeText(text)
        try XCTSkipUnless(app.keyboards.element.waitForExistence(timeout: 5), "Hardware-Tastatur verbunden, keine Bildschirmtastatur")
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    /// Legt die erste Session über die Oberfläche an (Standardwerte: heute, 60 Minuten).
    private func addFirstSession(_ app: XCUIApplication) {
        app.buttons["Session anlegen"].tap()
        XCTAssertTrue(app.navigationBars["Neue Session"].waitForExistence(timeout: 5), "Sessionformular öffnet nicht")
        app.buttons["Sichern"].tap()
    }

    // MARK: Bestand

    private func checkInventory(dark: Bool) throws {
        let app = launch(dark: dark)
        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 10), "Bestand: Leerzustand fehlt am Anfang")
        shot(app, "01-bestand-1-vorher", dark: dark)

        app.buttons["Produkt anlegen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Produkt anlegen"].waitForExistence(timeout: 5), "Produktformular öffnet nicht")
        try type("UI-Testgel", into: app.textFields["Name (Pflicht)"], app: app)
        try type("25", into: app.textFields["z. B. 25"], app: app)
        shot(app, "01-bestand-2-waehrend", dark: dark)
        app.buttons["Sichern"].tap()

        XCTAssertTrue(gone(app.staticTexts["Noch kein Vorrat"]), "Bestand: Leerzustand bleibt nach dem ersten Produkt")
        XCTAssertTrue(app.staticTexts["UI-Testgel"].waitForExistence(timeout: 5), "Bestand: das neue Produkt fehlt in der Liste")
        shot(app, "01-bestand-3-nachher", dark: dark)

        // „Archivieren“ eines Produkts ohne Buchungen löscht es. Dann ist wieder nichts da: der Leerzustand kommt zurück.
        // (Mit Buchungen bliebe es archiviert im Filter „Archiv“; das ist kein Leerzustand und hier nicht Thema.)
        app.staticTexts["UI-Testgel"].tap()
        let archive = app.buttons["Archivieren"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "Detail: Archivieren fehlt")
        archive.tap()
        // Der Bestätigungsdialog erscheint als Popover über dem Formular; sein Knopf heißt wie der darunter.
        let confirm = app.popovers.buttons["Archivieren"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Bestätigungsdialog erscheint nicht")
        shot(app, "01-bestand-4-bestaetigen", dark: dark)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 5), "Bestand: Leerzustand kommt nach dem Entfernen nicht zurück")
        shot(app, "01-bestand-5-entfernt", dark: dark)
    }

    // MARK: Bestand leer trotz Produkten (alles archiviert, Filter ohne Treffer)

    private func checkHiddenInventory(dark: Bool) throws {
        let app = launch(dark: dark)
        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 10))
        app.buttons["Produkt anlegen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Produkt anlegen"].waitForExistence(timeout: 5))
        try type("UI-Testgel", into: app.textFields["Name (Pflicht)"], app: app)
        try type("25", into: app.textFields["z. B. 25"], app: app)
        // Mit Menge entsteht eine Buchung: „Archivieren“ legt das Produkt dann ins Archiv, statt es zu löschen.
        try type("3", into: app.textFields["optional"].firstMatch, app: app)
        app.buttons["Sichern"].tap()
        XCTAssertTrue(app.staticTexts["UI-Testgel"].waitForExistence(timeout: 5))
        app.staticTexts["UI-Testgel"].tap()
        let archive = app.buttons["Archivieren"].firstMatch
        var swipes = 0
        while !(archive.exists && archive.isHittable) && swipes < 6 { app.swipeUp(); swipes += 1 }
        archive.tap()
        let confirm = app.popovers.buttons["Archivieren"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Bestätigungsdialog erscheint nicht")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Alle Produkte archiviert"].waitForExistence(timeout: 5), "Bestand: Grund „archiviert“ fehlt")
        XCTAssertFalse(app.staticTexts["Noch kein Vorrat"].exists)
        shot(app, "01-bestand-6-alles-archiviert", dark: dark)
        app.buttons["Archiv anzeigen"].tap()
        XCTAssertTrue(app.staticTexts["UI-Testgel"].waitForExistence(timeout: 5), "„Archiv anzeigen“ zeigt das Produkt nicht")

        app.buttons["Filter"].tap()
        app.buttons["Abgelaufen"].tap()
        XCTAssertTrue(app.staticTexts["Keine passenden Produkte"].waitForExistence(timeout: 5), "Bestand: Grund „Filter“ fehlt")
        shot(app, "01-bestand-7-filter-ohne-treffer", dark: dark)
        app.buttons["Filter zurücksetzen"].tap()
        XCTAssertTrue(app.staticTexts["Alle Produkte archiviert"].waitForExistence(timeout: 5), "Zurücksetzen führt nicht zurück")
    }

    func testHiddenInventoryNamesTheReason() throws { try checkHiddenInventory(dark: false) }
    func testHiddenInventoryNamesTheReasonDark() throws { try checkHiddenInventory(dark: true) }

    func testInventoryEmptyStateGoesAway() throws { try checkInventory(dark: false) }
    func testInventoryEmptyStateGoesAwayDark() throws { try checkInventory(dark: true) }

    // MARK: Training

    private func checkTraining(dark: Bool) {
        let app = launch(dark: dark)
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 10), "Training: Leerzustand fehlt am Anfang")
        shot(app, "05-training-1-vorher", dark: dark)

        app.buttons["Session anlegen"].tap()
        XCTAssertTrue(app.navigationBars["Neue Session"].waitForExistence(timeout: 5), "Sessionformular öffnet nicht")
        shot(app, "05-training-2-waehrend", dark: dark)
        app.buttons["Sichern"].tap()

        XCTAssertTrue(gone(app.staticTexts["Noch keine Sessions"]), "Training: Leerzustand bleibt nach der ersten Session")
        XCTAssertTrue(app.staticTexts["Heute und kommend"].waitForExistence(timeout: 5), "Training: die neue Session fehlt in der Liste")
        shot(app, "05-training-3-nachher", dark: dark)

        // Löschen: der Leerzustand kommt zurück.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Z2'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Training: Sessionzeile fehlt")
        row.swipeLeft()
        app.buttons["Löschen"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 5), "Training: Leerzustand kommt nach dem Löschen nicht zurück")
        shot(app, "05-training-4-geloescht", dark: dark)
    }

    func testTrainingEmptyStateGoesAway() { checkTraining(dark: false) }
    func testTrainingEmptyStateGoesAwayDark() { checkTraining(dark: true) }

    // MARK: Bedarf

    private func checkDemand(dark: Bool) {
        let app = launch(dark: dark)
        app.tabBars.buttons["Bedarf"].tap()
        XCTAssertTrue(app.staticTexts["Bedarf unbekannt"].waitForExistence(timeout: 10), "Bedarf: Leerzustand fehlt am Anfang")
        shot(app, "03-bedarf-1-vorher", dark: dark)

        // „Zum Training“ führt in den Tab, dort die erste Session anlegen.
        app.buttons["Zum Training"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 5), "„Zum Training“ führt nicht ins Training")
        addFirstSession(app)
        XCTAssertTrue(app.staticTexts["Heute und kommend"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Bedarf"].tap()
        XCTAssertTrue(gone(app.staticTexts["Bedarf unbekannt"]), "Bedarf: Leerzustand bleibt nach der ersten Session")
        XCTAssertFalse(app.buttons["Zum Training"].exists, "Bedarf: der Leerzustand-Knopf bleibt")
        shot(app, "03-bedarf-3-nachher", dark: dark)

        // Session löschen: ohne Bedarf und ohne Vorrat ist die Reichweite wieder unbekannt.
        app.tabBars.buttons["Training"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Z2'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Training: Sessionzeile fehlt")
        row.swipeLeft()
        app.buttons["Löschen"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Sessions"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Bedarf"].tap()
        XCTAssertTrue(app.staticTexts["Bedarf unbekannt"].waitForExistence(timeout: 5), "Bedarf: Leerzustand kommt nach dem Löschen nicht zurück")
        shot(app, "03-bedarf-4-geloescht", dark: dark)
    }

    func testDemandEmptyStateGoesAway() { checkDemand(dark: false) }
    func testDemandEmptyStateGoesAwayDark() { checkDemand(dark: true) }
}
