import XCTest
@testable import SwingCoach

/// The player's walkthrough order and the club-head trail, on the UI
/// fixture's report and evidence.
final class CoachingWalkthroughTests: XCTestCase {
    private func result(_ id: CoachingMetricID, value: Double, at time: Double, confidence: Double = 0.9) -> CoachingMetricResult {
        let definition = CoachingMetricDefinition.definition(id)
        return CoachingMetricResult(id: id, position: definition.position, clipTime: time, value: value,
                                    level: definition.level(for: value), confidence: confidence, drawings: [])
    }

    func testPointerComesFirstThenOtherFaultsInSwingOrder() {
        let report = UITestFixture.fixtureCoachingReport(steep: true)
        let verdict = CoachingFeedback.verdict(for: report)
        let steps = CoachingWalkthrough.steps(for: report, verdict: verdict)
        XCTAssertEqual(steps.map(\.kind), [.pointer, .finding])
        XCTAssertEqual(steps.map(\.lead), [.transition, .hipDepthImpact])
        XCTAssertEqual(steps[0].text, "Shaft steepens coming down")
        XCTAssertEqual(steps[0].clipTime, 1.85, accuracy: 1e-9)
        XCTAssertEqual(steps[1].position, 7)
        XCTAssertEqual(CoachingWalkthrough.place(steps[1].position), "At impact")
    }

    func testLaterFaultsFollowSwingOrderNotScore() {
        // Head dropped at the top (P4) is weaker than standing up at
        // impact (P7) but comes first in the swing.
        let report = SwingCoachingReport(rightHanded: true, metrics: [
            result(.transition, value: 26, at: 1.85),
            result(.hipDepthImpact, value: 9, at: 1.95),
            result(.headHeightTop, value: -10, at: 1.6),
        ], unavailable: [])
        let steps = CoachingWalkthrough.steps(for: report, verdict: CoachingFeedback.verdict(for: report))
        XCTAssertEqual(steps.first?.kind, .pointer)
        XCTAssertEqual(Array(steps.dropFirst()).map(\.position), [4, 7])
    }

    func testSupportingChecksOnTheSameFrameDrawTogether() {
        let report = SwingCoachingReport(rightHanded: true, metrics: [
            result(.hipDepthImpact, value: 9, at: 1.95),
            result(.trailKneeImpact, value: 14, at: 1.95),
            result(.transition, value: 0, at: 1.85),
        ], unavailable: [])
        let steps = CoachingWalkthrough.steps(for: report, verdict: CoachingFeedback.verdict(for: report))
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(Set(steps[0].metrics), [.hipDepthImpact, .trailKneeImpact])
    }

    func testGoodSwingOpensOnWhatWentRightThenSmallFaults() {
        let report = UITestFixture.fixtureCoachingReport(steep: false)
        let verdict = CoachingFeedback.verdict(for: report)
        XCTAssertEqual(verdict, .good)
        let steps = CoachingWalkthrough.steps(for: report, verdict: verdict)
        XCTAssertEqual(steps.first?.kind, .good)
        XCTAssertEqual(steps.first?.text, "Good swing")
        // Every check drawn on the good step is in zone.
        XCTAssertTrue(steps[0].metrics.allSatisfy { report.metric($0)?.inZone == true })
        XCTAssertEqual(steps.dropFirst().map(\.lead), [.hipDepthImpact])
    }

    func testSwingThatIsNotJudgedHasOneStepAndDrawsNothing() {
        var report = UITestFixture.fixtureCoachingReport(steep: true)
        report.swingLength = .short
        let steps = CoachingWalkthrough.steps(for: report, verdict: CoachingFeedback.verdict(for: report))
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].kind, .notJudged(.shortSwing))
        XCTAssertTrue(steps[0].metrics.isEmpty)
    }

    func testTrailFollowsTheClubAndFillsShortGaps() throws {
        let trail = try XCTUnwrap(CoachingClubTrail.make(from: UITestFixture.fixtureEvidence()))
        XCTAssertEqual(trail.points.first?.clipTime ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertTrue(trail.points.contains { !$0.seen }, "The samples where the club was lost are filled in")
        XCTAssertFalse(trail.points.contains(where: \.startsSegment))
        XCTAssertEqual(trail.points.map(\.clipTime), trail.points.map(\.clipTime).sorted())
    }

    func testTrailIgnoresAStillObjectAndAJump() throws {
        var evidence = UITestFixture.fixtureEvidence()
        for index in evidence.track.indices {
            // A bag in the corner in every sample, more confident than the club.
            evidence.track[index].clubheads.append(CoachingBox(x: 0.9, y: 0.9, width: 0.02, height: 0.02, confidence: 0.95))
        }
        // One wild detection across the frame.
        evidence.track[5].clubheads = [CoachingBox(x: 0.95, y: 0.05, width: 0.02, height: 0.02, confidence: 0.9)]
        let trail = try XCTUnwrap(CoachingClubTrail.make(from: evidence))
        XCTAssertFalse(trail.points.contains { $0.x > 0.85 }, "Neither the bag nor the jump is on the trail")
    }

    func testNoTrailWithoutATrack() {
        var evidence = UITestFixture.fixtureEvidence()
        evidence.track = []
        XCTAssertNil(CoachingClubTrail.make(from: evidence))
    }
}
