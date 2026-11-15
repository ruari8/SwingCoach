import XCTest
@testable import SwingCoach

/// Builds down-the-line evidence in "height units" (x already multiplied by
/// the aspect ratio), so the numbers in the tests read as distances.
private struct SyntheticSwing {
    static let aspect = 1080.0 / 1920.0
    /// Trail shoulder (0.25, 0.34) to hip (0.20, 0.50) plus hip to ankle (0.20, 0.80).
    static let bodyScale = (0.05 * 0.05 + 0.16 * 0.16).squareRoot() + 0.30

    var mirrored = false

    func point(_ x: Double, _ y: Double, confidence: Double = 0.9) -> CoachingPoint {
        let normalized = x / Self.aspect
        return CoachingPoint(x: mirrored ? 1 - normalized : normalized, y: y, confidence: confidence)
    }

    func box(from a: (Double, Double), to b: (Double, Double), confidence: Double = 0.9) -> CoachingBox {
        let first = point(a.0, a.1), second = point(b.0, b.1)
        return CoachingBox(x: min(first.x, second.x), y: min(first.y, second.y),
                           width: abs(first.x - second.x), height: abs(first.y - second.y), confidence: confidence)
    }

    func spot(_ x: Double, _ y: Double, confidence: Double = 0.9) -> CoachingBox {
        box(from: (x - 0.005, y - 0.005), to: (x + 0.005, y + 0.005), confidence: confidence)
    }

    /// Lead is the golfer's left for a right-hander, who faces frame right.
    private func name(_ joint: CoachingJoint) -> String {
        guard mirrored else { return joint.rawValue }
        let swapped = joint.rawValue.hasPrefix("left")
            ? "right" + joint.rawValue.dropFirst(4)
            : joint.rawValue.hasPrefix("right") ? "left" + joint.rawValue.dropFirst(5) : joint.rawValue
        return String(swapped)
    }

    func silhouette(back: Double, front: Double = 0.36) -> CoachingSilhouette {
        let rows = 160
        var left = [Double](repeating: -1, count: rows), right = left
        for row in 0..<rows {
            let y = (Double(row) + 0.5) / Double(rows)
            guard y > 0.2, y < 0.85 else { continue }
            let a = point(back, y).x, b = point(front, y).x
            left[row] = min(a, b)
            right[row] = max(a, b)
        }
        return CoachingSilhouette(left: left, right: right)
    }

    /// A frame with the body at address, optionally shifted.
    func frame(
        _ position: Int,
        clipTime: Double = 0,
        back: Double = 0.15,
        headLift: Double = 0,
        grip: (Double, Double) = (0.30, 0.52),
        head: (Double, Double)? = (0.42, 0.80),
        wristConfidence: Double = 0.9,
        ball: Bool = true
    ) -> CoachingFrameEvidence {
        var frame = CoachingFrameEvidence(position: position, clipTime: clipTime)
        frame.joints = [
            name(.leftHip): point(0.20, 0.50), name(.rightHip): point(0.20, 0.50), name(.root): point(0.20, 0.50),
            name(.neck): point(0.26, 0.34),
            name(.rightShoulder): point(0.25, 0.34), name(.leftShoulder): point(0.27, 0.35),
            name(.rightAnkle): point(0.20, 0.80), name(.leftAnkle): point(0.21, 0.80),
            name(.rightElbow): point(0.27, 0.44), name(.leftElbow): point(0.28, 0.44),
            name(.rightWrist): point(grip.0, grip.1, confidence: wristConfidence),
            name(.leftWrist): point(grip.0, grip.1, confidence: wristConfidence),
            name(.nose): point(0.29, 0.30 - headLift),
        ]
        frame.silhouette = silhouette(back: back)
        if let head {
            frame.shafts = [box(from: grip, to: head)]
            frame.clubheads = [spot(head.0, head.1)]
        }
        if ball { frame.balls = [spot(0.44, 0.80)] }
        return frame
    }

    func evidence(_ frames: [CoachingFrameEvidence], track: [CoachingFrameEvidence] = []) -> SwingCoachingEvidence {
        SwingCoachingEvidence(frameWidth: 1080, frameHeight: 1920, timeScale: 8, frames: frames, track: track)
    }
}

final class SwingCoachingTests: XCTestCase {
    private func result(_ id: CoachingMetricID, level: Int, confidence: Double = 0.9) -> CoachingMetricResult {
        let definition = CoachingMetricDefinition.definition(id)
        return CoachingMetricResult(id: id, position: definition.position, clipTime: 0, value: 0, level: level,
                                    confidence: confidence, drawings: [])
    }

    private func report(_ results: [CoachingMetricResult]) -> SwingCoachingReport {
        SwingCoachingReport(rightHanded: true, metrics: results, unavailable: [])
    }

    // MARK: - Levels

