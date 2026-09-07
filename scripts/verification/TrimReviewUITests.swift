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
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["Pause"].tap()
        let page = app.otherElements.matching(identifier: "swing-review-page").allElementsBoundByIndex.first { $0.isHittable }!
        page.swipeRight()
        XCTAssertTrue(NSPredicate(format: "label == %@", "2 of 3").evaluate(with: waitFor(position, label: "2 of 3")))
        let analyze = app.buttons["Analyze this swing"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()
        XCTAssertEqual(analyze.value as? String, "Selected")
        attach("full-review-subset")
        app.buttons["Close trim review"].tap()
        XCTAssertTrue(app.buttons["trim-export-only"].waitForExistence(timeout: 5))
        XCTAssertEqual(playhead.value as? String, "149.00")
        XCTAssertTrue(playhead.isHittable)
        XCTAssertEqual(app.buttons["Analyze swing 2"].value as? String, "Selected")
        // Even checked clips do not trigger analysis through Export only.
        app.buttons["trim-export-only"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 90))
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
        let coach = app.tabBars.buttons["Coach"]
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: coach)
        waitForExpectations(timeout: 90)
        attach("subset-handed-to-coach")
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
