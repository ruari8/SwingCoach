import XCTest

/// Straight-line drawing on a Library review, including with the device held
/// sideways while the interface stays portrait.
final class ReviewAnnotationUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testDrawingRemainsAvailableWhenDeviceRotates() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.launched(seed: "review", ["-ui-testing-library"])
        app.openLibraryCard("Review A starred DTL", sessionCard: true)
        let draw = app.buttons["Draw straight lines"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5))
        draw.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.43))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["Undo last line"].waitForExistence(timeout: 2))
        app.buttons["Finish drawing lines"].tap()
        attachScreenshot(name: "Drawn line portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.width >= app.frame.height }, object: nil
        )
        rotated.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 1.5), .completed)
        XCTAssertTrue(app.buttons["Draw straight lines"].waitForExistence(timeout: 5))
        // Drawing remains usable while the interface stays in portrait.
        draw.tap()
        XCTAssertTrue(app.buttons["Undo last line"].waitForExistence(timeout: 2))
        app.buttons["Finish drawing lines"].tap()
        attachScreenshot(name: "Drawn line portrait with device held landscape")
        draw.tap()
        app.buttons["Clear all lines"].tap()
        XCTAssertFalse(app.buttons["Undo last line"].exists)
    }

    private func attachScreenshot(name: String) {
        // Capture the whole display; application screenshots can crop using
        // stale portrait bounds after a Simulator orientation change.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
