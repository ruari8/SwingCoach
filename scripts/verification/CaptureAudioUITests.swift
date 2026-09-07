import XCTest

final class CaptureAudioUITests: XCTestCase {
    func testLaunchAndTabReentryLeaveAudioPolicyAndMicrophoneUntouched() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { break }
            alert.buttons.firstMatch.tap()
        }
        assertAudioUnchanged(app, start: 1)
        app.segmentedControls.buttons["Manual"].tap()
        for start in 2...3 {
            app.tabBars.buttons["Library"].tap()
            app.tabBars.buttons["Capture"].tap()
            assertAudioUnchanged(app, start: start)
        }
        app.segmentedControls.buttons["Auto"].tap()
        app.tabBars.buttons["Library"].tap()
        app.tabBars.buttons["Capture"].tap()
        assertAudioUnchanged(app, start: 4)
        app.terminate()
        app.launch()
        assertAudioUnchanged(app, start: 1)
    }

    private func assertAudioUnchanged(_ app: XCUIApplication, start: Int) {
        let value = app.staticTexts["capture-audio-verification"]
        let expected = "unchanged=true microphones=0 starts=\(start)"
        let predicate = NSPredicate(format: "label == %@", expected)
        expectation(for: predicate, evaluatedWith: value)
        waitForExpectations(timeout: 10)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "audio-policy-start-\(start)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
