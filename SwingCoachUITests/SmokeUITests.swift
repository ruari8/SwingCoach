import XCTest

/// The shortest journey through the app: launch into the Library, play a clip,
/// go back, and enter Capture.
final class SmokeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLaunchPlayClipAndEnterCapture() {
        let app = XCUIApplication.launched(seed: "smoke", ["-ui-testing-library"] + Fixture.syntheticCamera)
        let card = app.buttons.matching(identifier: "swing-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let timeline = app.otherElements["playback-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        app.buttons["Play"].tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(timeline.value as? String ?? "") ?? 0) > 0.1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed, "The clip must play")
        attach(app, "clip-playing")

        app.buttons["Back to library"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Auto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Auto"].isSelected)
        attach(app, "capture")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
