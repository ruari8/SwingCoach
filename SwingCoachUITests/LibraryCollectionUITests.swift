import XCTest

/// Review swipes stay inside the collection the card was opened from. The
/// review seed has B (Face-On), A and C (starred DTL), newest first, plus
/// three references.
final class LibraryCollectionUITests: XCTestCase {
    func testSessionSwipesFollowDateAndStayInPersonalCollection() {
        let app = launchLibrary()
        app.openLibraryCard("Review A starred DTL", sessionCard: true)
        assertPosition("2 of 3", title: "Review A starred DTL", in: app)
        swipeNext(in: app)
        assertPosition("3 of 3", title: "Review C DTL", in: app)
        swipeNext(in: app)
        assertPosition("3 of 3", title: "Review C DTL", in: app)
    }

    func testStarredSwipesStayInStarredCollection() {
        let app = launchLibrary()
        app.openLibraryCard("Review A starred DTL", sessionCard: false)
        assertPosition("1 of 2", title: "Review A starred DTL", in: app)
        swipeNext(in: app)
        assertPosition("2 of 2", title: "Review C DTL", in: app)
        swipeNext(in: app)
        assertPosition("2 of 2", title: "Review C DTL", in: app)
    }

    func testSwipesRespectDTLFilter() {
        let app = launchLibrary()
        app.buttons["Filter swings"].tap()
        app.buttons["Down the Line"].tap()
        app.openLibraryCard("Review A starred DTL", sessionCard: true)
        assertPosition("1 of 2", title: "Review A starred DTL", in: app)
        swipeNext(in: app)
        assertPosition("2 of 2", title: "Review C DTL", in: app)
        attachScreenshot(app, name: "DTL filter retained after swipe")
    }

    func testReferenceSwipesStayInReferenceCollection() {
        let app = launchLibrary()
        let reference = app.staticTexts["Reference swing 1"]
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        reference.tap()
        assertPosition("1 of 3", title: "Reference swing 1", in: app)
        swipeNext(in: app)
        assertPosition("2 of 3", title: "Reference swing 2", in: app)
    }

    private func launchLibrary() -> XCUIApplication {
        XCUIApplication.launched(seed: "review", ["-ui-testing-library"])
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
