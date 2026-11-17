import XCTest

/// Misura il tempo di avvio dei video per ogni tecnica anti-pubblicità.
/// Ogni risultato finisce nel log come: METRIC <configurazione> <video> <ms|timeout> <ads|noads>
final class StartTimeTests: XCTestCase {
    private let videos = [
        "https://m.youtube.com/watch?v=kJQP7kiw5Fk",
        "https://m.youtube.com/watch?v=JGwWNGJdvx8",
    ]

    override func setUp() { continueAfterFailure = true }

    private func measure(_ name: String, arguments: [String]) {
        for (index, url) in videos.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-LieveStartURL", url] + arguments
            app.launch()
            let label = app.staticTexts["lieve.metric"]
            var result = "timeout"
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                if label.exists, label.label.contains("ads"), let value = label.label.split(separator: " ").dropFirst().first {
                    result = "\(value) " + (label.label.hasSuffix("noads") ? "noads" : "ads")
                    break
                }
                sleep(1)
            }
            print("METRIC \(name) v\(index + 1) \(result)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "metric-\(name)-v\(index + 1)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    func test1Channel() { measure("channel", arguments: ["-adStrategy", "channel"]) }
    func test2Inline() { measure("inline", arguments: ["-adStrategy", "inline"]) }
    func test3Both() { measure("both", arguments: ["-adStrategy", "both"]) }
    func test4Prune() { measure("prune", arguments: ["-adStrategy", "prune"]) }
    func test5NoBlock() { measure("noblock", arguments: ["-adBlock", "NO"]) }

    /// Mini player: trascinamento del video verso il basso.
    func test6MiniPlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-LieveStartURL", videos[0]]
        app.launch()
        sleep(20)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "mini-1-prima"; before.lifetime = .keepAlways; add(before)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)
        sleep(3)
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "mini-2-dopo-trascinamento"; after.lifetime = .keepAlways; add(after)
        XCTAssertEqual(app.state, .runningForeground)
        print("MINIPLAYER done")
    }
}
