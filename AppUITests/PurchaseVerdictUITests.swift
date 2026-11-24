import XCTest

/// M5: Nach der Zahleneingabe erscheint das Kaufurteil mit Begründung. E2E über die echte Oberfläche, Bilder hell und dunkel.
final class PurchaseVerdictUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func enter(_ app: XCUIApplication, in field: XCUIElement, _ text: String) {
        var swipes = 0
        while !field.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        field.tap()
        field.typeText(text)
        try? XCTSkipUnless(app.keyboards.element.waitForExistence(timeout: 5), "Hardware-Tastatur verbunden, keine Bildschirmtastatur")
    }

    private func checkVerdict(dark: Bool) throws {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let look = dark ? "dunkel" : "hell"
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory", "-CarbStockSampleData"]
        app.launch()

        app.tabBars.buttons["Einkauf"].tap()
        // Produkt aus dem Bestand wählen.
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Produkt'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Produktauswahl fehlt")
        picker.tap()
        let gel = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Energy Gel'")).firstMatch
        XCTAssertTrue(gel.waitForExistence(timeout: 5), "Produkt aus dem Bestand fehlt in der Auswahl")
        gel.tap()

        // Noch kein Urteil ohne Menge.
        XCTAssertFalse(app.staticTexts["Urteil"].exists, "Urteil erscheint ohne Eingabe")

        // Zahlen eingeben: Menge, dann Gesamtpreis.
        let quantity = app.textFields["Pflicht"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5), "Mengenfeld fehlt")
        enter(app, in: quantity, "20")
        let price = app.textFields.matching(NSPredicate(format: "placeholderValue == 'optional'")).element(boundBy: 0)
        enter(app, in: price, "30")
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 5) { done.tap() }

        // Das Urteil steht da, mit Begründung und Preis je 100 g Carbs.
        let verdict = app.staticTexts["Urteil"]
        var swipes = 0
        while !verdict.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(verdict.exists, "Nach der Zahleneingabe erscheint kein Urteil")
        XCTAssertTrue(app.staticTexts["Begründung"].exists, "Begründung fehlt")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'je 100 g Carbs'")).firstMatch.exists, "Preis je 100 g Carbs fehlt")
        XCTAssertFalse(app.staticTexts["Noch nötig"].exists, "Eingabe gilt als unvollständig")
        shot(app, "10-kaufurteil-\(look)")
    }

    func testVerdictAppearsAfterNumbersLight() throws { try checkVerdict(dark: false) }
    func testVerdictAppearsAfterNumbersDark() throws { try checkVerdict(dark: true) }
}
