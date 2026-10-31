import XCTest

/// P1-P10 quick navigation and the player's tool rail, on the `positions` seed:
/// one personal DTL clip and three references with positions (P8 unsure).
final class PlayerPositionsUITests: XCTestCase {
    func testPoseStripJumpsToPositionsAndCanBeHidden() throws {
        let app = XCUIApplication.launched(seed: "positions", ["-ui-testing-library"])
        app.openLibraryCard("Positions DTL", sessionCard: true)
        let strip = app.otherElements["swing-position-strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let timeline = try XCTUnwrap(app.otherElements.matching(identifier: "playback-timeline")
            .allElementsBoundByIndex.first { $0.isHittable })

        app.buttons["swing-position-P4"].tap()
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.6, accuracy: 0.01)
        XCTAssertTrue(app.buttons["swing-position-P4"].isSelected)
        XCTAssertTrue(app.buttons["swing-position-P8"].label.contains("unsure"))

        // Dragging across the strip moves a whole position per chip.
        let p5 = app.buttons["swing-position-P5"], p7 = app.buttons["swing-position-P7"]
        p5.press(forDuration: 0.05, thenDragTo: p7)
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.95, accuracy: 0.01)
        attach(app, "pose-strip-on-P7")

        app.buttons["Hide swing positions"].tap()
        XCTAssertFalse(strip.waitForExistence(timeout: 1))
        app.buttons["Show swing positions"].tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 2))
    }

    func testToolRailFoldsAndDocksOnTheChosenSide() throws {
        let app = XCUIApplication.launched(seed: "positions", ["-ui-testing-library"])
        app.openLibraryCard("Positions DTL", sessionCard: true)
        let fold = app.buttons["player-tools-fold"]
        let draw = app.buttons["Draw straight lines"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5))
        let star = app.buttons["Star swing"]
        XCTAssertEqual(fold.frame.midX, star.frame.midX, accuracy: 1)
        XCTAssertEqual(fold.frame.minY - star.frame.maxY, 10, accuracy: 1)
        assertToolOrder(app, ["player-tools-fold", "Show swing metadata", "Change playback speed",
                              "Draw straight lines", "Hide swing positions"])

        fold.tap()
        XCTAssertEqual(fold.label, "Show player tools")
        XCTAssertFalse(draw.waitForExistence(timeout: 1))
        fold.tap()
        XCTAssertTrue(draw.waitForExistence(timeout: 2))

        fold.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: fold.frame.midY / app.frame.height)))
        let back = app.buttons["Back to library"]
        let docked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(fold.frame.midX - back.frame.midX) < 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [docked], timeout: 2), .completed, "The rail must dock under Back")
        XCTAssertLessThan(draw.frame.midX, app.frame.midX)
        attach(app, "tool-rail-docked-left")

        // The side is the user's choice and is remembered, including in Auto review.
        app.relaunch(["-ui-testing-auto-review"])
        XCTAssertTrue(fold.waitForExistence(timeout: 5))
        XCTAssertLessThan(fold.frame.midX, app.frame.midX)
        XCTAssertTrue(app.otherElements["swing-position-strip"].exists)
        attach(app, "auto-review-docked-left")
    }

    private func assertToolOrder(_ app: XCUIApplication, _ identifiers: [String],
                                 file: StaticString = #filePath, line: UInt = #line) {
        let frames = identifiers.map { app.buttons[$0].frame }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(upper.midX, lower.midX, accuracy: 1, file: file, line: line)
            XCTAssertEqual(lower.minY - upper.maxY, 10, accuracy: 1, file: file, line: line)
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
