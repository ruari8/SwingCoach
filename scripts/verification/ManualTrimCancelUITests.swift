import XCTest

final class ManualTrimCancelUITests: XCTestCase {
    func testCancelReturnsToManualAndAllowsAnotherRecording() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { break }
            alert.buttons.firstMatch.tap()
        }
        let manual = app.segmentedControls.buttons["Manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        for attempt in 1...2 {
            let record = app.buttons["Start recording"]
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            record.tap()
            let stop = app.buttons["Stop recording"]
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            stop.tap()
            XCTAssertTrue(app.staticTexts["Trim Swings"].waitForExistence(timeout: 10))
            attach(app, "trim-\(attempt)")
            app.buttons["Cancel"].tap()
            let returned = record.waitForExistence(timeout: 5)
            attach(app, "after-cancel-\(attempt)")
            XCTAssertTrue(returned, "Cancel must return to Manual capture, not the old recording player")
            XCTAssertTrue(manual.isSelected)
            XCTAssertTrue(record.isEnabled && record.isHittable)
            XCTAssertFalse(app.staticTexts["Trim Swings"].exists)
            XCTAssertFalse(app.buttons["Play"].exists)
        }
        app.tabBars.buttons["Library"].tap()
        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(manual.isSelected)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
