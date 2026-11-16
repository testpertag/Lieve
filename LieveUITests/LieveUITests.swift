import XCTest

/// Prova d'uso reale nel simulatore: tocchi sulla pagina, scorrimento, menu e trascinamento.
/// Dopo ogni passo controlla che l'app sia ancora in esecuzione.
final class LieveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-LieveStartURL", "https://m.youtube.com/watch?v=dQw4w9WgXcQ"]
        app.launch()
    }

    private func assertAlive(_ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "L'app si è chiusa dopo: \(step)")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func testTouchesMenuAndDrag() {
        sleep(12)
        snapshot("1-avvio")

        point(0.5, 0.6).tap(); sleep(2); assertAlive("tocco sulla pagina")
        point(0.5, 0.25).tap(); sleep(2); assertAlive("tocco sul video")
        app.swipeUp(); sleep(2); assertAlive("scorrimento in su")
        app.swipeDown(); sleep(2); assertAlive("scorrimento in giù")
        snapshot("2-dopo-tocchi")

        let menu = app.buttons["Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Pulsante Menu non trovato")
        menu.tap(); sleep(1); assertAlive("apertura menu")
        XCTAssertTrue(app.buttons["Impostazioni"].waitForExistence(timeout: 5))
        snapshot("3-menu-aperto")

        app.buttons["Indirizzo"].tap(); sleep(2); assertAlive("foglio indirizzo")
        snapshot("4-indirizzo")
        app.buttons["Annulla"].tap(); sleep(1); assertAlive("chiusura indirizzo")

        app.buttons["Impostazioni"].tap(); sleep(2); assertAlive("impostazioni")
        snapshot("5-impostazioni")
        app.buttons["Fine"].tap(); sleep(1); assertAlive("chiusura impostazioni")

        app.buttons["Chiudi menu"].tap(); sleep(1); assertAlive("chiusura menu")
        menu.press(forDuration: 0.2, thenDragTo: point(0.1, 0.4)); sleep(1); assertAlive("trascinamento menu")
        snapshot("6-menu-spostato")

        point(0.5, 0.7).tap(); sleep(1)
        point(0.5, 0.7).press(forDuration: 1.2); sleep(2); assertAlive("pressione prolungata")
        snapshot("7-fine")
    }
}
