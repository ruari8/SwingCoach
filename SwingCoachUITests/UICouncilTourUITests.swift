import XCTest

/// The UI council's screenshot tour (ui-council/capture.sh), on request only.
/// It expects a coached range session already copied into the app container,
/// so it never seeds; it only walks the key screens in the Simulator's current appearance and
/// writes one PNG per screen to `UI_COUNCIL_OUT` (passed as
/// `TEST_RUNNER_UI_COUNCIL_OUT`). Steps are soft: a control that an older
/// build lacks is skipped and the screen is still captured, so the same tour
/// runs on the baseline commits.
final class UICouncilTourUITests: XCTestCase {
    private var out: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["UI_COUNCIL_OUT"], "Set TEST_RUNNER_UI_COUNCIL_OUT")
        out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
    }

    func testTour() {
        // capture.sh sets the Simulator's appearance before each pass. Setting
        // XCUIDevice.appearance here left the Simulator stuck in light.
        let look = ProcessInfo.processInfo.environment["UI_COUNCIL_APPEARANCE"] ?? "light"
        libraryScreens(look)
        playerScreens(look)
        captureScreens(look)
    }

    // MARK: Library, Settings, session review

    private func libraryScreens(_ look: String) {
        let app = launch(["-ui-testing-library"])
        _ = app.buttons["Filter swings"].waitForExistence(timeout: 15)
        grantPhotosAccess(app)
        settle(1.5)
        shot("01-library", look)

        if tap(app.buttons["Settings"]) {
            settle(1)
            shot("02-settings", look)
            if !tap(app.navigationBars.buttons["Done"]) { app.swipeDown(velocity: .fast) }
            settle(0.8)
        }

        if tap(app.buttons["session-coaching-button"].firstMatch) {
            _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'session-theme-'"))
                .firstMatch.waitForExistence(timeout: 20)
            settle(2)
            shot("03-session-review", look)
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            settle(1)
            shot("04-session-review-scrolled", look)
        }
        app.terminate()
    }

    // MARK: The review player

    private func playerScreens(_ look: String) {
        let app = launch(["-ui-testing-library"])
        _ = app.buttons["Filter swings"].waitForExistence(timeout: 15)
        let card = app.buttons.matching(identifier: "swing-card").firstMatch
        guard card.waitForExistence(timeout: 10) else { return app.terminate() }
        card.tap()
        _ = app.staticTexts["coaching-step-title"].waitForExistence(timeout: 15)
            || app.buttons["swing-coaching-pill"].waitForExistence(timeout: 5)
        settle(2.5)
        shot("05-player-open", look)

        if tap(app.buttons["coaching-next"]) {
            settle(1.5)
            shot("06-player-next-step", look)
        }

        if tap(app.buttons["coaching-all-checks"].firstMatch) || tapPillTwice(app) {
            settle(1.5)
            shot("07-all-checks", look)
            dismissSheet(app)
        }

        if tap(app.buttons["player-tool-drawings"]) {
            settle(1.2)
            shot("08-drawings-tool", look)
            dismissSheet(app)
        }

        if tap(app.buttons["player-tool-info"]) {
            settle(1.2)
            shot("09-swing-info", look)
            dismissSheet(app)
        }

        if tap(app.buttons["swing-position-P1"]) {
            settle(1.5)
            shot("10-player-address-P1", look)
        }
        app.terminate()
    }

    // MARK: Capture: Auto with the coach, then Manual

    private func captureScreens(_ look: String) {
        let app = launch(["-ui-testing-camera", "synthetic", "-ui-testing-auto-library"])
        let recap = app.descendants(matching: .any)["coach-recap"]
        if recap.waitForExistence(timeout: 15) {
            settle(1.5)
            shot("11-auto-recap", look)
            if tap(app.buttons["coach-recap-open"]) {
                settle(2)
                shot("12-auto-compare", look)
                // Swing 2: the first of the five that is judged (swing 1 is a chip).
                if tap(app.buttons["coach-compare-swing-2"]) {
                    _ = app.staticTexts.matching(identifier: "coaching-step-title").firstMatch.waitForExistence(timeout: 10)
                    settle(2)
                    shot("13-auto-review", look)
                    _ = tap(app.buttons["Back to the comparison"])
                    settle(1)
                }
                _ = tap(app.buttons["Done"].firstMatch, timeout: 2)
                settle(1)
            }
            _ = tap(app.buttons["coach-recap-close"], timeout: 2)
        }
        settle(1.5)
        shot("14-auto-camera", look)

        if tap(app.buttons["coach-cadence"]) {
            settle(1)
            shot("15-auto-coach-menu", look)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
            settle(0.8)
        }

        if tap(app.segmentedControls.buttons["Manual"]) {
            settle(1.5)
            shot("16-capture-manual", look)
        }
        app.terminate()
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Fixed coach cadence and no first-run hints, so every round matches.
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @discardableResult
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// Older builds open the measurement list from the verdict pill's second tap.
    private func tapPillTwice(_ app: XCUIApplication) -> Bool {
        let pill = app.buttons["swing-coaching-pill"]
        guard tap(pill, timeout: 2) else { return false }
        settle(0.8)
        return tap(pill, timeout: 2)
    }

    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Done", "Close"] where tap(app.buttons[label].firstMatch, timeout: 1) {
            settle(0.8)
            return
        }
        app.swipeDown(velocity: .fast)
        settle(0.8)
    }

    /// The test runner's reinstall resets the Photos grant, so answer the
    /// prompt the way a golfer would; the grant then holds for the run.
    private func grantPhotosAccess(_ app: XCUIApplication) {
        guard tap(app.buttons["Allow"].firstMatch, timeout: 2) else { return }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"]
        where tap(springboard.buttons[label].firstMatch, timeout: 3) {
            break
        }
        settle(1)
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String, _ look: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let file = out.appendingPathComponent("\(name)-\(look).png")
        XCTAssertNoThrow(try png.write(to: file))
    }
}
