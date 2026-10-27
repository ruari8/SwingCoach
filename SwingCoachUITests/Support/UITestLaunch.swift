import XCTest

/// Launch arguments read by the app's DEBUG `UITestFixture`
/// (SwingCoach/Models/UITestFixture.swift), which documents each one.
extension XCUIApplication {
    /// Launches with erased app data and settings plus a synthetic Library.
    /// Seeds: empty, smoke, review, references, swipes, stress, sessions.
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

    /// Relaunches without reseeding, so the data the test built persists.
    func relaunch(_ arguments: [String]) {
        terminate()
        launchArguments = arguments
        launch()
    }
}

enum Fixture {
    static let syntheticCamera = ["-ui-testing-camera", "synthetic"]
}
