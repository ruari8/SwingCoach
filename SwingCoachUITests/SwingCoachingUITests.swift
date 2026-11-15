import XCTest

/// On-device coaching in the review player, the session review and on the
/// Auto camera screen, on the `coaching` seed: five DTL clips in one
/// session with stored reports, four of which steepen the shaft in
/// transition (drawn at P5, 1.85 s). With the synthetic camera, those five
/// are the Auto session.
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

    func testSessionReviewShowsTheThemeItsPicturesAndEachSwing() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Filter swings"].waitForExistence(timeout: 10))
        app.buttons["session-coaching-button"].firstMatch.tap()

        let theme = app.descendants(matching: .any)["session-theme-steepTransition-transition-1"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shaft steepens coming down"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["4 of 5 swings · P5 lead arm parallel down"].exists)
        XCTAssertTrue(app.staticTexts["Start here"].exists)

        // A dot a swing, in the order hit. The fifth is the first with four
        // behind it, so it is the one that gets the session's theme.
        let third = app.buttons["session-swing-dot-3"]
        XCTAssertTrue(third.exists)
        XCTAssertEqual(third.label, "Swing 3: Good swing")
        XCTAssertEqual(app.buttons["session-swing-dot-5"].label, "Swing 5: Shaft steepens coming down")

        // The theme at its worst and at its best, as pictures.
        XCTAssertTrue(app.buttons["session-example-1"].waitForExistence(timeout: 5), "Shows it most")
        XCTAssertTrue(app.buttons["session-example-3"].exists, "Your best here")
        attach(app, "session-coaching")

        // The theme's metric swing by swing.
        let trend = app.descendants(matching: .any)["session-trend-transition"]
        for _ in 0..<4 where !(trend.exists && trend.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(trend.exists)
        XCTAssertTrue(trend.label.contains("1 of 5 swings in the green band"), trend.label)
        attach(app, "session-coaching-trend")

        // A dot opens its swing.
        for _ in 0..<4 where !(third.exists && third.isHittable) {
            app.collectionViews.firstMatch.swipeDown(velocity: .slow)
        }
        third.tap()
        let pill = app.buttons["swing-coaching-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Coaching: Good swing")
    }

    func testRecapOnTheCameraComparesTheLastSwingsAndOpensOne() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.launched(seed: "coaching", Fixture.syntheticCamera)
        let chip = app.buttons["coach-cadence"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Coach speaks: Every 5 swings")
        // The session's five swings were measured before the camera
        // opened: no recap comes up by itself, and no verdict per swing.
        let recap = app.descendants(matching: .any)["coach-recap"]
        XCTAssertFalse(recap.exists)
        XCTAssertFalse(app.buttons["coach-latest-verdict"].exists)

        chip.tap()
        app.buttons["Recap the last swings"].tap()
        XCTAssertTrue(recap.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Last 5 swings"].exists)
        XCTAssertTrue(app.staticTexts["Shaft steepens coming down"].exists)
        XCTAssertTrue(app.staticTexts["4 of 5 swings · P5 lead arm parallel down"].exists)
        attach(app, "capture-recap")

        app.buttons["coach-recap-open"].tap()
        let third = app.buttons["coach-compare-swing-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["coach-compare-swing-1"].exists)
        XCTAssertTrue(app.staticTexts["in zone"].exists, "The clean swing is in zone on the theme")
        attach(app, "capture-recap-compare")

        // A swing in the comparison opens in the player.
        third.tap()
        let pill = app.buttons.matching(identifier: "swing-coaching-pill").allElementsBoundByIndex
            .first { $0.isHittable } ?? app.buttons["swing-coaching-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Coaching: Good swing")
        XCTAssertEqual(app.staticTexts["swing-position"].label, "3 of 5")
    }

    func testEverySwingSettingShowsTheLastVerdictOnTheCamera() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.launched(seed: "coaching", Fixture.syntheticCamera + ["-coaching.cadence", "everySwing"])
        let verdict = app.buttons["coach-latest-verdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        XCTAssertEqual(verdict.label, "Last swing: Shaft steepens coming down")
        XCTAssertEqual(app.buttons["coach-cadence"].label, "Coach speaks: Every swing")
        attach(app, "capture-latest-verdict")

        // Closing the recap brings the verdict back.
        app.buttons["coach-cadence"].tap()
        app.buttons["Recap the last swings"].tap()
        XCTAssertTrue(app.buttons["coach-recap-close"].waitForExistence(timeout: 3))
        XCTAssertFalse(verdict.exists)
        app.buttons["coach-recap-close"].tap()
        XCTAssertTrue(verdict.waitForExistence(timeout: 3))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
