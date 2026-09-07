import XCTest

/// Run with scripts/verify-review.sh, which seeds only its disposable Simulator.
final class LibraryReviewRegressionUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSwipesFollowStarsAndStayInPersonalCollection() throws {
        let app = launchLibrary()
        try open("Review A starred DTL", in: app)
        assertPosition("1 of 3", title: "Review A starred DTL", in: app)
        swipeNext(in: app)
        assertPosition("2 of 3", title: "Review B Face-On", in: app)
        swipeNext(in: app)
        assertPosition("3 of 3", title: "Review C DTL", in: app)
        swipeNext(in: app)
        assertPosition("3 of 3", title: "Review C DTL", in: app)
    }

    func testSwipesRespectDTLFilter() throws {
        let app = launchLibrary()
        app.buttons["Filter swings"].tap()
        app.buttons["Down the Line"].tap()
        try open("Review A starred DTL", in: app)
        assertPosition("1 of 2", title: "Review A starred DTL", in: app)
        swipeNext(in: app)
        assertPosition("2 of 2", title: "Review C DTL", in: app)
        attachScreenshot(app, name: "DTL filter retained after swipe")
    }

    func testReferenceSwipesStayInReferenceCollection() throws {
        let app = launchLibrary()
        try open("Reference swing 1", in: app)
        assertPosition("1 of 3", title: "Reference swing 1", in: app)
        swipeNext(in: app)
        assertPosition("2 of 3", title: "Reference swing 2", in: app)
    }

    func testDrawingRemainsAvailableWhenDeviceRotates() throws {
        let app = launchLibrary()
        try open("Review A starred DTL", in: app)
        let draw = app.buttons["Draw straight lines"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5))
        draw.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.43))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["Undo last line"].waitForExistence(timeout: 2))
        app.buttons["Finish drawing lines"].tap()
        attachScreenshot(app, name: "Drawn line portrait")
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
        attachScreenshot(app, name: "Drawn line portrait with device held landscape")
        draw.tap()
        app.buttons["Clear all lines"].tap()
        XCTAssertFalse(app.buttons["Undo last line"].exists)
    }

    private func launchLibrary() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-library"]
        app.launch()
        return app
    }

    private func open(_ title: String, in app: XCUIApplication) throws {
        let card = app.staticTexts[title]
        for _ in 0..<5 {
            if card.exists && card.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        guard card.exists && card.isHittable else {
            throw XCTSkip("Run scripts/verify-review.sh to install the disposable review fixtures")
        }
        card.tap()
    }

    private func swipeNext(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func assertPosition(_ label: String, title: String, in app: XCUIApplication) {
        let position = app.staticTexts["swing-position"]
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND value == %@", label, title), object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 3), .completed,
                       "Expected \(label), \(title); actual \(position.label), \(String(describing: position.value))")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        // Capture the whole display; application screenshots can crop using
        // stale portrait bounds after a Simulator orientation change.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
