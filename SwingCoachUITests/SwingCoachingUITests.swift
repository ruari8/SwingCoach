import XCTest

/// On-device coaching in the review player and the session summary, on the
/// `coaching` seed: five DTL clips in one session with stored reports, four
/// of which steepen the shaft in transition (drawn at P5, 1.85 s).
final class SwingCoachingUITests: XCTestCase {
    func testVerdictJumpsToItsDrawingAndListsTheMeasurements() throws {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        let pill = app.buttons["swing-coaching-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Coaching: Shaft steepens coming down")
        let timeline = try XCTUnwrap(app.otherElements.matching(identifier: "playback-timeline")
            .allElementsBoundByIndex.first { $0.isHittable })
        let transitionCaption = app.descendants(matching: .any)["coaching-caption-transition"]
        let hipsCaption = app.descendants(matching: .any)["coaching-caption-hipDepthImpact"]

        // First tap: pause on the position the finding was measured at.
        pill.tap()
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.85, accuracy: 0.01)
        XCTAssertTrue(app.buttons["swing-position-P5"].isSelected)
        XCTAssertTrue(transitionCaption.waitForExistence(timeout: 2), "The drawing is captioned")
        XCTAssertTrue(transitionCaption.label.contains("Shaft steepens coming down"), transitionCaption.label)
        attach(app, "coaching-drawing-on-P5")

        // Second tap: every measurement, grouped by position.
        pill.tap()
        let summary = app.descendants(matching: .any)["coaching-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("1 of 3 measurements in zone."), summary.label)
        XCTAssertTrue(app.buttons["coaching-metric-headHeightTop"].exists)
        attach(app, "coaching-measurements")
        // Impact is further down the list.
        let hips = app.buttons["coaching-metric-hipDepthImpact"]
        for _ in 0..<3 where !(hips.exists && hips.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(hips.exists && hips.isHittable)

        // Picking one moves the player to its position and draws it.
        hips.tap()
        XCTAssertTrue(hipsCaption.waitForExistence(timeout: 3))
        XCTAssertTrue(hipsCaption.label.contains("Hips moved toward the ball"), hipsCaption.label)
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.95, accuracy: 0.01)

        // Away from a measured position nothing is drawn.
        app.buttons["swing-position-P1"].tap()
        XCTAssertFalse(hipsCaption.exists)
        XCTAssertFalse(transitionCaption.exists)
    }

    func testSessionSummaryNamesWhatKeptHappening() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Filter swings"].waitForExistence(timeout: 10))
        app.buttons["session-coaching-button"].firstMatch.tap()

        let theme = app.descendants(matching: .any)["session-theme-steepTransition-transition-1"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shaft steepens coming down"].exists)
        XCTAssertTrue(app.staticTexts["4 of 5 swings · P5 lead arm parallel down"].exists)
        XCTAssertTrue(app.staticTexts["Start here"].exists)
        attach(app, "session-coaching")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
