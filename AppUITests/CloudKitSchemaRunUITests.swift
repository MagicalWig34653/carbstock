import XCTest

/// Führt das DEBUG-Werkzeug wirklich aus: legt das **Development**-Schema in CloudKit an. Läuft nie nebenbei,
/// nur mit `TEST_RUNNER_CARBSTOCK_SCHEMA_RUN=1`, in einem signierten Build auf einem Gerät oder Simulator mit iCloud-Konto:
/// `TEST_RUNNER_CARBSTOCK_SCHEMA_RUN=1 xcodebuild test … -only-testing:CarbStockUITests/CloudKitSchemaRunUITests`.
/// Ein Deploy nach Production gibt es hier nicht; das macht nur der Maintainer in der Konsole.
final class CloudKitSchemaRunUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCreatesTheDevelopmentSchema() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CARBSTOCK_SCHEMA_RUN"] == "1",
                          "Nur auf ausdrücklichen Wunsch (TEST_RUNNER_CARBSTOCK_SCHEMA_RUN=1)")
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockCloudKitSchema"]
        app.launch()
        let button = app.buttons["Schema anlegen"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Werkzeug erscheint nicht")
        button.tap()

        let done = app.staticTexts["Schema angelegt"]
        let refused = app.staticTexts["Nicht ausgeführt"]
        let failed = app.staticTexts["Fehlgeschlagen"]
        let deadline = Date.now.addingTimeInterval(300)
        while !done.exists && !refused.exists && !failed.exists && Date.now < deadline {
            _ = done.waitForExistence(timeout: 2)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "schema-lauf"
        shot.lifetime = .keepAlways
        add(shot)
        // Der sichtbare Text nennt bei Ablehnung oder Fehler den Grund.
        let screen = app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
        XCTAssertTrue(done.exists, "Schema nicht angelegt: \(screen)")
        for type in ["CD_Batch", "CD_Product", "CD_PurchaseEvaluation", "CD_ShoppingListItem", "CD_StockMovement"] {
            XCTAssertTrue(app.staticTexts[type].exists, "\(type) fehlt in der Anzeige")
        }
    }
}
