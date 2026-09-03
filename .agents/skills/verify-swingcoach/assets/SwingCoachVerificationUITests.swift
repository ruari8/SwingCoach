import XCTest

final class SwingCoachVerificationUITests: XCTestCase {
    func testLibraryReferencePagingFromTab() throws {
        let app = XCUIApplication()
        app.launch()
        dismissFirstLaunchPromptsIfNeeded()

        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "Library tab did not appear")
        libraryTab.tap()

        let firstReference = app.staticTexts["Reference swing 1"]
        XCTAssertTrue(firstReference.waitForExistence(timeout: 8), "Local reference swing did not appear")
        attach(app.screenshot(), named: "01-library-reference-list")
        firstReference.tap()

        let position = app.staticTexts["swing-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), "Swing position did not appear")
        let initialPosition = position.label
        attach(app.screenshot(), named: "02-before-page-swipe-\(initialPosition)")

        let reviewPage = app.otherElements.matching(identifier: "swing-review-page").firstMatch
        XCTAssertTrue(reviewPage.waitForExistence(timeout: 5), "Swing review page did not appear")
        let start = reviewPage.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        let end = reviewPage.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialPosition),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 2), .completed)
        XCTAssertNotEqual(position.label, initialPosition)
        attach(app.screenshot(), named: "03-after-page-swipe-\(position.label)")
    }

    private func dismissFirstLaunchPromptsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let preferredButtons = ["Allow", "Allow Full Access", "Continue", "OK", "Don’t Allow"]

        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1.5) else { return }

            var handled = false
            for title in preferredButtons {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    handled = true
                    break
                }
            }

            if !handled {
                let fallback = alert.buttons.firstMatch
                guard fallback.exists else { return }
                fallback.tap()
            }
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
