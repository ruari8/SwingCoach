import XCTest

/// Drives Library session selection, slide-to-select and batch export over a
/// seeded Library of six swings today and three yesterday.
final class LibrarySessionsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSessionSelectSlideSelectAndExport() {
        let app = XCUIApplication.launched(seed: "sessions", ["-ui-testing-library"])

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

        let cards = app.buttons.matching(identifier: "swing-card")
        let first = cards.element(boundBy: 0)
        // Three columns: the fifth card is one row down and one across.
        let fifth = cards.element(boundBy: 4)

        // A slide that starts at a card's edge still anchors on that card.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: cards.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))
        app.buttons["Select Today session"].tap()
        app.buttons["Deselect Today session"].tap()
        XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))

        // Slide from the first card across and down to the fifth (left/right, two rows).
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: fifth.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        XCTAssertTrue(app.staticTexts["5 selected"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["5 selected"].exists)
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
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))

        app.buttons["Share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 20))
        attach("share-sheet")
    }

    /// Pinching steps the grid between 2, 3 and 5 columns, as in Photos,
    /// and the choice survives a relaunch.
    func testPinchChangesTheColumnCount() {
        let app = XCUIApplication.launched(seed: "sessions", ["-ui-testing-library"])
        let cards = app.buttons.matching(identifier: "swing-card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(columns(cards), 3, "Three columns by default")

        let grid = app.scrollViews.firstMatch
        grid.pinch(withScale: 2, velocity: 1)
        expectColumns(2, cards)
        attach("two-columns")

        app.relaunch(["-ui-testing-library"])
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(columns(cards), 2, "The column count is remembered")

        grid.pinch(withScale: 0.5, velocity: -1)
        expectColumns(3, cards)
        grid.pinch(withScale: 0.5, velocity: -1)
        expectColumns(5, cards)
        attach("five-columns")
        // Square tiles with hairline gutters: five fill the width.
        let tile = cards.firstMatch.frame
        XCTAssertEqual(tile.width, tile.height, accuracy: 1)
        XCTAssertEqual(tile.width * 5, app.frame.width, accuracy: 12)
    }

    /// Tiles in the first row: those level with the first tile.
    private func columns(_ cards: XCUIElementQuery) -> Int {
        let top = cards.firstMatch.frame.minY
        return cards.allElementsBoundByIndex.filter { abs($0.frame.minY - top) < 2 }.count
    }

    private func expectColumns(_ expected: Int, _ cards: XCUIElementQuery) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.columns(cards) == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "Expected \(expected) columns, saw \(columns(cards))")
    }

    private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
