import XCTest

/// DEBUG-Werkzeug „CloudKit-Schema anlegen“: erscheint nur mit Startargument, führt ohne Knopfdruck nichts aus
/// und lehnt im unsignierten Build (ohne iCloud-Berechtigung) verständlich ab. Bilder hell und dunkel.
final class CloudKitSchemaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func launch(dark: Bool, extra: [String]) -> XCUIApplication {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testWithoutTheArgumentTheAppStartsNormally() {
        let app = launch(dark: false, extra: [])
        XCTAssertTrue(app.staticTexts["Noch kein Vorrat"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Schema anlegen"].exists)
        XCTAssertFalse(app.navigationBars["CloudKit-Schema"].exists)
    }

    private func checkTool(dark: Bool) {
        let look = dark ? "dunkel" : "hell"
        let app = launch(dark: dark, extra: ["-CarbStockCloudKitSchema"])
        XCTAssertTrue(app.navigationBars["CloudKit-Schema"].waitForExistence(timeout: 10), "Werkzeug erscheint nicht")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Im Werkzeug-Modus läuft die normale App nicht")
        // Nie automatisch: vor dem Knopfdruck gibt es kein Ergebnis.
        XCTAssertTrue(app.staticTexts["Noch nichts ausgeführt"].exists)
        shot(app, "schema-1-start-\(look)")
        app.buttons["Schema anlegen"].tap()
        XCTAssertTrue(app.staticTexts["Nicht ausgeführt"].waitForExistence(timeout: 10), "Ablehnung fehlt")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iCloud-Berechtigung")).firstMatch.exists)
        shot(app, "schema-2-abgelehnt-\(look)")
    }

    func testToolRunsOnlyOnTapAndRefusesAnUnsignedBuild() { checkTool(dark: false) }
    func testToolRunsOnlyOnTapAndRefusesAnUnsignedBuildDark() { checkTool(dark: true) }
}
