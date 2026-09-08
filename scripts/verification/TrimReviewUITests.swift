import XCTest

final class TrimReviewUITests: XCTestCase {
    func testManualTrimSelectionReviewExportOnlyThenSubsetAnalysis() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            guard springboard.alerts.firstMatch.waitForExistence(timeout: 1) else { break }
            springboard.alerts.firstMatch.buttons.firstMatch.tap()
        }
        let manual = app.segmentedControls.buttons["Manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        manual.tap()
        openTrim(app)
        XCTAssertFalse(app.buttons["trim-export-analyze"].isEnabled)
        app.buttons["trim-clip-3"].tap()
        let playhead = app.otherElements["trim-playhead"]
        XCTAssertTrue(playhead.waitForExistence(timeout: 5))
        attach("late-selection-before-assertion")
        XCTAssertTrue(playhead.isHittable, "Selection must scroll the late playhead into view")
        XCTAssertEqual(playhead.value as? String, "299.00")
        attach("late-selection")
        app.buttons["trim-review"].tap()
        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertEqual(position.label, "3 of 3")
        let review = app.otherElements["trim-full-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.buttons["Play"].waitForExistence(timeout: 10))
        XCTAssertTrue(review.buttons["Play"].isHittable, "Use the active review's fixed playback controls")
        attach("full-review-before-play")
        review.buttons["Play"].tap()
        XCTAssertTrue(review.buttons["Pause"].waitForExistence(timeout: 3))
        XCTAssertTrue(review.buttons["Pause"].isHittable)
        review.buttons["Pause"].tap()
        // The pager keeps neighbouring pages alive. Its fixed viewport is the
        // gesture target; the changing page label proves which clip settled.
        XCTAssertTrue(review.isHittable)
        let viewport = review.frame.intersection(app.frame)
        XCTAssertGreaterThan(viewport.width, app.frame.width * 0.8)
        XCTAssertGreaterThan(viewport.height, app.frame.height * 0.6)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.minX + viewport.width * 0.25,
                                              dy: viewport.midY))
        let end = origin.withOffset(CGVector(dx: viewport.minX + viewport.width * 0.75,
                                            dy: viewport.midY))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(NSPredicate(format: "label == %@", "2 of 3").evaluate(with: waitFor(position, label: "2 of 3")))
        let analyze = review.buttons["Analyze this swing"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        XCTAssertTrue(analyze.isHittable)
        analyze.tap()
        XCTAssertEqual(analyze.value as? String, "Selected")
        attach("full-review-subset")
        review.buttons["Close trim review"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trim-export-only"].isHittable)
        XCTAssertEqual(playhead.value as? String, "149.00")
        XCTAssertTrue(playhead.isHittable)
        XCTAssertEqual(app.buttons["Analyze swing 2"].value as? String, "Selected")
        // Even checked clips do not trigger analysis through Export only.
        app.buttons["trim-export-only"].tap()
        allowPhotosIfRequested(app)
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForNonExistence(timeout: 90))
        XCTAssertTrue(app.buttons["Start recording"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Capture"].isSelected)
        attach("export-only-returned-to-capture")
        app.terminate()
        app.launch()
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        manual.tap()
        openTrim(app)
        app.buttons["Analyze swing 2"].tap()
        XCTAssertEqual(app.buttons["trim-export-analyze"].label, "Export & Analyze 1")
        app.buttons["trim-export-analyze"].tap()
        allowPhotosIfRequested(app)
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForNonExistence(timeout: 90))
        let coach = app.tabBars.buttons["Coach"]
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: coach)
        waitForExpectations(timeout: 90)
        attach("subset-handed-to-coach")
    }

    private func allowPhotosIfRequested(_ app: XCUIApplication) {
        // Xcode can reinstall the app after the simctl pregrant. Accept the
        // actual runtime upgrade prompt too, instead of assuming TCC persisted.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [springboard, app] {
            let allow = host.buttons["Allow Full Access"]
            if allow.waitForExistence(timeout: 5), allow.isHittable {
                attach("photos-full-access-prompt")
                allow.tap()
                return
            }
        }
    }

    private func openTrim(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        app.buttons["Start recording"].tap()
        app.buttons["Stop recording"].tap()
        XCTAssertTrue(app.staticTexts["Trim Swings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trim-clip-3"].waitForExistence(timeout: 20))
    }

    private func waitFor(_ element: XCUIElement, label: String) -> XCUIElement {
        expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        waitForExpectations(timeout: 5)
        return element
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
