import XCTest

/// M6: Packliste anlegen, abhaken (bucht ab), Haken weg (Gegenbuchung), Rest zurücklegen. E2E über die echte Oberfläche,
/// der Bestand wird im Tab „Bestand“ gegengelesen. Bilder hell und dunkel als Belege.
final class PackListUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func shot(_ app: XCUIApplication, _ name: String, dark: Bool) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "\(name)-\(dark ? "dunkel" : "hell")"
        a.lifetime = .keepAlways
        add(a)
    }

    /// Alle Bestandszeilen („25 Stk. · 300 g Carbs“) des Bestand-Tabs, sortiert.
    private func stock(_ app: XCUIApplication) -> [String] {
        app.tabBars.buttons["Bestand"].tap()
        XCTAssertTrue(app.staticTexts["Energy Gel 100"].waitForExistence(timeout: 5), "Bestand zeigt die Beispielprodukte nicht")
        return app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' Carbs'")).allElementsBoundByIndex.map { $0.label }.sorted()
    }

    private func check(dark: Bool) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory", "-CarbStockSampleData"]
        app.launch()

        let before = stock(app)
        XCTAssertFalse(before.isEmpty)

        // Packliste aus der geplanten Session anlegen.
        app.tabBars.buttons["Training"].tap()
        app.buttons["Packlisten"].tap()
        XCTAssertTrue(app.staticTexts["Keine Packlisten"].waitForExistence(timeout: 5), "Packlisten: Leerzustand fehlt")
        app.buttons["Packliste anlegen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neue Packliste"].waitForExistence(timeout: 5), "Formular öffnet nicht")
        shot(app, "20-packliste-0-planer", dark: dark)
        app.buttons["Anlegen"].tap()
        XCTAssertTrue(app.staticTexts["Keine Packlisten"].waitForNonExistence(timeout: 5), "Packlisten: Leerzustand bleibt nach dem Anlegen")
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Entwurf'")).firstMatch.tap()

        // Vorher: nichts gepackt.
        let tick = app.buttons["Als gepackt abhaken"].firstMatch
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "Packliste: kein Posten zum Abhaken")
        XCTAssertFalse(app.buttons["Gepackt, Haken entfernen"].exists)
        shot(app, "20-packliste-1-vorher", dark: dark)

        // Während: abgehakt, der Bestand sinkt.
        tick.tap()
        XCTAssertTrue(app.buttons["Gepackt, Haken entfernen"].waitForExistence(timeout: 5), "Haken wird nicht gesetzt")
        shot(app, "20-packliste-2-gepackt", dark: dark)
        let packed = stock(app)
        XCTAssertNotEqual(packed, before, "Abhaken bucht nichts aus dem Bestand ab")

        // Nachher: Haken weg, der Bestand ist wieder wie vorher.
        app.tabBars.buttons["Training"].tap()
        let untick = app.buttons["Gepackt, Haken entfernen"].firstMatch
        XCTAssertTrue(untick.waitForExistence(timeout: 5), "Packliste: Ansicht nach dem Tabwechsel verloren")
        untick.tap()
        XCTAssertTrue(app.buttons["Als gepackt abhaken"].firstMatch.waitForExistence(timeout: 5), "Haken wird nicht entfernt")
        shot(app, "20-packliste-3-zurueckgebucht", dark: dark)
        XCTAssertEqual(stock(app), before, "Haken weg bucht nicht genau zurück")

        // Rest zurücklegen: abhaken, nach links wischen, zurücklegen.
        app.tabBars.buttons["Training"].tap()
        app.buttons["Als gepackt abhaken"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Gepackt, Haken entfernen"].firstMatch.waitForExistence(timeout: 5))
        // Wischen auf der Zeile (nicht auf dem Haken-Knopf), sonst bleiben die Wischaktionen zu.
        app.cells.containing(.button, identifier: "Gepackt, Haken entfernen").firstMatch.swipeLeft()
        app.buttons["Zurücklegen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Rest zurücklegen"].waitForExistence(timeout: 5), "Rest-Zurücklegen öffnet nicht")
        shot(app, "20-packliste-4-rest-blatt", dark: dark)
        app.navigationBars["Rest zurücklegen"].buttons["Zurücklegen"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'zurückgelegt'")).firstMatch.waitForExistence(timeout: 5),
                      "Packliste zeigt den zurückgelegten Rest nicht")
        shot(app, "20-packliste-5-rest-zurueck", dark: dark)
        XCTAssertNotEqual(stock(app), packed, "Rest zurücklegen ändert den Bestand nicht")
    }

    func testPackAndReturnLight() { check(dark: false) }
    func testPackAndReturnDark() { check(dark: true) }
}