    func testLevelIsZeroInZoneAndCountsStepsOutsideIt() {
        let metric = CoachingMetricDefinition(id: .planeDelivery, title: "", position: 6, unit: .bodyPercent,
                                              zone: -5...5, step: 4, below: "under", above: "over", measures: "", weight: 1)
        XCTAssertEqual(metric.level(for: 5), 0)
        XCTAssertEqual(metric.level(for: -5), 0)
        XCTAssertEqual(metric.level(for: 5.1), 1)
        XCTAssertEqual(metric.level(for: 13.1), 3)
        XCTAssertEqual(metric.level(for: -9.5), -2)
        XCTAssertEqual(metric.level(for: 500), 10)
        XCTAssertEqual(metric.finding(forLevel: 2), "over")
        XCTAssertEqual(metric.finding(forLevel: -2), "under")
        XCTAssertNil(metric.finding(forLevel: 0))
    }

    func testEveryMetricHasOneDefinition() {
        XCTAssertEqual(Set(CoachingMetricDefinition.all.map(\.id)), Set(CoachingMetricID.allCases))
        XCTAssertEqual(CoachingMetricDefinition.all.count, CoachingMetricID.allCases.count)
    }

    // MARK: - Measurements

    private func swing(mirrored: Bool) -> SwingCoachingEvidence {
        let golfer = SyntheticSwing(mirrored: mirrored)
        let scale = SyntheticSwing.bodyScale
        return golfer.evidence([
            golfer.frame(1, wristConfidence: 0.1),
            // Halfway back the shaft rises at 45 degrees; halfway down at 58.
            golfer.frame(3, grip: (0.22, 0.40), head: (0.10, 0.28)),
            golfer.frame(5, grip: (0.22, 0.40), head: (0.14, 0.40 - 0.08 * tan(58 * Double.pi / 180))),
            // At impact the backside is 5% of body scale nearer the ball and
            // the head 4.5% higher.
            golfer.frame(7, back: 0.15 + 0.05 * scale, headLift: 0.045 * scale, wristConfidence: 0.1, ball: false),
        ])
    }

    func testMeasuresHipDepthHeadAndTransitionAgainstAddress() throws {
        let report = try XCTUnwrap(CoachingAnalyzer.analyze(swing(mirrored: false)))
        XCTAssertTrue(report.rightHanded)

        let hips = try XCTUnwrap(report.metric(.hipDepthImpact))
        // 2 past the zone's 3, in steps of 1.5.
        XCTAssertEqual(hips.value, 5, accuracy: 0.3)
        XCTAssertEqual(hips.level, 2)
        // Address line, the zone good players stay in, and where it is now.
        XCTAssertEqual(hips.drawings.map(\.kind), [.area, .line, .line, .dot])
        XCTAssertEqual(hips.drawings.first?.role, .zone)
        XCTAssertEqual(hips.finding, "Hips moved toward the ball")

        let head = try XCTUnwrap(report.metric(.headHeightImpact))
        // Good players lower the head 3 to 12%; 4.5 higher is 7.5 past that.
        XCTAssertEqual(head.value, 4.5, accuracy: 0.1)
        XCTAssertEqual(head.level, 4)
        // Head depth carries the same picture, so it draws when it leads.
        XCTAssertEqual(report.metric(.headDepthImpact)?.drawings, head.drawings)
        XCTAssertEqual(head.finding, "Head stays up through impact")

        let transition = try XCTUnwrap(report.metric(.transition))
        // 13 degrees steeper is 7 outside the zone's 6: three steps of 3.
        XCTAssertEqual(transition.value, 13, accuracy: 0.2)
        XCTAssertEqual(transition.level, 3)
        XCTAssertEqual(transition.finding, "Shaft steepens coming down")
        XCTAssertFalse(transition.drawings.isEmpty)

        // The 45 degree shaft, carried on from the grip (0.22, 0.40) down to
        // the ball's height (0.80), lands at x 0.62: 0.18 past the ball at 0.44.
        let back = try XCTUnwrap(report.metric(.shaftHalfwayBack))
        XCTAssertEqual(back.value, 0.18 / SyntheticSwing.bodyScale * 100, accuracy: 0.5)

        // No frame for the top, so top metrics are reported as unmeasured.
        XCTAssertTrue(report.unavailable.contains(.leadArmTop))
        XCTAssertNil(report.metric(.leadArmTop))
    }

    func testLeftHanderMirrorsToTheSameNumbers() throws {
        let right = try XCTUnwrap(CoachingAnalyzer.analyze(swing(mirrored: false)))
        let left = try XCTUnwrap(CoachingAnalyzer.analyze(swing(mirrored: true)))
        XCTAssertFalse(left.rightHanded)
        for id in [CoachingMetricID.hipDepthImpact, .headHeightImpact, .transition, .shaftHalfwayBack, .setupPosture] {
            let a = try XCTUnwrap(right.metric(id)), b = try XCTUnwrap(left.metric(id))
            XCTAssertEqual(a.value, b.value, accuracy: 0.3, id.rawValue)
            XCTAssertEqual(a.level, b.level, id.rawValue)
        }
    }

    func testNoReportWithoutTheGolferAtAddress() {
        let golfer = SyntheticSwing()
        var address = golfer.frame(1)
        address.joints = [:]
        XCTAssertNil(CoachingAnalyzer.analyze(golfer.evidence([address])))
    }

