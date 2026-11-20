import XCTest

/// On-device coaching in the review player, the session review and on the
/// Auto camera screen, on the `coaching` seed: five DTL clips in one
/// session with stored reports, four of which steepen the shaft in
/// transition (drawn at P5, 1.85 s); hips are one step out at P7 (1.95 s)
/// and the head is in zone at P4 (1.6 s). With the synthetic camera, those
/// five are the Auto session.
final class SwingCoachingUITests: XCTestCase {
    func testSwingOpensOnItsPointerAndWalksThroughTheFindings() throws {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        let timeline = try XCTUnwrap(app.otherElements.matching(identifier: "playback-timeline")
            .allElementsBoundByIndex.first { $0.isHittable })
        let title = app.staticTexts["coaching-step-title"]
        let place = app.staticTexts["coaching-step-place"]
        let count = app.staticTexts["coaching-step-count"]
        let transitionCaption = app.descendants(matching: .any)["coaching-caption-transition"]
        let hipsCaption = app.descendants(matching: .any)["coaching-caption-hipDepthImpact"]

        // No tap: paused on the pointer's frame with its drawing up.
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Shaft steepened coming down")
        XCTAssertEqual(place.label, "Halfway down")
        XCTAssertEqual(count.label, "Finding 1 of 2")
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.85, accuracy: 0.01)
        XCTAssertTrue(app.buttons["swing-position-P5"].isSelected)
        XCTAssertTrue(app.buttons["swing-position-P5"].label.contains("out of zone, up to 5 steps out, the coach starts here"))
        XCTAssertTrue(transitionCaption.waitForExistence(timeout: 2), "The drawing carries its number")
        XCTAssertTrue(app.descendants(matching: .any)["coaching-step-level"].label.hasSuffix("steps out"))
        let legend = app.descendants(matching: .any)["coaching-legend"]
        XCTAssertFalse(legend.exists, "The drawing's key is in All checks, not on the card")
        XCTAssertFalse(app.buttons["Play"].exists, "On a step the card carries Play")
        attach(app, "coaching-step-1")

        // Next: the other fault, in swing order.
        app.buttons["coaching-next"].tap()
        XCTAssertTrue(hipsCaption.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Hips moved toward the ball")
        XCTAssertEqual(place.label, "At impact")
        XCTAssertEqual(count.label, "Finding 2 of 2")
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.95, accuracy: 0.01)
        XCTAssertFalse(transitionCaption.exists, "A drawing shows only on its own frame")
        XCTAssertFalse(app.buttons["coaching-next"].exists, "The last step offers Play instead")
        app.buttons["coaching-back"].tap()
        XCTAssertEqual(title.label, "Shaft steepened coming down")

