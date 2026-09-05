import XCTest

final class FastSwipePagingUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFastFlickMovesExactlyOneVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-library"]
        app.launch()
        let reference = app.staticTexts["Reference swing 7"]
        for _ in 0..<4 where !reference.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        reference.tap()
        assertPage(app, 7)
        exerciseFlicks(app, startingAt: 7)
    }

    func testFastFlicksInAutoReviewAndAtFirstVideo() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-auto-review"]
        app.launch()
        assertPage(app, 1)
        app.swipeRight(velocity: XCUIGestureVelocity(rawValue: 6000))
        assertPage(app, 1)
        exerciseFlicks(app, startingAt: 1)
        app.swipeRight(velocity: XCUIGestureVelocity(rawValue: 6000))
        assertPage(app, 1)
    }

    private func exerciseFlicks(_ app: XCUIApplication, startingAt initialPosition: Int) {
        var position = initialPosition
        for speed in [1500.0, 3000.0, 6000.0] {
            let velocity = XCUIGestureVelocity(rawValue: speed)
            app.swipeLeft(velocity: velocity)
            position += 1
            assertPage(app, position)
        }
        for speed in [1500.0, 3000.0, 6000.0] {
            app.swipeRight(velocity: XCUIGestureVelocity(rawValue: speed))
            position -= 1
            assertPage(app, position)
        }
    }

    private func assertPage(_ app: XCUIApplication, _ number: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), file: file, line: line)
        let expected = "\(number) of 171"
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed,
                       "One flick must advance one video. Expected \(expected), got \(position.label)",
                       file: file, line: line)
        let visible = app.otherElements.matching(identifier: "swing-review-page")
            .allElementsBoundByIndex.filter { $0.frame.intersection(app.frame).width > 2 }
        XCTAssertEqual(visible.count, 1, "Pager must finish on a whole video", file: file, line: line)
        XCTAssertEqual(visible.first?.label, "Reference swing \(number)", file: file, line: line)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settled \(expected)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
