import XCTest

/// Save to Photos with the synthetic camera and real exports, Library and
/// PhotoKit. scripts/verify.sh storage revokes Photos access before the OFF test,
/// grants it before the ON test, and checks the app's files and the Simulator's
/// Photos rows after each.
final class SavePhotosUITests: XCTestCase {
    private let oneDetectedSwing = Fixture.syntheticCamera + ["-ui-testing-detections", "0"]
    private let autoExport = Fixture.syntheticCamera + ["-ui-testing-auto-export"]

    override func setUp() { continueAfterFailure = false }

    func testOffPersistsAndSavesManualTrimAndAutoLocally() {
        let app = XCUIApplication.launched(seed: "empty", Fixture.syntheticCamera)
        openSettings(app)
        let toggle = app.switches["save-to-photos"]
        XCTAssertEqual(toggle.value as? String, "1", "New installs retain existing ON behavior")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        attach("save-to-photos-off")
        app.relaunch(Fixture.syntheticCamera)
        openSettings(app)
        XCTAssertEqual(toggle.value as? String, "0", "Preference survives process relaunch")
        app.buttons["Done"].tap()
        saveManual(app, range: false)
        app.relaunch(oneDetectedSwing)
        saveManual(app, range: true)
        app.relaunch(autoExport)
        let review = app.buttons["capture-saved-swings"]
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Review 1 saved swings"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed)
        review.tap()
        assertPlayback(app)
        attach("auto-local-playback")
        app.buttons["Delete this swing"].tap()
        XCTAssertTrue(app.buttons["Delete from SwingCoach"].waitForExistence(timeout: 5))
        app.buttons["Delete from SwingCoach"].tap()
        XCTAssertTrue(app.staticTexts["No Session Swings"].waitForExistence(timeout: 10))
        app.buttons["Close swing review"].tap()
        app.relaunch(Fixture.syntheticCamera)
        app.tabBars.buttons["Library"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DTL")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let previewLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.progressIndicators.count == 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [previewLoaded], timeout: 10), .completed,
                       "Local preview must load at Library entry without opening the clip or granting Photos")
        attach("local-thumbnails-after-relaunch")
        card.tap()
        assertPlayback(app)
        attach("local-library-playback-after-relaunch")
    }

    func testOnCreatesPhotosCopiesForManualTrimAndAuto() {
        allowPhotosAccessWhenAsked()
        let app = XCUIApplication.launched(seed: "empty", Fixture.syntheticCamera)
        openSettings(app)
        XCTAssertEqual(app.switches["save-to-photos"].value as? String, "1", "New installs save to Photos")
        app.buttons["Done"].tap()
        saveManual(app, range: false)
        app.relaunch(oneDetectedSwing)
        saveManual(app, range: true)
        app.relaunch(autoExport)
        let review = app.buttons["capture-saved-swings"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Review 1 saved swings"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed)
        review.tap()
        assertPlayback(app)
        attach("auto-photos-playback")
    }

    /// The verify runner grants Photos access up front; this covers a plain
    /// `xcodebuild test` on a Simulator that has not been asked yet.
    private func allowPhotosAccessWhenAsked() {
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    private func openSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
        app.buttons["Experimental settings"].tap()
        XCTAssertTrue(app.switches["save-to-photos"].waitForExistence(timeout: 5))
    }

    private func saveManual(_ app: XCUIApplication, range: Bool) {
        app.tabBars.buttons["Capture"].tap()
        app.segmentedControls.buttons["Manual"].tap()
        app.buttons["Start recording"].tap()
        XCTAssertTrue(app.buttons["Stop recording"].waitForExistence(timeout: 5))
        app.buttons["Stop recording"].tap()
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForExistence(timeout: 10))
        let export = app.buttons[range ? "trim-export-only" : "Use Full Video"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        export.tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 30))
        attach(range ? "trim-range-saved" : "manual-full-saved")
    }

    private func assertPlayback(_ app: XCUIApplication) {
        let timeline = app.otherElements["playback-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        if app.buttons["Play"].exists { app.buttons["Play"].tap() }
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(timeline.value as? String ?? "") ?? 0) > 0.1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
        if app.buttons["Pause"].exists { app.buttons["Pause"].tap() }
    }

    private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
