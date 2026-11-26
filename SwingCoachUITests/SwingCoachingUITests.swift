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
        XCTAssertTrue(legend.exists, "All checks keys the rows' tracks")
        let head = app.buttons["coaching-metric-headHeightTop"]
        XCTAssertTrue(head.exists)
        XCTAssertTrue(head.label.contains("Good zone: −6% to 0%"), head.label)
        attach(app, "coaching-every-check")
        head.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-headHeightTop"].waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Head height at the top: in zone")
        XCTAssertEqual(Double(timeline.value as? String ?? "") ?? 0, 1.6, accuracy: 0.01)
        app.buttons["coaching-back-to-steps"].tap()
        XCTAssertEqual(title.label, "Shaft steepened coming down")
    }

    /// The drawing sits on the video: paused on the first step, the mark
    /// at the end of the swing's own shaft line (0.33 across, 0.15 down the
    /// fixture's 360 x 640 clip) is where that point of the picture is on
    /// screen, wherever the video layer has been anchored or lifted to.
    func testDrawingSitsOnTheVideo() throws {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        XCTAssertTrue(app.staticTexts["coaching-step-title"].waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        func onScreen(_ identifier: String) -> XCUIElement? {
            app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
                .first { screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame.minX > -1 }
        }
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-transition"].firstMatch.waitForExistence(timeout: 3))

        // The video and the card settle after the swing opens: wait for the
        // drawing to stop moving.
        var mark = CGRect.null, layer = CGRect.null
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let caption = onScreen("coaching-caption-transition"), let video = onScreen("player-video-layer")
            else { return false }
            let still = caption.frame == mark && video.frame == layer
            (mark, layer) = (caption.frame, video.frame)
            return still
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed, "The player never settled")

        // The video layer is the size of the whole screen, behind the
        // status bar, moved up by its anchor and lift. The probe's frame
        // comes back trimmed by that move at both ends, so its centre is
        // the layer's; the clip is aspect-fit about that centre.
        XCTAssertEqual(layer.width, screen.width, accuracy: 1, "\(layer)")
        XCTAssertLessThan(layer.midY, screen.midY, "A portrait clip sits above the screen's middle: \(layer)")
        let aspect: CGFloat = 360.0 / 640.0
        let videoHeight = min(screen.height, screen.width / aspect), videoWidth = videoHeight * aspect
        let video = CGRect(x: layer.midX - videoWidth / 2, y: layer.midY - videoHeight / 2,
                           width: videoWidth, height: videoHeight)
        XCTAssertEqual(mark.midX, video.minX + 0.33 * video.width, accuracy: 3, "\(mark) on \(video)")
        XCTAssertEqual(mark.midY, video.minY + 0.15 * video.height, accuracy: 3, "\(mark) on \(video)")
        // A portrait clip's top is at or above the safe area's top, never
        // centred lower with black above it.
        XCTAssertLessThanOrEqual(video.minY, app.buttons["review-leading"].frame.minY)
        attach(app, "coaching-drawing-on-video")
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

    /// From a camera above hand height the club check is drawn and listed
    /// with its numbers, but never the pointer, a strip mark or a theme,
    /// and the app says why.
    func testClubChecksAreNotJudgedFromACameraThatIsTooHigh() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library", "-ui-testing-coaching-camera-high"])
        app.openLibraryCard("Coaching DTL", sessionCard: true)
        let title = app.staticTexts["coaching-step-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // The steep transition is held, and hips one step out is no pointer.
        XCTAssertEqual(title.label, "Good swing")
        XCTAssertFalse(app.buttons["swing-position-P5"].label.contains("out of zone"), "No level on a held club check")
        XCTAssertFalse(app.descendants(matching: .any)["coaching-caption-transition"].exists)

        app.buttons["coaching-all-checks"].firstMatch.tap()
        let summary = app.descendants(matching: .any)["coaching-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("1 of 2 judged checks in zone."), summary.label)
        XCTAssertTrue(summary.label.contains("Club checks not judged · camera too high."), summary.label)
        let transition = app.buttons["coaching-metric-transition"]
        XCTAssertTrue(transition.exists, "Still listed, with its numbers")
        XCTAssertTrue(transition.label.contains("Not judged · camera too high"), transition.label)
        XCTAssertTrue(transition.label.contains("Lower the camera to hand height."), transition.label)
        XCTAssertFalse(transition.label.contains("Shaft steepened"), transition.label)
        XCTAssertEqual(transition.value as? String, "Not judged")
        XCTAssertFalse(app.buttons["coaching-metric-headHeightTop"].label.contains("camera"), "Body checks are judged as before")
        attach(app, "coaching-camera-held")

        // Picked, it is drawn on its frame, named and not judged.
        transition.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coaching-caption-transition"].waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Transition")
        XCTAssertEqual(app.descendants(matching: .any)["coaching-step-level"].label, "Not judged")
        attach(app, "coaching-camera-held-drawn")
    }

    func testSessionReviewSaysWhenClubChecksWereHeldForTheCamera() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library", "-ui-testing-coaching-camera-high"])
        XCTAssertTrue(app.buttons["Filter swings"].waitForExistence(timeout: 10))
        app.buttons["session-coaching-button"].firstMatch.tap()
        let camera = app.staticTexts["session-coaching-camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        XCTAssertEqual(camera.label, "Club checks not judged on any swing · camera too high")
        XCTAssertFalse(app.descendants(matching: .any)["session-theme-steepTransition-transition-1"].exists,
                       "A held club check is never a theme")
        XCTAssertEqual(app.buttons["session-swing-dot-5"].label, "Swing 5: Good swing")
        attach(app, "session-coaching-camera-held")
    }

    func testSessionReviewShowsTheThemeItsPicturesAndEachSwing() {
        let app = XCUIApplication.launched(seed: "coaching", ["-ui-testing-library"])
        XCTAssertTrue(app.buttons["Filter swings"].waitForExistence(timeout: 10))
        app.buttons["session-coaching-button"].firstMatch.tap()

        let theme = app.descendants(matching: .any)["session-theme-steepTransition-transition-1"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shaft steepened coming down"].firstMatch.exists)
        // One caption: how many swings, and the check the theme's level is read on.
        XCTAssertTrue(app.staticTexts["4 of 5 measured · transition"].exists)
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
        XCTAssertTrue(trend.label.contains("1 of 5 swings in the good zone"), trend.label)
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
        XCTAssertEqual(chip.label, "Recap: Every 5 swings")
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
        XCTAssertEqual(app.buttons["coach-cadence"].label, "Recap: Every swing")
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
