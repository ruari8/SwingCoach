import XCTest

/// Each fast flick must move exactly one video, in Library and Auto review.
/// Sixteen clips leave room to see a skipped page before the end clamps it.
final class FastSwipePagingUITests: XCTestCase {
    private lazy var checks = FastSwipeChecks(test: self, seed: "swipes", count: 16)

    override func setUp() { continueAfterFailure = false }

    func testFastFlickMovesExactlyOneVideo() { checks.flicksInLibrary() }
    func testFastFlicksInAutoReviewAndAtLatestVideo() { checks.flicksInAutoReview() }
    func testAutoReviewReopensLatestAfterBrowsingDeletionAndNewClip() { checks.reopenAfterDeletionAndNewClip() }
}

/// The same checks over 171 clips, where momentum skipping first appeared.
/// Runs only on request: `scripts/verify.sh stress`.
final class FastSwipeStressUITests: XCTestCase {
    private lazy var checks = FastSwipeChecks(test: self, seed: "stress", count: 171)

    override func setUp() { continueAfterFailure = false }

    func testFastFlickMovesExactlyOneVideo() { checks.flicksInLibrary() }
    func testFastFlicksInAutoReviewAndAtLatestVideo() { checks.flicksInAutoReview() }
    func testAutoReviewReopensLatestAfterBrowsingDeletionAndNewClip() { checks.reopenAfterDeletionAndNewClip() }
}

private struct FastSwipeChecks {
    unowned let test: XCTestCase
    let seed: String
    let count: Int

    func flicksInLibrary() {
        let app = XCUIApplication.launched(seed: seed, ["-ui-testing-library"])
        let reference = app.staticTexts["Reference swing 7"]
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        for _ in 0..<4 where !reference.isHittable {
            app.swipeUp()
        }
        reference.tap()
        assertPage(app, 7)
        exerciseFlicks(app, startingAt: 7)
    }

    func flicksInAutoReview() {
        let app = XCUIApplication.launched(seed: seed, ["-ui-testing-auto-review"])
        assertPage(app, count)
        app.swipeLeft(velocity: XCUIGestureVelocity(rawValue: 6000))
        assertPage(app, count)
        var position = count
        for speed in [1500.0, 3000.0, 6000.0] {
            app.swipeRight(velocity: XCUIGestureVelocity(rawValue: speed))
            position -= 1
            assertPage(app, position)
        }
        exerciseFlicks(app, startingAt: count - 3)
    }

    func reopenAfterDeletionAndNewClip() {
        let app = XCUIApplication.launched(seed: seed, ["-ui-testing-auto-review"])
        assertPage(app, count)
        app.swipeRight()
        assertPage(app, count - 1)
        app.buttons["Close swing review"].tap()
        app.buttons["Review fixture swings"].tap()
        assertPage(app, count)

        deleteSelectedSwing(app)
        assertPage(app, count - 1, of: count - 1)
        app.swipeRight()
        assertPage(app, count - 2, of: count - 1)
        deleteSelectedSwing(app)
        assertPage(app, count - 2, of: count - 2, title: "Reference swing \(count - 1)")

        app.buttons["Close swing review"].tap()
        app.buttons["Append fixture swing"].tap()
        app.buttons["Review fixture swings"].tap()
        assertPage(app, count - 1, of: count - 1, title: "New fixture swing")
        app.swipeRight()
        assertPage(app, count - 2, of: count - 1, title: "Reference swing \(count - 1)")
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
            app.swipeLeft(velocity: XCUIGestureVelocity(rawValue: speed))
            position += 1
            assertPage(app, position)
        }
        for speed in [1500.0, 3000.0, 6000.0] {
            app.swipeRight(velocity: XCUIGestureVelocity(rawValue: speed))
            position -= 1
            assertPage(app, position)
        }
    }

    private func assertPage(_ app: XCUIApplication, _ number: Int, of total: Int? = nil, title: String? = nil,
                            file: StaticString = #filePath, line: UInt = #line) {
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), file: file, line: line)
        let expected = "\(number) of \(total ?? count)"
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
        test.add(attachment)
    }
}
