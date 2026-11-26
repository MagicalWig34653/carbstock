import XCTest

/// AC-S7 über die echte Oberfläche: erfundene Daten anlegen, Sicherung über den Dateien-Dialog speichern, App leer neu
/// starten, Sicherung wählen und alles wiederfinden; ein zweiter Import legt nichts an. Bilder hell und dunkel.
final class BackupRestoreUITests: XCTestCase {
    /// Je Lauf neu: findet sich die Kennung nach dem Import wieder, stammt die gewählte Datei sicher aus diesem Lauf.
    private let entry = "Salztabletten \(Int.random(in: 100_000...999_999))"

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .dark }

    private func shot(_ app: XCUIApplication, _ name: String, dark: Bool) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "\(name)-\(dark ? "dunkel" : "hell")"
        a.lifetime = .keepAlways
        add(a)
    }

    private func text(_ app: XCUIApplication, containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
    }

    private func type(_ app: XCUIApplication, in field: XCUIElement, _ value: String) {
        scroll(app, to: field)
        field.tap()
        field.typeText(value)
    }

    private func closeKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    private func stock(_ app: XCUIApplication) -> [String] {
        app.tabBars.buttons["Bestand"].tap()
        XCTAssertTrue(app.staticTexts["Energy Gel 100"].waitForExistence(timeout: 5), "Bestand zeigt die Produkte nicht")
        return app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' Carbs'")).allElementsBoundByIndex.map { $0.label }.sorted()
    }

    private func openDataSettings(_ app: XCUIApplication, button: String) -> XCUIElement {
        app.tabBars.buttons["Bestand"].tap()
        app.buttons["Einstellungen"].tap()
        let element = app.buttons[button]
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        scroll(app, to: element)
        XCTAssertTrue(element.exists, "„\(button)“ fehlt in den Einstellungen")
        return element
    }

    /// Erfundene Daten, nur über die Oberfläche: Listeneintrag, Bewertung im Verlauf, Packliste mit Haken.
    private func createData(_ app: XCUIApplication) {
        app.tabBars.buttons["Einkauf"].tap()
        app.buttons["Liste"].tap()
        app.buttons["Eintrag hinzufügen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Zur Einkaufsliste"].waitForExistence(timeout: 5))
        type(app, in: app.textFields["Text (z. B. Gel Sorte X)"], entry)
        type(app, in: app.textFields["Pflicht"], "3")
        closeKeyboard(app)
        app.navigationBars["Zur Einkaufsliste"].buttons["Hinzufügen"].tap()
        XCTAssertTrue(text(app, containing: entry).waitForExistence(timeout: 5))

        app.buttons["Entscheiden"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Produkt'")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Energy Gel'")).firstMatch.tap()
        type(app, in: app.textFields["Pflicht"], "20")
        type(app, in: app.textFields.matching(NSPredicate(format: "placeholderValue == 'optional'")).element(boundBy: 0), "30")
        closeKeyboard(app)
        let save = app.buttons["Im Verlauf sichern"]
        scroll(app, to: save)
        save.tap()

        app.tabBars.buttons["Training"].tap()
        app.buttons["Packlisten"].tap()
        app.buttons["Packliste anlegen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neue Packliste"].waitForExistence(timeout: 5))
        app.buttons["Anlegen"].tap()
        XCTAssertTrue(text(app, containing: "Entwurf").waitForExistence(timeout: 5))
        text(app, containing: "Entwurf").tap()
        let tick = app.buttons["Als gepackt abhaken"].firstMatch
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        tick.tap()
        XCTAssertTrue(app.buttons["Gepackt, Haken entfernen"].waitForExistence(timeout: 5))
    }

    // MARK: Dateien-Dialog (System). Beschriftungen je nach Simulatorsprache deutsch oder englisch.

    private func first(_ app: XCUIApplication, _ labels: [String], timeout: TimeInterval = 5) -> XCUIElement? {
        let query = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels))
        return query.firstMatch.waitForExistence(timeout: timeout) ? query.firstMatch : nil
    }

    private func attachTree(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func saveInFiles(_ app: XCUIApplication, dark: Bool) {
        guard let save = first(app, ["Sichern", "Speichern", "Save", "Bewegen", "Move"], timeout: 15) else {
            attachTree(app, "dialog-sichern")
            return XCTFail("Dateien-Dialog zum Sichern erscheint nicht")
        }
        shot(app, "30-sicherung-1-sichern", dark: dark)
        save.tap()
        confirmReplace(app)
        XCTAssertTrue(filesDialog(app).waitForNonExistence(timeout: 15), "Sichern schließt den Dialog nicht")
    }

    private func filesDialog(_ app: XCUIApplication) -> XCUIElement { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"] }

    /// Liegt von einem früheren Lauf schon eine Datei da, fragt iOS erst nach einigen Sekunden, ob sie ersetzt werden
    /// soll. Die Abfrage kommt vom System (meist SpringBoard). Solange gewartet wird, bis sie bestätigt ist oder der
    /// Dialog nach einer Mindestzeit ohne Abfrage verschwunden ist.
    private func confirmReplace(_ app: XCUIApplication) {
        let hosts = [XCUIApplication(bundleIdentifier: "com.apple.springboard"), app]
        let start = Date()
        while Date().timeIntervalSince(start) < 30 {
            for host in hosts {
                let replace = host.buttons.matching(NSPredicate(format: "label IN %@", ["Ersetzen", "Replace"])).firstMatch
                if replace.waitForExistence(timeout: 1) { return replace.tap() }
            }
            if Date().timeIntervalSince(start) > 10 && !filesDialog(app).exists { return }
        }
        for host in hosts { attachTree(host, "dialog-ersetzen") }
    }

    private func pickBackup(_ app: XCUIApplication, dark: Bool) {
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS 'CarbStock-Sicherung' OR identifier CONTAINS 'CarbStock-Sicherung'")).firstMatch
        if !file.waitForExistence(timeout: 8) {
            // Der Dialog öffnet bei „Zuletzt benutzt“: auf „Durchsuchen“ wechseln.
            first(app, ["Durchsuchen", "Browse"])?.tap()
        }
        guard file.waitForExistence(timeout: 10) else {
            attachTree(app, "dialog-oeffnen")
            return XCTFail("Die gesicherte Datei ist im Dateien-Dialog nicht zu finden")
        }
        shot(app, "30-sicherung-3-auswaehlen", dark: dark)
        file.tap()
        first(app, ["Öffnen", "Open"], timeout: 3)?.tap()
    }

    private func check(dark: Bool) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication()
        app.launchArguments = ["-CarbStockInMemory", "-CarbStockSampleData"]
        app.launch()

        createData(app)
        let before = stock(app)
        openDataSettings(app, button: "Sicherung exportieren").tap()
        saveInFiles(app, dark: dark)

        // Leerer Bestand: neuer Start ohne Beispieldaten, Speicher nur im Arbeitsspeicher.
        app.terminate()
        app.launchArguments = ["-CarbStockInMemory"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Bestand"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Energy Gel 100"].exists, "Nach dem Neustart ist der Bestand nicht leer")

        openDataSettings(app, button: "Sicherung importieren").tap()
        pickBackup(app, dark: dark)
        let imported = app.alerts["Hinweis"]
        XCTAssertTrue(imported.waitForExistence(timeout: 10), "Keine Meldung nach dem Import")
        for part in ["Einkaufsliste: 1", "Verlauf: 1", "Packlisten: 1"] {
            XCTAssertTrue(text(app, containing: part).exists, "Meldung nennt „\(part)“ nicht")
        }
        shot(app, "30-sicherung-4-importiert", dark: dark)
        imported.buttons["OK"].tap()

        // Zweiter Import: nichts Neues.
        let again = app.buttons["Sicherung importieren"]
        again.tap()
        pickBackup(app, dark: dark)
        XCTAssertTrue(imported.waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Nichts Neues").exists, "Zweiter Import legt etwas an")
        imported.buttons["OK"].tap()
        let footer = text(app, containing: "Die Sicherung ist eine JSON-Datei")
        scroll(app, to: footer)
        XCTAssertTrue(footer.label.contains("Packlisten"), "Erklärtext nennt die Packlisten nicht")
        shot(app, "30-sicherung-5-einstellungen", dark: dark)
        app.buttons["Fertig"].tap()

        XCTAssertEqual(stock(app), before, "Bestand weicht nach der Wiederherstellung ab")

        app.tabBars.buttons["Einkauf"].tap()
        app.buttons["Liste"].tap()
        XCTAssertTrue(text(app, containing: entry).waitForExistence(timeout: 5),
                      "Einkaufsliste fehlt oder die importierte Datei stammt nicht aus diesem Lauf")
        shot(app, "30-sicherung-6-einkaufsliste", dark: dark)
        app.buttons["Verlauf"].tap()
        XCTAssertTrue(text(app, containing: "Energy Gel").waitForExistence(timeout: 5), "Einkaufsverlauf fehlt")
        shot(app, "30-sicherung-7-verlauf", dark: dark)

        app.tabBars.buttons["Training"].tap()
        app.buttons["Packlisten"].tap()
        XCTAssertFalse(app.staticTexts["Keine Packlisten"].exists, "Packlisten fehlen")
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["Gepackt, Haken entfernen"].waitForExistence(timeout: 5), "Packliste oder Haken fehlt")
        shot(app, "30-sicherung-8-packliste", dark: dark)
    }

    func testBackupAndRestoreLight() { check(dark: false) }
    func testBackupAndRestoreDark() { check(dark: true) }
}
