import XCTest

/// Run with scripts/verify-capture-controls.sh. The scratch build substitutes
/// camera output and telemetry, while settings, capture controls and review are real.
final class CaptureControlsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testStatsDefaultOffPersistAndFollowBothCaptureModes() {
        let app = launch()
        let auto = app.segmentedControls.buttons["Auto"]
        let manual = app.segmentedControls.buttons["Manual"]
        XCTAssertTrue(auto.waitForExistence(timeout: 5))
        XCTAssertTrue(auto.isSelected)
        XCTAssertLessThan(auto.frame.minX, manual.frame.minX)
        XCTAssertFalse(app.staticTexts["capture-model-stats"].exists)
        XCTAssertTrue(app.buttons["capture-saved-swings"].isEnabled)
        attach(app, "auto-default-clean")

        openSettings(app)
        let statsToggle = app.switches["show-capture-model-stats"]
        XCTAssertEqual(statsToggle.value as? String, "0")
        tapSwitch(statsToggle)
        XCTAssertEqual(statsToggle.value as? String, "1")
        returnToCapture(app)
        assertStats("8.0 fps / 56 ms", in: app)
        attach(app, "auto-stats-enabled")

        app.terminate()
        app.launchArguments = []
        app.launch()
        assertStats("8.0 fps / 56 ms", in: app)
        let topRow = app.buttons["capture-frame-rate"].frame
        app.segmentedControls.buttons["Manual"].tap()
        XCTAssertFalse(app.staticTexts["capture-model-stats"].exists)
        app.buttons["Start recording"].tap()
        XCTAssertTrue(app.buttons["Stop recording"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture-frame-rate"].exists)
        XCTAssertFalse(app.segmentedControls["capture-mode"].exists)
        let timer = app.staticTexts["capture-recording-timer"]
        XCTAssertTrue(timer.exists)
        XCTAssertEqual(timer.frame.midY, topRow.midY, accuracy: 3)
        // The red dot and timer are centred together, so the text sits slightly
        // to the right of the screen's centre.
        XCTAssertEqual(timer.frame.midX, app.frame.midX, accuracy: 12)
        XCTAssertEqual(app.staticTexts["capture-status-title"].label, "Detecting swings")
        XCTAssertEqual(app.staticTexts["capture-status-detail"].label, "2 detected")
        assertStats("12.5 fps / 42 ms", in: app)
        XCTAssertLessThanOrEqual(app.staticTexts["capture-model-stats"].frame.maxX,
                                 app.buttons["Stop recording"].frame.minX)
        attach(app, "manual-recording-with-stats")

        assertPortraitAfterRotation(in: app, anchor: app.buttons["Stop recording"], screen: "manual-recording")
        assertStats("12.5 fps / 42 ms", in: app)

        app.buttons["Stop recording"].tap()
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-frame-rate"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Manual"].isSelected)
        openSettings(app)
        XCTAssertEqual(statsToggle.value as? String, "1")
        tapSwitch(statsToggle)
        returnToCapture(app)
        app.segmentedControls.buttons["Auto"].tap()
        XCTAssertFalse(app.staticTexts["capture-model-stats"].exists)
        app.segmentedControls.buttons["Manual"].tap()
        app.buttons["Start recording"].tap()
        XCTAssertTrue(app.staticTexts["capture-status-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["capture-model-stats"].exists)
        attach(app, "manual-recording-clean")
    }

    func testDisabledDetectionDoesNotClaimToBeRunning() {
        let app = launch()
        openSettings(app)
        tapSwitch(app.switches["show-capture-model-stats"])
        tapSwitch(app.switches["Model swing detection"])
        XCTAssertEqual(app.switches["Model swing detection"].value as? String, "0")
        returnToCapture(app)
        let manual = app.segmentedControls.buttons["Manual"]
        waitUntilHittable(manual)
        manual.tap()
        XCTAssertTrue(manual.isSelected)
        app.buttons["Start recording"].tap()
        XCTAssertTrue(app.buttons["Stop recording"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["capture-status-title"].label, "Detection off")
        XCTAssertEqual(app.staticTexts["capture-status-detail"].label, "Recording video")
        XCTAssertFalse(app.staticTexts["capture-model-stats"].exists)
        attach(app, "manual-detection-disabled")
    }

    func testWaitingAndErrorsKeepCaptureStateHonest() {
        let waiting = launch(extra: ["-capture-controls-waiting", "-capture-controls-stats"])
        assertStats("Waiting for model…", in: waiting)
        waiting.terminate()
        let unavailable = launch(extra: ["-capture-controls-unavailable", "-capture-controls-stats"])
        XCTAssertTrue(unavailable.staticTexts["Detection unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(unavailable.staticTexts["capture-model-stats"].exists)
        attach(unavailable, "detector-unavailable")
        unavailable.terminate()
        let error = launch(extra: ["-capture-controls-error"])
        XCTAssertTrue(error.staticTexts["Auto needs attention"].waitForExistence(timeout: 5))
        XCTAssertEqual(error.staticTexts["capture-status-detail"].label, "Enable Photos add access in Settings before the range session.")
        XCTAssertTrue(error.buttons["capture-saved-swings"].isHittable)
        attach(error, "auto-save-error")
    }

    func testSavedReviewStillPlaysPagesAndDeletes() {
        let app = launch()
        let saved = app.buttons["capture-saved-swings"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.label, "Review 3 saved swings")
        saved.tap()
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(position.label, "3 of 3")
        let close = app.buttons["Close swing review"]
        XCTAssertTrue(close.exists)
        XCTAssertTrue(app.buttons["Delete this swing"].exists)
        let timeline = app.otherElements["playback-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        app.buttons["Play"].tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(timeline.value as? String ?? "") ?? 0) > 0.1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        app.buttons["Pause"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.43))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.43))
        start.press(forDuration: 0.05, thenDragTo: end)
        let paged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            position.label == "2 of 3"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paged], timeout: 5), .completed)
        attach(app, "auto-review-shared-player")
        app.buttons["Delete this swing"].tap()
        app.buttons["Delete from SwingCoach"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            position.label == "2 of 2"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [deleted], timeout: 5), .completed)
        close.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.label, "Review 2 saved swings")
        attach(app, "auto-count-after-delete")
    }

