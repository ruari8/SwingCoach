import XCTest

/// scripts/verify.sh library also checks the files left on disk after this test.
final class LibraryDeletionUITests: XCTestCase {
    func testBulkDeletePersistsAndKeepsReferences() {
        let app = XCUIApplication.launched(seed: "review", ["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 8))
        app.buttons["Select"].tap()
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 3))
        app.buttons["Delete selected swings"].tap()
        let confirmation = app.alerts["Delete 3 Swings?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 3))
        assertReferencesRemain(in: app)
        app.relaunch(["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 8))
        assertReferencesRemain(in: app)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Library after bulk deletion and relaunch"
        proof.lifetime = .keepAlways
        add(proof)
    }

    private func assertReferencesRemain(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Reference swing 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(identifier: "swing-card").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Review A starred DTL"].exists)
        XCTAssertFalse(app.staticTexts["Review B Face-On"].exists)
        XCTAssertFalse(app.staticTexts["Review C DTL"].exists)
    }
}
