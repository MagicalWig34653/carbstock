import XCTest

/// Zahlenfelder haben keine Eingabetaste: „Fertig“ über der Tastatur muss sie schließen und den Knopf darunter freigeben.
final class KeyboardDoneUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDoneClosesNumberPadAndFreesTheBookButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory", "-CarbStockSampleData"]
        app.launch()

        app.buttons["Inventur"].tap()
        let field = app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Gezählt'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1")
        try XCTSkipUnless(app.keyboards.element.waitForExistence(timeout: 5), "Hardware-Tastatur verbunden, keine Bildschirmtastatur")

        let done = app.buttons["keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "„Fertig“ über der Zifferntastatur fehlt")
        done.tap()

        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 5), "Die Tastatur bleibt nach „Fertig“ offen")
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Differenz'")).firstMatch
        // Ohne Tastatur lässt sich die Liste bis zum Knopf scrollen (vorher verdeckte die Tastatur ihn).
        var swipes = 0
        while !(book.exists && book.isHittable) && swipes < 5 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(book.exists && book.isHittable, "Der Buchen-Knopf ist nach „Fertig“ nicht erreichbar")
        book.tap()
        XCTAssertTrue(app.buttons["Buchen"].waitForExistence(timeout: 5), "Die Bestätigung erscheint nicht")
    }
}