    func testClubheadSeenInTheSamePlaceEveryFrameIsIgnored() throws {
        let golfer = SyntheticSwing()
        var frames = [golfer.frame(1, wristConfidence: 0.1)]
        // A bag in the corner, detected with more confidence than the club.
        let bag = golfer.spot(0.50, 0.90, confidence: 0.99)
        for position in 2...7 {
            frames.append(golfer.frame(position, grip: (0.22, 0.40), head: (0.10, 0.28)))
        }
        for index in frames.indices { frames[index].clubheads.insert(bag, at: 0) }
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: golfer.evidence(frames)))
        let shaft = try XCTUnwrap(geometry.shaft(at: 3))
        XCTAssertEqual(shaft.head.x, 0.10, accuracy: 0.01)
        XCTAssertEqual(shaft.head.y, 0.28, accuracy: 0.01)
    }

    // MARK: - Club timing

    func testTimesTakeawayDeliveryAndImpactOffTheClubTrack() throws {
        let golfer = SyntheticSwing()
        func sample(_ time: Double, headY: Double, ball: Bool) -> CoachingFrameEvidence {
            var frame = golfer.frame(0, clipTime: time, grip: (0.30, 0.50), head: (0.40, headY), ball: ball)
            frame.silhouette = nil
            return frame
        }
        // Clubhead below the hands, then above (crossing hand height at
        // t = 1.5), up to the top, then back down through it at t = 6.5.
        var track = [
            sample(1, headY: 0.60, ball: true), sample(2, headY: 0.40, ball: true), sample(3, headY: 0.30, ball: true),
            sample(5, headY: 0.30, ball: true), sample(6.4, headY: 0.45, ball: true), sample(6.6, headY: 0.55, ball: true),
            sample(6.8, headY: 0.62, ball: true), sample(7.0, headY: 0.68, ball: true), sample(7.2, headY: 0.72, ball: true),
        ]
        // The ball is struck at 7.4 and never seen again.
        track += [7.4, 7.6, 7.8, 8.0, 8.2].map { sample($0, headY: 0.75, ball: false) }
        let evidence = golfer.evidence([golfer.frame(1, wristConfidence: 0.1)], track: track)
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: evidence))

        let times = CoachingCheckpointTiming.refine(geometry: geometry, modelTimes: [1: 0, 4: 4, 7: 7.5])
        XCTAssertEqual(try XCTUnwrap(times.takeaway), 1.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(times.delivery), 6.5, accuracy: 0.01)
        XCTAssertEqual(times.impact, 7.4)
    }

    func testBallHiddenForAMomentIsNotImpact() throws {
        let golfer = SyntheticSwing()
        func sample(_ time: Double, ball: Bool) -> CoachingFrameEvidence {
            var frame = golfer.frame(0, clipTime: time, grip: (0.30, 0.50), head: (0.40, 0.70), ball: ball)
            frame.silhouette = nil
            return frame
        }
        func impact(_ seen: [Bool]) throws -> Double? {
            let track = seen.enumerated().map { sample(6.2 + 0.1 * Double($0.offset), ball: $0.element) }
            let evidence = golfer.evidence([golfer.frame(1, wristConfidence: 0.1)], track: track)
            let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: evidence))
            return CoachingCheckpointTiming.refine(geometry: geometry, modelTimes: [1: 0, 4: 4, 7: 7.5]).impact
        }
        // Seen, hidden behind the club for four samples, seen again, then
        // struck: impact is where the last absence starts.
        let hidden = [true, true, true, true, false, false, false, false]
        let gone = [false, false, false, false, false]
        XCTAssertEqual(try XCTUnwrap(impact(hidden + [true, true] + gone)), 7.2, accuracy: 0.001)
        // Seen only once after being hidden: still not impact at the gap.
        XCTAssertEqual(try XCTUnwrap(impact(hidden + [true] + gone)), 7.1, accuracy: 0.001)
        // Too few frames after the last sighting to call it gone.
        XCTAssertNil(try impact(hidden + [true, false, false]))
    }

    func testClubTimesThatBreakTheOrderOrSitFarFromTheModelAreRefused() {
        let model: [Int: Double] = [1: 0, 2: 1.0, 3: 1.4, 4: 3, 5: 4, 6: 4.4, 7: 4.8, 8: 5.2]
        // At 8x slow motion a slot is 0.267 s. P2 at 1.6 is within four
        // slots of the model but after P3; P6 at 4.5 is fine; P7 at 4.45
        // would come before the accepted P6.
        let refined = CoachingCheckpointTiming.Times(takeaway: 1.6, delivery: 4.5, impact: 4.45)
        let times = CoachingCheckpointTiming.accepting(refined, over: model, timeScale: 8)
        XCTAssertEqual(times[2], 1.0)
        XCTAssertEqual(times[6], 4.5)
        XCTAssertEqual(times[7], 4.8)
        // Three slots away is too far for P6.
        XCTAssertEqual(CoachingCheckpointTiming.accepting(.init(delivery: 3.5), over: model, timeScale: 8)[6], 4.4)
    }

    func testShaftsLeaningOppositeWaysAreFarApartNotTheSame() throws {
        let golfer = SyntheticSwing()
        // Halfway back the shaft leans back; halfway down it leans the same
        // amount toward the ball. Folding the sides together would call
        // that no change.
        let report = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([
            golfer.frame(1, wristConfidence: 0.1),
            golfer.frame(3, grip: (0.22, 0.40), head: (0.12, 0.20)),
            golfer.frame(5, grip: (0.22, 0.40), head: (0.32, 0.20)),
        ])))
        // 63 degrees from flat-back going back, 117 coming down. That is
        // more than ten steps out, so it is dropped as a slip, not scored 0.
        XCTAssertNil(report.metric(.transition))

        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: golfer.evidence([golfer.frame(1, wristConfidence: 0.1)])))
        XCTAssertEqual(geometry.angleFromBack(CoachingVector(-0.10, -0.20)), 63.4, accuracy: 0.1)
        XCTAssertEqual(geometry.angleFromBack(CoachingVector(0.10, -0.20)), 116.6, accuracy: 0.1)
        XCTAssertEqual(geometry.angleFromBack(CoachingVector(-0.20, 0.035)), -9.9, accuracy: 0.1, "below flat is negative")
        let unit = geometry.direction(atAngleFromBack: 116.6)
        XCTAssertGreaterThan(unit.x, 0, "past upright points toward the ball")
        XCTAssertLessThan(unit.y, 0)
    }

    func testTrackSampleAtTheExactTimeKeepsItsConfidence() throws {
        let golfer = SyntheticSwing()
        func sample(_ time: Double) -> CoachingFrameEvidence {
            var frame = golfer.frame(0, clipTime: time, grip: (0.22, 0.40), head: (0.10, 0.28))
            frame.silhouette = nil
            return frame
        }
        let evidence = golfer.evidence([golfer.frame(1, wristConfidence: 0.1)], track: [sample(3.0), sample(3.2), sample(3.4)])
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: evidence))
        let exact = try XCTUnwrap(geometry.trackedShaft(atTime: 3.2))
        let between = try XCTUnwrap(geometry.trackedShaft(atTime: 3.1))
        let beyond = try XCTUnwrap(geometry.trackedShaft(atTime: 3.5))
        XCTAssertEqual(exact.confidence, 0.9, accuracy: 0.001)
        XCTAssertEqual(between.confidence, 0.9 * 0.6, accuracy: 0.001)
        XCTAssertEqual(beyond.confidence, 0.9 * 0.6, accuracy: 0.001, "past the end is no surer than a midpoint")
    }

    func testNoClubTimesWithoutATrack() throws {
        let golfer = SyntheticSwing()
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: golfer.evidence([golfer.frame(1)])))
        XCTAssertEqual(CoachingCheckpointTiming.refine(geometry: geometry, modelTimes: [1: 0, 4: 4]),
                       CoachingCheckpointTiming.Times())
    }

    // MARK: - What to say

    func testDecentSwingGetsNoPointers() {
        // Small misses, and one level 3 on its own: none is worth a thought.
        let decent = report([result(.hipDepthImpact, level: 1), result(.leadArmTop, level: 3), result(.transition, level: 0)])
        XCTAssertEqual(CoachingFeedback.verdict(for: decent), .good)
        XCTAssertEqual(CoachingFeedback.verdict(for: decent).headline, "Good swing")
    }

    func testMentionsOneFaultAndFoldsItsMetricsTogether() throws {
        let swing = report([
            result(.hipDepthImpact, level: 4), result(.postureImpact, level: -3), result(.headHeightImpact, level: 2),
            result(.trailKneeImpact, level: 2), result(.leadArmTop, level: 3),
        ])
        let findings = CoachingFeedback.findings(in: swing)
        XCTAssertEqual(findings.map(\.fault), [.earlyExtension, .topPosition])
        XCTAssertEqual(findings[0].metric, .hipDepthImpact)
        XCTAssertEqual(Set(findings[0].supporting), [.postureImpact, .headHeightImpact, .trailKneeImpact])

        guard case .focus(let finding) = CoachingFeedback.verdict(for: swing) else {
            return XCTFail("expected one focus")
        }
        XCTAssertEqual(finding.fault, .earlyExtension)
        XCTAssertEqual(finding.text, "Hips moved toward the ball")
    }

    func testDirectionDecidesTheFault() {
        XCTAssertEqual(CoachingFault.fault(for: result(.transition, level: 3)), .steepTransition)
        XCTAssertEqual(CoachingFault.fault(for: result(.transition, level: -3)), .flatTransition)
        XCTAssertEqual(CoachingFault.fault(for: result(.shaftHalfwayDown, level: -2)), .steepTransition)
        XCTAssertEqual(CoachingFault.fault(for: result(.shaftHalfwayDown, level: 2)), .flatTransition)
        XCTAssertNil(CoachingFault.fault(for: result(.transition, level: 0)))
        // Gaining hip depth is not a fault, nor is a knee that pulls back.
        XCTAssertNil(CoachingFault.fault(for: result(.hipDepthImpact, level: -2)))
        XCTAssertNil(CoachingFault.fault(for: result(.trailKneeImpact, level: -2)))
        XCTAssertEqual(CoachingFault.fault(for: result(.trailKneeImpact, level: 2)), .earlyExtension)
    }

    func testThemeNeedsHalfTheSessionAndFourSwings() {
        let steep = report([result(.transition, level: 4)])
        let clean = report([result(.transition, level: 0)])
        XCTAssertTrue(CoachingFeedback.themes(in: [steep, steep, steep]).isEmpty, "three swings is not a pattern")
        XCTAssertTrue(CoachingFeedback.themes(in: [steep, steep, steep, steep] + Array(repeating: clean, count: 6)).isEmpty,
                      "four of ten is under half")

        let themes = CoachingFeedback.themes(in: [steep, steep, clean, steep, steep, clean])
        XCTAssertEqual(themes.map(\.fault), [.steepTransition])
        XCTAssertEqual(themes[0].swings, 4)
        XCTAssertEqual(themes[0].measured, 6)
        XCTAssertEqual(themes[0].medianLevel, 4)
        XCTAssertEqual(themes[0].text, "Shaft steepens coming down")
    }

    func testEarlierFaultLeadsWhenThemesAreClose() {
        let both = report([result(.takeawayClub, level: -4), result(.hipDepthImpact, level: 3)])
        XCTAssertEqual(CoachingFeedback.themes(in: Array(repeating: both, count: 3), minimumSwings: 3).count, 2,
                       "a recap of the last few swings can ask for fewer")
        let themes = CoachingFeedback.themes(in: Array(repeating: both, count: 5))
        XCTAssertEqual(themes.map(\.fault), [.takeaway, .earlyExtension])
    }

    func testStaysOnTheSessionThemeAndNoticesWhenItIsGone() {
        let steep = report([result(.transition, level: 3)])
        let session = Array(repeating: steep, count: 5)

        // The theme is mentioned at a level that wouldn't earn a pointer cold.
        XCTAssertEqual(CoachingFeedback.verdict(for: steep), .good)
        guard case .focus = CoachingFeedback.verdict(for: steep, earlier: session) else {
            return XCTFail("expected the theme")
        }

        // A new, bigger-looking miss doesn't pull attention off the theme...
        let alsoHigh = report([result(.transition, level: 3), result(.leadArmTop, level: 4)])
        guard case .focus(let finding) = CoachingFeedback.verdict(for: alsoHigh, earlier: session) else {
            return XCTFail("expected a focus")
        }
        XCTAssertEqual(finding.fault, .steepTransition)

        // ...unless it is far outside its zone.
        let wayOff = report([result(.transition, level: 3), result(.hipDepthImpact, level: 9)])
        guard case .focus(let override) = CoachingFeedback.verdict(for: wayOff, earlier: session) else {
            return XCTFail("expected a focus")
        }
        XCTAssertEqual(override.fault, .earlyExtension)

        // The theme metric back in zone is worth saying.
        let fixed = report([result(.transition, level: 0), result(.leadArmTop, level: 2)])
        XCTAssertEqual(CoachingFeedback.verdict(for: fixed, earlier: session), .better(.steepTransition))
    }

    func testOppositeDirectionsOfAMetricAreNotOneTheme() {
        // Three swings with the clubhead inside the hands and three with it
        // outside: neither happened four times.
        let inside = report([result(.takeawayClub, level: -4)])
        let outside = report([result(.takeawayClub, level: 4)])
        XCTAssertTrue(CoachingFeedback.themes(in: [inside, outside, inside, outside, inside, outside]).isEmpty)

        // Four each way out of eight: both reach half, and neither is said.
        XCTAssertTrue(CoachingFeedback.themes(in: Array(repeating: inside, count: 4) + Array(repeating: outside, count: 4)).isEmpty)

        let themes = CoachingFeedback.themes(in: [inside, outside, inside, inside, inside])
        XCTAssertEqual(themes.map(\.text), ["Clubhead inside the hands"])
        XCTAssertEqual(themes[0].swings, 4)
        XCTAssertEqual(themes[0].measured, 5)
        XCTAssertEqual(themes[0].medianLevel, -4)
    }

    func testThemeCountsEverySwingWhereTheFaultCouldBeSeen() {
        // Early extension on four swings, by two different metrics; six
        // clean swings where only posture was measured still count as
        // swings that could have shown it. Four of ten is not a theme.
        let hips = report([result(.hipDepthImpact, level: 3), result(.postureImpact, level: 0)])
        let posture = report([result(.postureImpact, level: -3)])
        let clean = report([result(.postureImpact, level: 0)])
        XCTAssertTrue(CoachingFeedback.themes(in: [hips, hips, hips, posture] + Array(repeating: clean, count: 6)).isEmpty)

        let theme = CoachingFeedback.themes(in: [hips, hips, hips, posture, clean, clean]).first
        XCTAssertEqual(theme?.fault, .earlyExtension)
        XCTAssertEqual(theme?.swings, 4)
        XCTAssertEqual(theme?.measured, 6)
        XCTAssertEqual(theme?.metric, .hipDepthImpact, "the metric that led most often stands for it")
    }

    func testThemeOrderIsTheSameEveryTimeAndMedianIsTheMiddle() {
        // Takeaway, top and impact themes whose scores chain within a
        // quarter of each other pairwise but not end to end.
        let swing = report([result(.takeawayClub, level: -3), result(.leadArmTop, level: 5), result(.hipDepthImpact, level: 4)])
        let first = CoachingFeedback.themes(in: Array(repeating: swing, count: 6)).map(\.id)
        for _ in 0..<20 {
            XCTAssertEqual(CoachingFeedback.themes(in: Array(repeating: swing, count: 6)).map(\.id), first)
        }
        // Impact scores highest; the top is within a quarter of it and
        // earlier, so it leads. Takeaway is too weak to jump the queue.
        XCTAssertEqual(first, ["topPosition-leadArmTop-1", "earlyExtension-hipDepthImpact-1", "takeaway-takeawayClub--1"])

        let low = report([result(.transition, level: 2)]), high = report([result(.transition, level: 6)])
        XCTAssertEqual(CoachingFeedback.themes(in: [low, low, high, high]).first?.medianLevel, 4)
    }

    func testCoachDrawsOnlyTheFaultItNamesAndNothingOnAGoodSwing() {
        // Out of zone in three places, none worth a pointer.
        let decent = report([result(.takeawayClub, level: -2), result(.shaftHalfwayBack, level: 2), result(.leadArmTop, level: 3)])
        XCTAssertEqual(CoachingFeedback.verdict(for: decent), .good)
        XCTAssertTrue(CoachingFeedback.picks(for: .good).isEmpty)
        XCTAssertTrue(CoachingFeedback.picks(for: .better(.takeaway)).isEmpty)
        XCTAssertTrue(CoachingFeedback.picks(for: .notJudged(.shortSwing)).isEmpty)

        // Standing up, shown by three metrics, plus an unrelated miss: the
        // fault's own metrics are drawn, the other one is not.
        let standing = report([
            result(.hipDepthImpact, level: 4), result(.trailKneeImpact, level: 3), result(.postureImpact, level: -2),
            result(.leadArmTop, level: 3),
        ])
        XCTAssertEqual(CoachingFeedback.picks(for: CoachingFeedback.verdict(for: standing)),
                       [.hipDepthImpact, .trailKneeImpact, .postureImpact])
    }

    func testSessionVerdictsJudgeEachSwingAgainstTheOnesBefore() {
        let steep = report([result(.transition, level: 3)])
        let clean = report([result(.transition, level: 0)])
        let verdicts = CoachingFeedback.sessionVerdicts([steep, steep, steep, steep, steep, clean])
        // Level 3 alone is not worth a pointer for the first four; once
        // four swings have shown it, it is the theme.
        XCTAssertEqual(verdicts[0], .good)
        XCTAssertEqual(verdicts[3], .good)
        guard case .focus(let finding) = verdicts[4] else { return XCTFail("the fifth is on the theme") }
        XCTAssertEqual(finding.fault, .steepTransition)
        XCTAssertEqual(verdicts[5], .better(.steepTransition))
    }

    func testSessionVerdictsJudgeASwingAloneWhileAnEarlierOneIsUncoached() {
        // Level 3 alone is not worth a pointer; as a theme it is.
        let steep = report([result(.transition, level: 3)])
        let all = CoachingFeedback.sessionVerdicts([steep, steep, steep, steep, steep, steep])
        XCTAssertEqual(all.filter { $0 == .good }.count, 4)

        // With the first swing still to be coached, every later pill
        // judges its swing alone, so the count must too.
        let waiting = CoachingFeedback.sessionVerdicts([nil, steep, steep, steep, steep, steep])
        XCTAssertEqual(waiting, Array(repeating: .good, count: 5))
        XCTAssertEqual(CoachingFeedback.verdict(for: steep, earlierInSession: [nil, steep, steep, steep, steep]), .good)
    }

    func testAWeakerConfidentReadingDoesNotHideAThemeReading() {
        // Hands high at level 2 with little confidence shows standing up.
        let hands = result(.handsHeightImpact, level: 2, confidence: 0.35)
        let alone = Array(repeating: report([hands]), count: 4)
        XCTAssertEqual(CoachingFeedback.themes(in: alone).first?.fault, .earlyExtension)

        // A confident level 1 on the hips outscores it on each swing but
        // is under theme level: the theme stays, on the hands.
        let hips = result(.hipDepthImpact, level: 1, confidence: 0.85)
        let both = Array(repeating: report([hands, hips]), count: 4)
        let theme = CoachingFeedback.themes(in: both).first
        XCTAssertEqual(theme?.fault, .earlyExtension)
        XCTAssertEqual(theme?.metric, .handsHeightImpact)
        XCTAssertEqual(theme?.swings, 4)
    }

    func testBetterNeedsTheThemeMetricBackInItsZone() {
        let forward = report([result(.hipDepthImpact, level: 3), result(.postureImpact, level: -2)])
        let session = Array(repeating: forward, count: 5)
        XCTAssertEqual(CoachingFeedback.themes(in: session).first?.metric, .hipDepthImpact)

        // Hips now well back the other way: not a fault, but not "in zone".
        let backTheOtherWay = report([result(.hipDepthImpact, level: -4), result(.postureImpact, level: 0)])
        XCTAssertEqual(CoachingFeedback.verdict(for: backTheOtherWay, earlier: session), .good)
        let inZone = report([result(.hipDepthImpact, level: 0), result(.postureImpact, level: 0)])
        XCTAssertEqual(CoachingFeedback.verdict(for: inZone, earlier: session), .better(.earlyExtension))
    }

    // MARK: - Swings that aren't judged

    func testTooLittleSeenIsNotAGoodSwing() throws {
        // Address is clear; nothing else was seen.
        let golfer = SyntheticSwing()
        var frames = [golfer.frame(1, wristConfidence: 0.1)]
        for position in 2...10 { frames.append(CoachingFrameEvidence(position: position, clipTime: Double(position))) }
        let report = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence(frames)))
        XCTAssertTrue(report.metrics.allSatisfy { !$0.definition.scored })
        XCTAssertEqual(CoachingFeedback.verdict(for: report), .notJudged(.positionsUnclear))

        // The whole swing seen and in zone is a good swing.
        let seen = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([
            golfer.frame(1, wristConfidence: 0.1),
            golfer.frame(4, grip: (0.20, 0.20), head: (0.10, 0.10)),
            golfer.frame(7, wristConfidence: 0.1, ball: false),
        ])))
        XCTAssertNil(seen.exclusion)
    }

    func testChipIsMeasuredButNotJudgedOrCountedInThemes() throws {
        let golfer = SyntheticSwing()
        // Hands stop at hip height at the top: under the trail shoulder (y 0.34).
        let chip = golfer.evidence([
            golfer.frame(1, wristConfidence: 0.1),
            golfer.frame(4, grip: (0.24, 0.48), head: (0.14, 0.52)),
            golfer.frame(7, back: 0.15 + 0.08 * SyntheticSwing.bodyScale, wristConfidence: 0.1, ball: false),
        ])
        let report = try XCTUnwrap(CoachingAnalyzer.analyze(chip))
        XCTAssertEqual(report.swingLength, .short)
        XCTAssertEqual(report.exclusion, .shortSwing)
        XCTAssertNotEqual(report.metric(.hipDepthImpact)?.level, 0, "still measured")
        XCTAssertTrue(CoachingFeedback.findings(in: report).isEmpty)
        XCTAssertEqual(CoachingFeedback.verdict(for: report), .notJudged(.shortSwing))
        XCTAssertEqual(CoachingFeedback.verdict(for: report).headline, "Short swing, not judged")
        XCTAssertTrue(CoachingFeedback.themes(in: Array(repeating: report, count: 8)).isEmpty)
    }

    func testMovedCameraAndUnclearPositionsAreNotJudged() throws {
        let golfer = SyntheticSwing()
        // Both feet 15% of body scale lower at the top: the camera tilted.
        var top = golfer.frame(4, grip: (0.22, 0.20), head: (0.10, 0.10))
        for ankle in ["leftAnkle", "rightAnkle"] { top.joints[ankle]?.y += 0.15 * SyntheticSwing.bodyScale }
        let impact = golfer.frame(7, wristConfidence: 0.1, ball: false)
        let moved = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([golfer.frame(1, wristConfidence: 0.1), top, impact])))
        XCTAssertTrue(moved.cameraMoved)
        XCTAssertEqual(CoachingFeedback.verdict(for: moved), .notJudged(.cameraMoved))

        // "Address" with the club already up beside the hands: a rehearsal.
        let rehearsal = golfer.frame(1, grip: (0.22, 0.40), head: (0.10, 0.28))
        let unclear = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([rehearsal])))
        XCTAssertTrue(unclear.positionsUnclear)
        XCTAssertEqual(CoachingFeedback.verdict(for: unclear), .notJudged(.positionsUnclear))

        // "Impact" with the hands well away from where they started.
        let steadyTop = golfer.frame(4, grip: (0.20, 0.20), head: (0.10, 0.10))
        let late = golfer.frame(7, grip: (0.45, 0.30), head: (0.60, 0.20), ball: false)
        let followThrough = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([golfer.frame(1, wristConfidence: 0.1), steadyTop, late])))
        XCTAssertTrue(followThrough.positionsUnclear)

        // The same when blur hides the shaft and only the wrists say where
        // the hands are; and with neither, impact can't be vouched for.
        var blurred = late
        blurred.shafts = []
        blurred.clubheads = []
        XCTAssertTrue(try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([golfer.frame(1, wristConfidence: 0.1), steadyTop, blurred]))).positionsUnclear)
        var handsUnseen = golfer.frame(7, wristConfidence: 0.1, ball: false)
        handsUnseen.shafts = []
        handsUnseen.clubheads = []
        XCTAssertTrue(try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([golfer.frame(1, wristConfidence: 0.1), steadyTop, handsUnseen]))).positionsUnclear)
    }

    func testReadingFarOutsideTheZoneIsDroppedAsASlip() throws {
        let hips = CoachingMetricDefinition.definition(.hipDepthImpact)
        XCTAssertTrue(hips.isBelievable(hips.zone.upperBound + 10 * hips.step))
        XCTAssertFalse(hips.isBelievable(hips.zone.upperBound + 10 * hips.step + 0.1))

        // The backside "moves" a third of body scale: another person joined the outline.
        let golfer = SyntheticSwing()
        let report = try XCTUnwrap(CoachingAnalyzer.analyze(golfer.evidence([
            golfer.frame(1, wristConfidence: 0.1),
            golfer.frame(7, back: 0.15 + 0.33 * SyntheticSwing.bodyScale, wristConfidence: 0.1, ball: false),
        ])))
        XCTAssertNil(report.metric(.hipDepthImpact))
        XCTAssertTrue(report.unavailable.contains(.hipDepthImpact))
    }

    func testClubReadingsAreMarkedAsCameraDependentAndBodyReadingsAreNot() {
        let marked = Set(CoachingMetricDefinition.all.filter(\.dependsOnCamera).map(\.id))
        XCTAssertEqual(marked, [.takeawayClub, .planeTakeaway, .shaftHalfwayBack, .transition, .shaftHalfwayDown, .planeDelivery])
    }

    func testGuidesAreDrawnButNeverJudged() throws {
        let plane = CoachingMetricDefinition.definition(.planeDelivery)
        XCTAssertFalse(plane.scored)
        XCTAssertEqual(plane.level(for: 500), 0)
        XCTAssertFalse(CoachingMetricDefinition.definition(.setupPosture).scored)
        XCTAssertNil(CoachingFault.fault(for: result(.setupHands, level: 0)))
    }

    func testFrameShaftBeatsAShakyTrackBetweenSamples() throws {
        let golfer = SyntheticSwing()
        func sample(_ time: Double, head: (Double, Double), confidence: Double) -> CoachingFrameEvidence {
            var frame = golfer.frame(0, clipTime: time, grip: (0.22, 0.40), head: head)
            frame.silhouette = nil
            frame.shafts[0].confidence = confidence
            frame.clubheads[0].confidence = confidence
            return frame
        }
        // Halfway back the frame shows the shaft (no clubhead) with high
        // confidence; the track either side saw the club only faintly.
        var halfwayBack = golfer.frame(3, clipTime: 3, grip: (0.22, 0.40), head: (0.10, 0.28))
        halfwayBack.clubheads = []
        let evidence = golfer.evidence([golfer.frame(1, wristConfidence: 0.1), halfwayBack], track: [
            sample(2.9, head: (0.14, 0.30), confidence: 0.35), sample(3.1, head: (0.14, 0.30), confidence: 0.35),
        ])
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: evidence))
        let shaft = try XCTUnwrap(geometry.shaft(at: 3))
        XCTAssertEqual(shaft.head.x, 0.10, accuracy: 0.01, "the frame's own shaft box")
        XCTAssertFalse(shaft.headDetected)
    }

    func testZonesKeepTheirOrderAndAStep() {
        for definition in CoachingMetricDefinition.all {
            XCTAssertLessThan(definition.zone.lowerBound, definition.zone.upperBound, definition.id.rawValue)
            XCTAssertGreaterThan(definition.step, 0, definition.id.rawValue)
            XCTAssertTrue((1...10).contains(definition.position), definition.id.rawValue)
        }
    }

    // MARK: - Positions re-timed by the club

    func testRetimedPositionsKeepTheModelTimesAndRestoreThem() {
        let model = SwingPositions(model: SwingPositions.currentModel, positions: (1...10).map {
            SwingPosition(number: $0, clipTime: Double($0), confidence: 0.9)
        })
        let golfer = SyntheticSwing()
        var frames = (1...10).map { golfer.frame($0, clipTime: Double($0)) }
        frames[1] = golfer.frame(2, clipTime: 2.5)

        let retimed = SwingCoachingStore.retimed(model, by: golfer.evidence(frames))
        XCTAssertEqual(retimed.positions[1].clipTime, 2.5)
        XCTAssertEqual(retimed.positions[2].clipTime, 3)
        XCTAssertEqual(retimed.modelClipTimes, (1...10).map(Double.init))
        XCTAssertEqual(SwingCoachingStore.modelPositions(retimed).positions, model.positions)

        // Nothing moved: nothing recorded.
        let unmoved = SwingCoachingStore.retimed(model, by: golfer.evidence((1...10).map { golfer.frame($0, clipTime: Double($0)) }))
        XCTAssertNil(unmoved.modelClipTimes)
        XCTAssertEqual(unmoved, model)
    }

    func testStoredPositionsWithoutClubTimesStillDecode() throws {
        let old = #"{"model":"tcn_vision_v2","positions":[{"number":1,"clipTime":1.5,"confidence":0.8}]}"#
        let decoded = try JSONDecoder().decode(SwingPositions.self, from: Data(old.utf8))
        XCTAssertNil(decoded.modelClipTimes)
        XCTAssertEqual(decoded.positions.first?.clipTime, 1.5)
    }
}
