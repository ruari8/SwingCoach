import XCTest

/// Uses the disposable local backend and seeded clips from verify-coaching.sh.
final class CoachingPipelineUITests: XCTestCase {
    func testRealUploadAnalysisAndSourceNotesPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-library", "-experimental.backendTarget", "custom",
                               "-experimental.customBackendURL", "http://127.0.0.1:8871",
                               "-experimental.useMockAnalysis", "NO"]
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        app.buttons["coaching-context"].tap()
        let goal = app.textFields["practice-goal"].exists ? app.textFields["practice-goal"] : app.textViews["practice-goal"]
        goal.tap()
        goal.typeText("Improve contact")
        app.textFields["practice-club"].tap()
        app.textFields["practice-club"].typeText("7 iron")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Coaching upload fixture"].waitForExistence(timeout: 10))
        app.staticTexts["Coaching upload fixture"].tap()
        XCTAssertTrue(app.buttons["Analyze Swing"].waitForExistence(timeout: 5))
        app.buttons["Analyze Swing"].tap()
        XCTAssertTrue(app.buttons["Coach notes"].waitForExistence(timeout: 150), "Real local analysis should finish")
        app.buttons["Annotated video"].tap()
        XCTAssertTrue(app.buttons["Toggle Body Reference"].waitForExistence(timeout: 20))
        attach("Generated reference overlays")
        app.buttons["Coach notes"].tap()
        XCTAssertTrue(app.staticTexts["Head horizontal range"].waitForExistence(timeout: 10))
        scrollTo(app.staticTexts["coaching-status"], in: app)
        XCTAssertTrue(app.staticTexts["coaching-status"].label.contains("Coach unavailable"))
        attach("Measured evidence and unavailable coach")
        app.terminate()
        app.launch()
        app.staticTexts["Coaching upload fixture"].tap()
        app.buttons["Coach notes"].tap()
        XCTAssertTrue(app.staticTexts["Head horizontal range"].waitForExistence(timeout: 10))
        // The second saved result is an explicit contract fixture for the sourced
        // recommendation UI, not a live AI diagnosis of the uploaded video.
        app.terminate()
        app.launch()
        app.staticTexts["Coaching source fixture"].tap()
        app.buttons["Coach notes"].tap()
        scrollTo(app.staticTexts["Your cue"], in: app)
        XCTAssertTrue(app.staticTexts["Your cue"].exists)
        scrollTo(app.buttons["Coaching source and moments"], in: app)
        app.buttons["Coaching source and moments"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Teagan Moore / teaganmooregolf · 2:03–2:26")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        attach("Source-linked cue and reassessment")
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
