import XCTest

final class ReviewLockUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLibraryLockPersistsAcrossPaging() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-library"]
        app.launch()
        openFirstReference(app)
        exerciseLockAcrossPages(app)

        // Leaving review ends this lock preference, even without relaunching.
        app.buttons["Keep controls on screen"].tap()
        assertLock(app, enabled: true)
        app.buttons["Back to library"].tap()
        openFirstReference(app)
        assertLock(app, enabled: false)
    }

    func testAutoLockPersistsAcrossPaging() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-auto-review"]
        app.launch()
        // Test paging independently of which clip Auto selects on entry.
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        if position.label == "3 of 3" { page(app, number: 2) }
        if position.label == "2 of 3" { page(app, number: 1) }
        exerciseLockAcrossPages(app)
        let delete = app.buttons["Delete this swing"]
        XCTAssertTrue(delete.isHittable)
        XCTAssertFalse(delete.frame.intersects(app.buttons["Keep controls on screen"].frame))
        XCTAssertFalse(delete.frame.intersects(app.otherElements["playback-timeline"].frame))
        delete.tap()
        XCTAssertTrue(app.buttons["Delete from SwingCoach and Photos"].waitForExistence(timeout: 3))
        // Reaching confirmation proves Delete is usable. End without deleting
        // the fixture; system popovers do not always expose a Cancel button.
        app.terminate()
    }

    private func openFirstReference(_ app: XCUIApplication) {
        let reference = app.buttons.containing(.staticText, identifier: "Reference swing 1").firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 10), "Requires the synthetic fixtures from verify-review-lock.sh")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        reference.tap()
        assertPage(app, number: 1)
    }

    private func exerciseLockAcrossPages(_ app: XCUIApplication) {
        assertPage(app, number: 1)
        assertLock(app, enabled: false)
        // Cache a page with hidden controls before another page changes Lock.
        page(app, number: 2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["Keep controls on screen"].waitForNonExistence(timeout: 3))
        page(app, number: 1)
        app.buttons["Keep controls on screen"].tap()
        assertLock(app, enabled: true)
        for number in [2, 3, 2, 1] {
            page(app, number: number)
            assertLock(app, enabled: true)
            // Lock pins the controls when the video is tapped, on every page.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            assertLock(app, enabled: true)
        }

        // Playing a locked clip must keep controls visible past the hide delay.
        app.buttons["Play"].tap()
        let locked = app.buttons["Unlock controls"]
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: locked)
        hidden.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3.5), .completed)
        app.buttons["Pause"].tap()

        app.buttons["Unlock controls"].tap()
        assertLock(app, enabled: false)
        for number in [2, 3, 2, 1] {
            page(app, number: number)
            assertLock(app, enabled: false)
        }
        // Explicit unlock restores tap-to-hide, including on revisited players.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["Keep controls on screen"].waitForNonExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        assertLock(app, enabled: false)
    }

    private func page(_ app: XCUIApplication, number: Int) {
        let previous = Int(app.staticTexts["swing-position"].label.prefix(1))!
        let forward = number > previous
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.82 : 0.18, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.18 : 0.82, dy: 0.45))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        assertPage(app, number: number)
    }

    private func assertPage(_ app: XCUIApplication, number: Int) {
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(number) of 3"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }

    private func assertLock(_ app: XCUIApplication, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let label = enabled ? "Unlock controls" : "Keep controls on screen"
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "Expected \(label) on \(app.staticTexts["swing-position"].label)", file: file, line: line)
        XCTAssertTrue(app.buttons[label].isHittable, file: file, line: line)
        if enabled {
            XCTAssertTrue(app.otherElements["playback-timeline"].isHittable, file: file, line: line)
            XCTAssertTrue(app.buttons["Play"].isHittable || app.buttons["Pause"].isHittable, file: file, line: line)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(app.staticTexts["swing-position"].label) \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
