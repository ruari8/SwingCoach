import XCTest

/// Feeds recorded range footage through Auto in place of the camera, with Keep
/// Auto recordings on, and checks that each labelled swing is saved. Run it with
/// `scripts/verify.sh footage`, which copies the footage into the app, passes
/// its labels in TEST_RUNNER_FOOTAGE_* variables, and checks the diagnostics log
/// and kept recordings afterwards.
final class FootageCameraUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAutoSavesEachLabelledSwingFromFootage() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let file = environment["FOOTAGE_FILE"], let expectedText = environment["FOOTAGE_EXPECTED"],
              let expected = Int(expectedText) else {
            throw XCTSkip("Run through scripts/verify.sh footage, which supplies the footage and labels.")
        }
        let footageSeconds = Double(environment["FOOTAGE_SECONDS"] ?? "") ?? 120

        let app = XCUIApplication()
        app.launchArguments = [
            "-footage-camera", file,
            "-footage-camera-time-scale", environment["FOOTAGE_TIME_SCALE"] ?? "1",
            "-footage-camera-impacts", environment["FOOTAGE_IMPACTS"] ?? "",
            "-experimental.keepAutoRecordings", "YES",
            // Real time with drops, as on a phone, so the run lasts as long as the footage.
            "-footage-camera-every-frame", "NO",
        ]
        app.launch()

        let status = app.staticTexts["footage-camera-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "Capture did not show the footage camera")
        XCTAssertFalse(status.label.contains("Footage camera:"), "Footage camera failed: \(status.label)")
        XCTAssertEqual(app.staticTexts["capture-status-title"].label, "Auto is on")

        let finished = NSPredicate(format: "label BEGINSWITH %@", "Footage finished")
        expectation(for: finished, evaluatedWith: status)
        waitForExpectations(timeout: footageSeconds + 60)
        let footage = XCTAttachment(string: status.label)
        footage.name = "footage-status"
        footage.lifetime = .keepAlways
        add(footage)

        // The last swing's clip finishes after the footage does.
        let saved = app.buttons["capture-saved-swings"]
        let allSaved = NSPredicate(format: "label == %@", "Review \(expected) saved swings")
        expectation(for: allSaved, evaluatedWith: saved)
        waitForExpectations(timeout: 60)
        XCTAssertEqual(app.staticTexts["capture-status-detail"].label, "Swings save automatically",
                       "Auto reported an error or is still saving")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "footage-finished"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Leaving Capture stops Auto, which keeps the recordings still inside
        // the rolling window. Give the chunk being written time to finish;
        // the runner then checks the kept files cover the footage.
        app.tabBars.buttons["Library"].tap()
        let settle = XCTestExpectation(description: "kept recordings finish")
        settle.isInverted = true
        wait(for: [settle], timeout: 3)
    }
}
