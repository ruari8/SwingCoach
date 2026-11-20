import XCTest

/// Launch arguments read by the app's DEBUG `UITestFixture`
/// (SwingCoach/Models/UITestFixture.swift), which documents each one.
extension XCUIApplication {
    /// Launches with erased app data and settings plus a synthetic Library.
    /// Seeds: empty, smoke, review, references, swipes, stress, sessions, positions.
    static func launched(seed: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-seed", seed] + arguments
        app.launch()
        return app
    }

    /// Opens the Library card whose label contains `title`, scrolling to it.
    /// Session cards carry the `swing-card` identifier; Starred and reference
    /// cards do not. Session cards sit in a lazy stack below the fold.
    func openLibraryCard(_ title: String, sessionCard: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let format = sessionCard ? "identifier == 'swing-card' AND label CONTAINS %@"
            : "identifier != 'swing-card' AND label CONTAINS %@"
        let card = buttons.matching(NSPredicate(format: format, title)).firstMatch
        XCTAssertTrue(buttons["Filter swings"].waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<5 where !(card.exists && card.isHittable) {
            scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(card.exists && card.isHittable, "No card for \(title)", file: file, line: line)
        card.tap()
    }

    /// Opens the player's tool rail when it is folded, as it is on the
    /// coaching walkthrough.
    func showPlayerTools(file: StaticString = #filePath, line: UInt = #line) {
        let fold = buttons["player-tools-fold"]
        XCTAssertTrue(fold.waitForExistence(timeout: 5), file: file, line: line)
        if fold.label == "Show player tools" { fold.tap() }
    }

    /// Relaunches without reseeding, so the data the test built persists.
    func relaunch(_ arguments: [String]) {
        terminate()
        launchArguments = arguments
        launch()
    }
}

/// The review counter on page `k of n` of a collection ordered newest
/// first (every Library collection, and the references the Auto fixtures
/// show): the player numbers swings in the order hit, oldest first.
func swingCounter(_ page: String) -> String {
    let parts = page.split(separator: " ")
    let index = Int(parts[0])!, total = Int(parts[2])!
    return "Swing \(total + 1 - index) of \(total)"
}

/// The page index (1 is the newest) behind a counter of `total` swings.
func pageIndex(fromCounter counter: String, total: Int) -> Int {
    let number = Int(counter.split(separator: " ")[1])!
    return total + 1 - number
}

enum Fixture {
    static let syntheticCamera = ["-ui-testing-camera", "synthetic"]
}
