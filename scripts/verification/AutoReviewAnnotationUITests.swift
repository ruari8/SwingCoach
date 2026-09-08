import XCTest

/// Camera output is substituted by the capture verification script. Both review
/// entry points, the line canvas, and disk persistence use production code.
final class AutoReviewAnnotationUITests: XCTestCase {
    func testLinesFollowSavedClipFromCaptureToLibraryAfterRelaunch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-capture-controls-reset"]
        app.launch()
        let saved = app.buttons["capture-saved-swings"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        beginDrawing(app)
        XCTAssertFalse(app.buttons["Undo last line"].exists)
        drawLine(app)
        XCTAssertTrue(app.buttons["Undo last line"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["swing-position"].label, "1 of 3", "Drawing must not page")
        app.buttons["Undo last line"].tap()
        XCTAssertFalse(app.buttons["Undo last line"].exists)
        drawLine(app)
        XCTAssertTrue(app.buttons["Undo last line"].waitForExistence(timeout: 2))
        app.buttons["Finish drawing lines"].tap()
        attach("auto-review-line")

        swipe(app, from: 0.8, to: 0.2)
        assertPosition("2 of 3", app)
        beginDrawing(app)
        XCTAssertFalse(app.buttons["Undo last line"].exists, "A line must not leak to the next clip")
        app.buttons["Finish drawing lines"].tap()
        swipe(app, from: 0.2, to: 0.8)
        assertPosition("1 of 3", app)
        beginDrawing(app)
        XCTAssertTrue(app.buttons["Undo last line"].exists)
        app.buttons["Finish drawing lines"].tap()
        app.buttons["Close swing review"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        beginDrawing(app)
        XCTAssertTrue(app.buttons["Undo last line"].exists, "Reopening Auto review must retain the line")
        app.buttons["Close swing review"].tap()

        app.terminate()
        app.launchArguments = ["-ui-testing-library"]
        app.launch()
        let card = app.staticTexts["Reference swing 1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        beginDrawing(app)
        XCTAssertTrue(app.buttons["Undo last line"].exists, "Library must reload Auto's line from disk for the same UUID")
        app.buttons["Finish drawing lines"].tap()
        attach("library-line-after-relaunch")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width >= app.frame.height
        }, object: nil)
        rotated.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 1.5), .completed)
        beginDrawing(app)
        XCTAssertTrue(app.buttons["Undo last line"].exists)
        attach("library-line-portrait-after-rotation")
        app.buttons["Clear all lines"].tap()
        XCTAssertFalse(app.buttons["Undo last line"].exists)
        app.buttons["Finish drawing lines"].tap()
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Back to library"].tap()
        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        beginDrawing(app)
        XCTAssertFalse(app.buttons["Undo last line"].exists, "Clearing in Library must also clear Auto review")
        app.buttons["Finish drawing lines"].tap()
        app.buttons["Close swing review"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Auto"].isSelected)
    }

    private func beginDrawing(_ app: XCUIApplication) {
        let draw = app.buttons["Draw straight lines"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5))
        draw.tap()
        XCTAssertTrue(app.buttons["Finish drawing lines"].exists)
    }

    private func drawLine(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.43))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipe(_ app: XCUIApplication, from: Double, to: Double) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.43))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.43))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func assertPosition(_ label: String, _ app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: app.staticTexts["swing-position"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
