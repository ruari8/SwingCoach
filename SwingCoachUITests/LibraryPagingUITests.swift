import XCTest

final class LibraryPagingUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPagingSettlesOnOneWholeVideo() throws {
        let app = try launchFirstReferenceSwing()
        exercisePaging(app)
    }

    func testAutoReviewPagingAndDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-auto-review"]
        app.launch()
        guard app.staticTexts["swing-position"].waitForExistence(timeout: 5),
              app.staticTexts["swing-position"].label != "0 of 0" else {
            throw XCTSkip("Requires ignored local reference videos")
        }
        let speedButton = app.buttons.matching(NSPredicate(format: "label == %@", "Change playback speed")).firstMatch
        XCTAssertTrue(speedButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(speedButton.frame.minY, app.buttons["Close swing review"].frame.minY - 8)
        exercisePaging(app)
        drag(app, from: 0.82, to: 0.18, velocity: .fast)
        assertSettledPage(app, position: "2 of 3")
        let deleteButton = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", "Delete this swing")).allElementsBoundByIndex.first {
            $0.frame.intersects(app.frame) && $0.isHittable
        })
        deleteButton.tap()
        app.buttons["Delete from SwingCoach and Photos"].tap()
        assertSettledPage(app, position: "2 of 2", reference: 3)
        drag(app, from: 0.18, to: 0.82, velocity: .fast)
        assertSettledPage(app, position: "1 of 2")
    }

    func testOpeningMiddleSwingAndPlaybackGestures() throws {
        let app = try launchFirstReferenceSwing(number: 2)
        assertSettledPage(app, position: "2 of 3")

        let timeline = try XCTUnwrap(app.otherElements.matching(identifier: "playback-timeline").allElementsBoundByIndex.first {
            app.frame.contains($0.frame) && $0.isHittable
        })
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        assertSettledPage(app, position: "2 of 3")
        XCTAssertGreaterThan(Double(timeline.value as? String ?? "") ?? 0, 0)

        app.buttons["Draw straight lines"].tap()
        drag(app, from: 0.18, to: 0.82, velocity: .slow)
        assertSettledPage(app, position: "2 of 3")
    }

    func testHoldCanBecomePageSwipe() throws {
        let app = try launchFirstReferenceSwing(number: 2)
        assertSettledPage(app, position: "2 of 3")
        // Starting with a hold must still let a subsequent horizontal drag page.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45))
        edge.press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.45)))
        assertSettledPage(app, position: "3 of 3")
    }

    func testStationaryHoldStopsOnRelease() throws {
        let app = try launchFirstReferenceSwing(number: 2)
        assertSettledPage(app, position: "2 of 3")
        let timeline = try XCTUnwrap(app.otherElements.matching(identifier: "playback-timeline").allElementsBoundByIndex.first {
            app.frame.contains($0.frame) && $0.isHittable
        })
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)).press(forDuration: 0.4)
        let releasedTime = try XCTUnwrap(timeline.value as? String)
        XCTAssertGreaterThan(Double(releasedTime) ?? 0, 0, "Holding the edge must step the video")
        let keepsStepping = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", releasedTime), object: timeline
        )
        keepsStepping.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [keepsStepping], timeout: 0.7), .completed, "Stepping must stop when the finger lifts")
    }

    private func exercisePaging(_ app: XCUIApplication) {
        assertSettledPage(app, position: "1 of 3")

        // A short drag must return to the same page, including at either end.
        drag(app, from: 0.5, to: 0.55, velocity: .slow)
        assertSettledPage(app, position: "1 of 3")
        for _ in 0..<3 {
            drag(app, from: 0.82, to: 0.18, velocity: .slow)
            assertSettledPage(app, position: "2 of 3")
            drag(app, from: 0.82, to: 0.18, velocity: .fast)
            assertSettledPage(app, position: "3 of 3")
            drag(app, from: 0.82, to: 0.18, velocity: .fast)
            assertSettledPage(app, position: "3 of 3")
            drag(app, from: 0.18, to: 0.82, velocity: .slow)
            assertSettledPage(app, position: "2 of 3")
            drag(app, from: 0.18, to: 0.82, velocity: .fast)
            assertSettledPage(app, position: "1 of 3")
        }
    }

    private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat, velocity: XCUIGestureVelocity) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.45))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0.05)
    }

    private func assertSettledPage(_ app: XCUIApplication, position: String, reference: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["swing-position"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", position), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed, "Expected \(position), got \(label.label)", file: file, line: line)
        let viewport = app.frame
        let visiblePages = app.otherElements.matching(identifier: "swing-review-page").allElementsBoundByIndex.filter {
            $0.frame.intersection(viewport).width > 2
        }
        XCTAssertEqual(visiblePages.count, 1, "Adjacent videos remain visible after settling: \(visiblePages.map(\.frame))", file: file, line: line)
        if let page = visiblePages.first {
            let referenceNumber = reference.map(String.init) ?? String(position.prefix { $0 != " " })
            XCTAssertEqual(page.label, "Reference swing \(referenceNumber)", "Page label and visible video must agree", file: file, line: line)
            XCTAssertEqual(page.frame.minX, viewport.minX, accuracy: 1, "Video is stuck between pages", file: file, line: line)
            XCTAssertEqual(page.frame.width, viewport.width, accuracy: 1, file: file, line: line)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settled \(position)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    private func launchFirstReferenceSwing(number: Int = 1) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-library")
        app.launch()

        let firstReference = app.staticTexts["Reference swing \(number)"]
        guard firstReference.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires ignored local fixtures from SwingCoach/ReferenceSwings/README.md")
        }
        firstReference.tap()
        return app
    }
}
