import XCTest

final class LibraryPagingUITests: XCTestCase {
    func testSideSwipeMovesToNextSwing() throws {
        let app = try launchFirstReferenceSwing()

        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let initialPosition = position.label

        let reviewPage = app.otherElements.matching(identifier: "swing-review-page").firstMatch
        XCTAssertTrue(reviewPage.waitForExistence(timeout: 5))
        let start = reviewPage.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        let end = reviewPage.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialPosition),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 2), .completed)
    }

    func testDrawingRailDoesNotOverlapPlayerLock() throws {
        let app = try launchFirstReferenceSwing()
        let drawButton = app.buttons["Draw straight lines"]
        let lockButton = app.buttons.matching(NSPredicate(format: "label == %@", "Keep controls on screen")).firstMatch

        XCTAssertTrue(drawButton.waitForExistence(timeout: 5))
        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        XCTAssertFalse(drawButton.frame.intersects(lockButton.frame))
        XCTAssertLessThan(drawButton.frame.midX, lockButton.frame.midX)
    }

    private func launchFirstReferenceSwing() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-library")
        app.launch()

        let firstReference = app.staticTexts["Reference swing 1"]
        guard firstReference.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires ignored local fixtures from SwingCoach/ReferenceSwings/README.md")
        }
        firstReference.tap()
        return app
    }
}