    func testPortraitPolicyAcrossTabsTrimAndReview() {
        let app = launch()
        let saved = app.buttons["capture-saved-swings"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        assertPortraitAfterRotation(in: app, anchor: saved, screen: "auto-capture")
        saved.tap()
        let close = app.buttons["Close swing review"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        assertPortraitAfterRotation(in: app, anchor: close, screen: "auto-review")
        close.tap()

        app.segmentedControls.buttons["Manual"].tap()
        let record = app.buttons["Start recording"]
        assertPortraitAfterRotation(in: app, anchor: record, screen: "manual-idle")
        record.tap()
        app.buttons["Stop recording"].tap()
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForExistence(timeout: 10))
        assertPortraitAfterRotation(in: app, anchor: app.buttons["Cancel"], screen: "trim")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))

        app.tabBars.buttons["Library"].tap()
        let reference = app.staticTexts["Reference swing 1"]
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        assertPortraitAfterRotation(in: app, anchor: reference, screen: "library")
        reference.tap()
        let back = app.buttons["Back to library"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        assertPortraitAfterRotation(in: app, anchor: back, screen: "library-player")
        back.tap()
        for tab in ["Coach", "Debug"] {
            let button = app.tabBars.buttons[tab]
            button.tap()
            assertPortraitAfterRotation(in: app, anchor: button, screen: tab.lowercased())
        }
    }

    private func assertPortraitAfterRotation(in app: XCUIApplication, anchor: XCUIElement, screen: String) {
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation: UIDeviceOrientation in [.landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            XCUIDevice.shared.orientation = orientation
            // Observe the whole transition. An immediate portrait read could
            // pass before an unwanted rotation animation has started.
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width >= app.frame.height
            }, object: nil)
            rotated.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 1.5), .completed, screen)
            XCTAssertTrue(anchor.isHittable, screen)
            XCTAssertTrue(app.frame.contains(anchor.frame), screen)
            attach(app, "\(screen)-device-\(orientation.rawValue)-ui-portrait")
        }
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-capture-controls-reset"] + extra
        app.launch()
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
        app.buttons["Experimental settings"].tap()
        XCTAssertTrue(app.switches["show-capture-model-stats"].waitForExistence(timeout: 5))
    }

    private func returnToCapture(_ app: XCUIApplication) {
        app.buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.navigationBars["Experiments"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)

        let capture = app.tabBars.buttons["Capture"]
        waitUntilHittable(capture)
        capture.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            capture.isSelected && app.segmentedControls["capture-mode"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        // SwiftUI exposes the entire row as a switch. Tap the trailing native
        // control; tapping the label's centre does not toggle it on iOS 26.
        let expected = toggle.value as? String == "1" ? "0" : "1"
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            toggle.value as? String == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func assertStats(_ expected: String, in app: XCUIApplication) {
        let stats = app.staticTexts["capture-model-stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        XCTAssertEqual(stats.label, expected)
        XCTAssertGreaterThan(stats.frame.minY, app.staticTexts["capture-status-detail"].frame.minY)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        // Capture the entire display. Application screenshots can crop the
        // landscape image using portrait bounds after a simulator rotation.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
