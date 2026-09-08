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

    func testFastFlicksInAutoReviewAndAtLatestVideo() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-auto-review"]
        app.launch()
        assertPage(app, 171)
        app.swipeLeft(velocity: XCUIGestureVelocity(rawValue: 6000))
        assertPage(app, 171)
        var position = 171
        for speed in [1500.0, 3000.0, 6000.0] {
            app.swipeRight(velocity: XCUIGestureVelocity(rawValue: speed))
            position -= 1
            assertPage(app, position)
        }
        exerciseFlicks(app, startingAt: 168)
    }

    func testAutoReviewReopensLatestAfterBrowsingDeletionAndNewClip() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-auto-review"]
        app.launch()
        assertPage(app, 171)
        app.swipeRight()
        assertPage(app, 170)
        app.buttons["Close swing review"].tap()
        app.buttons["Review fixture swings"].tap()
        assertPage(app, 171)

        deleteSelectedSwing(app)
        assertPage(app, 170, count: 170)
        app.swipeRight()
        assertPage(app, 169, count: 170)
        deleteSelectedSwing(app)
        assertPage(app, 169, count: 169, title: "Reference swing 170")

        app.buttons["Close swing review"].tap()
        app.buttons["Append fixture swing"].tap()
        app.buttons["Review fixture swings"].tap()
        assertPage(app, 170, count: 170, title: "New fixture swing")
        app.swipeRight()
        assertPage(app, 169, count: 170, title: "Reference swing 170")
    }

    private func deleteSelectedSwing(_ app: XCUIApplication) {
        let delete = app.buttons["Delete this swing"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.buttons["Delete from SwingCoach"].tap()
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

    private func assertPage(_ app: XCUIApplication, _ number: Int, count: Int = 171, title: String? = nil,
                            file: StaticString = #filePath, line: UInt = #line) {
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), file: file, line: line)
        let expected = "\(number) of \(count)"
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed,
                       "One flick must advance one video. Expected \(expected), got \(position.label)",
                       file: file, line: line)
        let visible = app.otherElements.matching(identifier: "swing-review-page")
            .allElementsBoundByIndex.filter { $0.frame.intersection(app.frame).width > 2 }
        XCTAssertEqual(visible.count, 1, "Pager must finish on a whole video", file: file, line: line)
        XCTAssertEqual(visible.first?.label, title ?? "Reference swing \(number)", file: file, line: line)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settled \(expected)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
