import XCTest

final class SavePhotosUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOffPersistsAndSavesManualTrimAndAutoLocally() {
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        let toggle = app.switches["save-to-photos"]
        XCTAssertEqual(toggle.value as? String, "1", "New installs retain existing ON behavior")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        attach("save-to-photos-off")
        app.terminate()
        app.launch()
        openSettings(app)
        XCTAssertEqual(toggle.value as? String, "0", "Preference survives process relaunch")
        app.buttons["Done"].tap()
        saveManual(app, range: false)
        app.terminate()
        app.launchArguments = ["-storage-range"]
        app.launch()
        saveManual(app, range: true)
        app.terminate()
        app.launchArguments = ["-storage-auto"]
        app.launch()
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
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Library"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DTL")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        assertPlayback(app)
        attach("local-library-playback-after-relaunch")
    }

    func testOnCreatesPhotosCopiesForManualTrimAndAuto() {
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        let toggle = app.switches["save-to-photos"]
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        saveManual(app, range: false)
        app.terminate()
        app.launchArguments = ["-storage-range"]
        app.launch()
        saveManual(app, range: true)
        app.terminate()
        app.launchArguments = ["-storage-auto"]
        app.launch()
        let review = app.buttons["capture-saved-swings"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Review 1 saved swings"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed)
        review.tap()
        assertPlayback(app)
        attach("auto-photos-playback")
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
        let export = app.buttons[range ? "Export & Analyze" : "Use Full Video"]
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
