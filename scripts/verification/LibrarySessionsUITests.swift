import XCTest

/// Drives Library session selection, slide-to-select and batch export against
/// the seeded library written by verify-library-sessions.sh (6 swings today, 3 yesterday).
final class LibrarySessionsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSessionSelectSlideSelectAndExport() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-library"]
        app.launch()

        let selectToday = app.buttons["Select Today session"]
        XCTAssertTrue(selectToday.waitForExistence(timeout: 15))
        attach("sessions")

        selectToday.tap()
        XCTAssertTrue(app.staticTexts["6 selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Yesterday"].exists)
        XCTAssertTrue(app.buttons["Deselect Today session"].exists)
        attach("today-selected")

        app.buttons["Deselect Today session"].tap()
        XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))

        // Slide from the first card across and down to the fourth (left/right, two rows).
        let cards = app.buttons.matching(identifier: "swing-card")
        let first = cards.element(boundBy: 0)
        let fourth = cards.element(boundBy: 3)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: fourth.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        XCTAssertTrue(app.staticTexts["4 selected"].waitForExistence(timeout: 5))
        attach("slide-selected-four")

        // A vertical drag on the cards still scrolls and leaves the selection alone.
        let header = app.staticTexts["Yesterday"]
        let headerY = header.frame.minY
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)),
            withVelocity: .fast,
            thenHoldForDuration: 0.1
        )
        XCTAssertTrue(app.staticTexts["4 selected"].exists)
        XCTAssertLessThan(header.frame.minY, headerY - 50, "Vertical drag should scroll the grid")
        attach("after-vertical-scroll")

        // Sliding back over a selected card removes the range it covers.
        app.staticTexts["Yesterday"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
            withVelocity: .fast,
            thenHoldForDuration: 0.1
        )
        XCTAssertTrue(app.buttons["Select Today session"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(first.frame.minY, 200)
        cards.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))

        app.buttons["Share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 20))
        attach("share-sheet")
    }

    private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