        // Away from the walkthrough's frames nothing is drawn, and one line
        // brings the walkthrough back.
        app.buttons["swing-position-P1"].tap()
        XCTAssertFalse(transitionCaption.exists)
        XCTAssertFalse(hipsCaption.exists)
        let folded = app.buttons["swing-coaching-pill"]
        XCTAssertTrue(folded.waitForExistence(timeout: 2))
        XCTAssertEqual(folded.label, "Coaching: Shaft steepened coming down")
        XCTAssertTrue(app.buttons["Play"].exists, "Off the walkthrough the transport row is back")
        folded.tap()
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.85, accuracy: 0.01)

        // Every check, with its numbers; picking one shows it on its frame.
        app.buttons["coaching-all-checks"].firstMatch.tap()
        let summary = app.descendants(matching: .any)["coaching-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("1 of 3 judged checks in zone."), summary.label)
        XCTAssertTrue(legend.exists, "All checks keys the level badges")
        let head = app.buttons["coaching-metric-headHeightTop"]
        XCTAssertTrue(head.exists)
        XCTAssertTrue(head.label.contains("Good players: −6% to 0%"), head.label)
        attach(app, "coaching-every-check")
        head.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-headHeightTop"].waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Head height at the top: in zone")
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.6, accuracy: 0.01)
        app.buttons["coaching-back-to-steps"].tap()
        XCTAssertEqual(title.label, "Shaft steepened coming down")
    }

    func testDrawingsToolTurnsTheCoachsDrawingOffAndBack() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        let caption = app.descendants(matching: .any)["coaching-caption-transition"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))

        // On the walkthrough the tools start folded, one tap away.
        let fold = app.buttons["player-tools-fold"]
        XCTAssertEqual(fold.label, "Show player tools")
        XCTAssertFalse(app.buttons["player-tool-drawings"].exists)
        app.showPlayerTools()
        app.buttons["player-tool-drawings"].tap()
        let coach = app.switches["coaching-layer-coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["coaching-layer-club"].exists)
        coach.switches.firstMatch.tap()
        app.navigationBars["Layers"].buttons["Done"].tap()

        XCTAssertFalse(caption.waitForExistence(timeout: 1))
        let changed = app.descendants(matching: .any)["coaching-layers-custom"]
        XCTAssertTrue(changed.waitForExistence(timeout: 2), "The video says the drawings differ from the coach's")
        attach(app, "coaching-drawings-changed")
        app.buttons["coaching-layers-reset"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 2))
        XCTAssertFalse(changed.exists)
    }

    func testFirstReadingSaysWhatTheClipReadingChanged() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library", "-ui-testing-coaching-reads", "6"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        let title = app.staticTexts["coaching-step-title"]
        let note = app.descendants(matching: .any)["coaching-reading-note"]
        // Body checks only: no transition, so the swing reads as good.
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Good swing")
        XCTAssertTrue(note.label.contains("Body checks only. Adding the club checks now."), note.label)
        attach(app, "coaching-first-reading")

        // The clip's reading adds the club checks and moves to the new pointer.
        let updated = NSPredicate(format: "label CONTAINS %@", "On the body checks alone it was: Good swing")
        expectation(for: updated, evaluatedWith: note)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(title.label, "Shaft steepened coming down")
        attach(app, "coaching-clip-reading-replaced")
        app.buttons["coaching-next"].tap()
        XCTAssertFalse(note.exists, "The note goes once the golfer moves on")

        // The swing before it had no reading yet: it is read after this one.
        app.buttons["Back to library"].tap()
        app.openLibraryCard("10:06", sessionCard: true)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
    }

    func testFailedReadSaysSoAndOffersRetry() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library", "-ui-testing-coaching-reads", "fail"])
        app.openLibraryCard("10:06", sessionCard: true)
        let failed = app.descendants(matching: .any)["swing-coaching-failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Couldn't read this swing"].exists)
        XCTAssertTrue(app.buttons["coaching-retry"].exists)
        attach(app, "coaching-read-failed")
    }

    func testSwingThatIsNotJudgedSaysWhyAndDrawsNothing() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library", "-ui-testing-coaching-short"])
        app.openLibraryCard("10:00", sessionCard: true)
        let title = app.staticTexts["coaching-step-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Short swing, not judged")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "A chip or pitch.")).firstMatch.exists)
        XCTAssertFalse(app.buttons["coaching-next"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["coaching-caption-headHeightTop"].exists)
        XCTAssertFalse(app.buttons["swing-position-P5"].label.contains("out of zone"), "No levels on a swing that isn't judged")
        attach(app, "coaching-not-judged")
    }

    func testSessionReviewShowsTheThemeItsPicturesAndEachSwing() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Filter swings"].waitForExistence(timeout: 10))
        app.buttons["session-coaching-button"].firstMatch.tap()

        let theme = app.descendants(matching: .any)["session-theme-steepTransition-transition-1"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shaft steepened coming down"].firstMatch.exists)
        // One caption: how many swings, and the check the theme's level is read on.
        XCTAssertTrue(app.staticTexts["4 of 5 swings · transition"].exists)
        XCTAssertTrue(app.staticTexts["Start here"].exists)

        // A dot a swing, in the order hit. The fifth is the first with four
        // behind it, so it is the one that gets the session's theme.
        let third = app.buttons["session-swing-dot-3"]
        XCTAssertTrue(third.exists)
        XCTAssertEqual(third.label, "Swing 3: Good swing")
        XCTAssertEqual(app.buttons["session-swing-dot-5"].label, "Swing 5: Shaft steepened coming down")

        // The theme at its worst and at its best, as pictures.
        XCTAssertTrue(app.buttons["session-example-1"].waitForExistence(timeout: 5), "Shows it most")
        XCTAssertTrue(app.buttons["session-example-3"].exists, "Your best here")
        attach(app, "session-coaching")

        // The theme's metric swing by swing.
        let trend = app.descendants(matching: .any)["session-trend-transition"]
        for _ in 0..<4 where !(trend.exists && trend.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(trend.exists)
        XCTAssertTrue(trend.label.contains("1 of 5 swings in the green band"), trend.label)
        attach(app, "session-coaching-trend")

        // A dot opens its swing, on what went right.
        for _ in 0..<4 where !(third.exists && third.isHittable) {
            app.collectionViews.firstMatch.swipeDown(velocity: .slow)
        }
        third.tap()
        let title = app.staticTexts["coaching-step-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Good swing")
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-headHeightTop"].waitForExistence(timeout: 2),
                      "A good swing draws its checks in zone")
    }

    func testRecapOnTheCameraComparesTheLastSwingsAndOpensOne() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.launched(seed: "coaching", Fixture.syntheticCamera)
        let chip = app.buttons["coach-cadence"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Coach speaks: Every 5 swings")
        // The session's five measured swings arrive once the camera is
        // up: the recap comes up by itself, and there is no verdict per swing.
        let recap = app.descendants(matching: .any)["coach-recap"]
        XCTAssertTrue(recap.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coach-latest-verdict"].exists)

        // Closed, it can be asked for again.
        app.buttons["coach-recap-close"].tap()
        XCTAssertFalse(recap.waitForExistence(timeout: 1))
        chip.tap()
        app.buttons["Show recap now"].tap()
        XCTAssertTrue(recap.waitForExistence(timeout: 3))
        // The card is a glance: the finding and the picture, whose drawing
        // carries the level; no badge or word to disagree with it. The
        // count is in the comparison below.
        XCTAssertTrue(app.staticTexts["Shaft steepened coming down"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["coach-recap-level"].exists, "No level badge beside a picture")
        XCTAssertFalse(app.descendants(matching: .any)["coaching-camera-caveat"].exists, "The caveat is in the comparison")
        XCTAssertTrue(app.descendants(matching: .any)["coach-recap-picture"].exists, "The recap pictures the theme")
        attach(app, "capture-recap")

        // The count of swings that showed it is in the comparison, out of
        // the judged swings.
        app.buttons["coach-recap-open"].tap()
        let third = app.buttons["coach-compare-swing-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coach-compare-share"].label, "On 4 of 5 judged swings")
        XCTAssertTrue(app.buttons["coach-compare-swing-1"].exists)
        XCTAssertTrue(app.staticTexts["In zone"].exists, "The clean swing is in zone on the theme")
        attach(app, "capture-recap-compare")

        // A swing in the comparison opens on the check it pictured, and
        // Back returns to the comparison.
        third.tap()
        let title = app.staticTexts.matching(identifier: "coaching-step-title").allElementsBoundByIndex
            .first { $0.isHittable } ?? app.staticTexts["coaching-step-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Transition: in zone")
        XCTAssertEqual(app.staticTexts["swing-position"].label, "Swing 3 of 5")
        attach(app, "capture-compare-opens-at-check")
        app.buttons["Back to the comparison"].tap()
        XCTAssertTrue(third.waitForExistence(timeout: 3))
    }

    func testEverySwingSettingShowsTheLastVerdictOnTheCamera() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.launched(seed: "coaching", Fixture.syntheticCamera + ["-coaching.cadence", "everySwing"])
        let verdict = app.buttons["coach-latest-verdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        XCTAssertEqual(verdict.label, "Last swing: Shaft steepened coming down")
        XCTAssertEqual(app.buttons["coach-cadence"].label, "Coach speaks: Every swing")
        attach(app, "capture-latest-verdict")

        // Closing the recap brings the verdict back.
        app.buttons["coach-cadence"].tap()
        app.buttons["Show recap now"].tap()
        XCTAssertTrue(app.buttons["coach-recap-close"].waitForExistence(timeout: 3))
        XCTAssertFalse(verdict.exists)
        app.buttons["coach-recap-close"].tap()
        XCTAssertTrue(verdict.waitForExistence(timeout: 3))

        // It opens that swing on its pointer, drawn.
        verdict.tap()
        let title = app.staticTexts.matching(identifier: "coaching-step-title").allElementsBoundByIndex
            .first { $0.isHittable } ?? app.staticTexts["coaching-step-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Shaft steepened coming down")
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-transition"].firstMatch.waitForExistence(timeout: 2))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
