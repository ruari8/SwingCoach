import XCTest
@testable import SwingCoach

final class SwingTempoTests: XCTestCase {
    private func makePositions(
        p1: Double = 8.0,
        takeawayStart: Double? = 8.64,
        p2: Double = 11.2,
        p4: Double = 14.4,
        p7: Double = 16.6,
        confidences: [Int: Double] = [:]
    ) -> SwingPositions {
        let defaults: [(Int, Double)] = [
            (1, p1), (2, p2), (3, (p2 + p4) / 2), (4, p4),
            (5, p4 + (p7 - p4) * 0.5), (6, p4 + (p7 - p4) * 0.8),
            (7, p7), (8, p7 + 0.4), (9, p7 + 1.0), (10, p7 + 3.0),
        ]
        let list = defaults.map { number, time in
            SwingPosition(number: number, clipTime: time, confidence: confidences[number] ?? 0.9)
        }
        return SwingPositions(
            model: SwingPositions.currentModel,
            positions: list,
            takeawayStartClipTime: takeawayStart
        )
    }

    // MARK: - Core tempo math & frame rates

    func testComputesBackswingDownswingAndRatioAt240FPS() throws {
        // Real swing: backswing = 720 ms, downswing = 240 ms -> 3.0:1.
        // At 240 fps exported at 30 fps (8x): 0.720 * 8 = 5.76 s, 0.240 * 8 = 1.92 s.
        let positions = makePositions(p1: 8.0, takeawayStart: 8.64, p4: 14.40, p7: 16.32)
        let tempo = try XCTUnwrap(SwingTempo.measure(positions: positions, timeScale: 8))
        XCTAssertEqual(tempo.backswingMilliseconds, 720, accuracy: 1e-6)
        XCTAssertEqual(tempo.downswingMilliseconds, 240, accuracy: 1e-6)
        XCTAssertEqual(tempo.ratio, 3.0, accuracy: 1e-6)
        XCTAssertEqual(tempo.backswingMS, 720)
        XCTAssertEqual(tempo.downswingMS, 240)
        XCTAssertEqual(tempo.ratioText, "3.0:1")
        XCTAssertEqual(tempo.backswingText, "720 ms")
        XCTAssertEqual(tempo.downswingText, "240 ms")
        XCTAssertEqual(tempo.summaryText, "3.0:1 · 720 / 240 ms")
        XCTAssertEqual(tempo.backswingShare, 0.75, accuracy: 1e-6)
        XCTAssertFalse(tempo.isLowConfidence)

        let fromFPS = try XCTUnwrap(SwingTempo.measure(positions: positions, sourceFPS: 240, playbackFPS: 30))
        XCTAssertEqual(fromFPS, tempo)
    }

    func test120FPSVs240FPSUsesRealFrameRate() throws {
        // Same physical swing (720 ms backswing, 240 ms downswing) recorded at 120 fps (4x)
        // produces half the slow-motion clip delta of 240 fps (8x), so real ms must match.
        let clip240 = makePositions(p1: 8.0, takeawayStart: 8.64, p4: 14.40, p7: 16.32)
        let clip120 = makePositions(p1: 4.0, takeawayStart: 4.32, p4: 7.20, p7: 8.16)

        let tempo240 = try XCTUnwrap(SwingTempo.measure(positions: clip240, sourceFPS: 240, playbackFPS: 30))
        let tempo120 = try XCTUnwrap(SwingTempo.measure(positions: clip120, sourceFPS: 120, playbackFPS: 30))
        XCTAssertEqual(tempo120.backswingMilliseconds, tempo240.backswingMilliseconds, accuracy: 1e-6)
        XCTAssertEqual(tempo120.downswingMilliseconds, tempo240.downswingMilliseconds, accuracy: 1e-6)
        XCTAssertEqual(tempo120.ratio, tempo240.ratio, accuracy: 1e-6)

        // Conversely, identical clip-timeline timestamps at 120 fps vs 240 fps differ by 2x
        // in milliseconds (never assumes 240 fps) while keeping the same ratio.
        let sameTimestampsAt120 = try XCTUnwrap(SwingTempo.measure(positions: clip240, timeScale: 4))
        XCTAssertEqual(sameTimestampsAt120.backswingMilliseconds, tempo240.backswingMilliseconds * 2, accuracy: 1e-6)
        XCTAssertEqual(sameTimestampsAt120.downswingMilliseconds, tempo240.downswingMilliseconds * 2, accuracy: 1e-6)
        XCTAssertEqual(sameTimestampsAt120.ratio, tempo240.ratio, accuracy: 1e-6)
    }

    func testFormatsRatioToOneDecimal() throws {
        // 731 ms / 272 ms = 2.6875 -> "2.7:1"
        let positions = makePositions(p1: 8.0, takeawayStart: 8.552, p4: 14.4, p7: 16.576)
        let tempo = try XCTUnwrap(SwingTempo.measure(positions: positions, timeScale: 8))
        XCTAssertEqual(tempo.backswingMS, 731)
        XCTAssertEqual(tempo.downswingMS, 272)
        XCTAssertEqual(tempo.ratioText, "2.7:1")
    }

    // MARK: - Missing / invalid / low-confidence cases

    func testReturnsNilWithoutTakeawayStartAndNeverFallsBackToP1() {
        let missing = makePositions(takeawayStart: nil)
        XCTAssertNil(SwingTempo.measure(positions: missing, timeScale: 8))

        // Takeaway start must be strictly after P1, never P1 itself or earlier.
        let equalToP1 = makePositions(p1: 8.0, takeawayStart: 8.0, p4: 14.4, p7: 16.6)
        XCTAssertNil(SwingTempo.measure(positions: equalToP1, timeScale: 8))

        let beforeP1 = makePositions(p1: 8.0, takeawayStart: 7.9, p4: 14.4, p7: 16.6)
        XCTAssertNil(SwingTempo.measure(positions: beforeP1, timeScale: 8))

        // Takeaway start must be strictly before P4.
        let atP4 = makePositions(p1: 8.0, takeawayStart: 14.4, p4: 14.4, p7: 16.6)
        XCTAssertNil(SwingTempo.measure(positions: atP4, timeScale: 8))
    }

    func testReturnsNilWhenRequiredPositionsOrTimeScaleAreMissingOrInvalid() {
        let base = makePositions()
        XCTAssertNil(SwingTempo.measure(positions: base, timeScale: 0))
        XCTAssertNil(SwingTempo.measure(positions: base, timeScale: -4))
        XCTAssertNil(SwingTempo.measure(positions: base, timeScale: .nan))
        XCTAssertNil(SwingTempo.measure(positions: base, sourceFPS: 0, playbackFPS: 30))
        XCTAssertNil(SwingTempo.measure(positions: base, sourceFPS: 240, playbackFPS: 0))

        // Missing P1, P4, or P7.
        for drop in [1, 4, 7] {
            let trimmed = SwingPositions(
                model: SwingPositions.currentModel,
                positions: base.positions.filter { $0.number != drop },
                takeawayStartClipTime: base.takeawayStartClipTime
            )
            XCTAssertNil(SwingTempo.measure(positions: trimmed, timeScale: 8), "Dropping P\(drop) must return nil")
        }

        // Non-positive downswing.
        let reversedImpact = makePositions(p1: 8.0, takeawayStart: 8.64, p4: 14.4, p7: 14.4)
        XCTAssertNil(SwingTempo.measure(positions: reversedImpact, timeScale: 8))
    }

    func testFlagsLowConfidenceOnlyOnMeasuredEndpointsP4AndP7() throws {
        // Low confidence on P1 (address, fuzzy across still frames) or P8 does not make
        // tempo unsure, because backswing starts at the club-tracked takeaway start, not P1.
        let p8Low = makePositions(confidences: [8: 0.35])
        XCTAssertFalse(try XCTUnwrap(SwingTempo.measure(positions: p8Low, timeScale: 8)).isLowConfidence)

        let p1Low = makePositions(confidences: [1: 0.42])
        XCTAssertFalse(try XCTUnwrap(SwingTempo.measure(positions: p1Low, timeScale: 8)).isLowConfidence)

        // Low confidence on P4 (top) or P7 (impact) flags tempo as unsure.
        for number in [4, 7] {
            let low = makePositions(confidences: [number: 0.49])
            let tempo = try XCTUnwrap(SwingTempo.measure(positions: low, timeScale: 8))
            XCTAssertTrue(tempo.isLowConfidence, "Low confidence on P\(number) must mark tempo unsure")
        }
    }

    // MARK: - SavedSwing gating & Codable backwards compatibility

    @MainActor
    func testSavedSwingTempoIsDownTheLineAndKnownRateOnly() throws {
        var swing = SavedSwing(
            id: UUID(),
            photoAssetID: "",
            vantage: .dtl,
            duration: 23.2,
            createdAt: Date(),
            notes: nil,
            sourceTimeScale: 8
        )
        swing.swingPositions = makePositions(p1: 8.0, takeawayStart: 8.64, p4: 14.40, p7: 16.32)
        XCTAssertEqual(swing.tempo?.ratioText, "3.0:1")

        // Face-on gets no tempo.
        var faceOn = swing
        faceOn.vantage = .faceOn
        XCTAssertNil(faceOn.tempo)

        // Import without sourceTimeScale gets no tempo (never assumes 240 fps).
        var imported = swing
        imported.sourceTimeScale = nil
        XCTAssertNil(imported.tempo)

        // Reference clip gets no tempo.
        var reference = swing
        reference.isReference = true
        XCTAssertNil(reference.tempo)
    }

    func testSwingPositionsDecodesLegacyJSONWithoutTakeawayStartAndRoundTrips() throws {
        let legacyJSON = """
        {"model":"tcn_vision_v2","positions":[{"number":1,"clipTime":8.0,"confidence":0.9}]}
        """
        let decoded = try JSONDecoder().decode(SwingPositions.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.takeawayStartClipTime)

        var withStart = decoded
        withStart.takeawayStartClipTime = 8.64
        let roundTripped = try JSONDecoder().decode(SwingPositions.self, from: JSONEncoder().encode(withStart))
        XCTAssertEqual(roundTripped.takeawayStartClipTime, 8.64)
    }

    // MARK: - Takeaway start detection from club track

    private func buildTrackEvidence(
        clubheadMoves: [(time: Double, headDX: Double, gripDX: Double)],
        p1: Double = 8.0,
        p2: Double = 11.2,
        mirrored: Bool = false
    ) -> SwingCoachingEvidence {
        let aspect = 1080.0 / 1920.0
        func pt(_ x: Double, _ y: Double) -> CoachingPoint {
            let nx = x / aspect
            return CoachingPoint(x: mirrored ? 1 - nx : nx, y: y, confidence: 0.9)
        }
        func box(_ a: (Double, Double), _ b: (Double, Double)) -> CoachingBox {
            let p1 = pt(a.0, a.1), p2 = pt(b.0, b.1)
            return CoachingBox(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                               width: abs(p1.x - p2.x), height: abs(p1.y - p2.y), confidence: 0.9)
        }
        func spot(_ x: Double, _ y: Double) -> CoachingBox {
            box((x - 0.005, y - 0.005), (x + 0.005, y + 0.005))
        }
        func jointName(_ joint: CoachingJoint) -> String {
            guard mirrored else { return joint.rawValue }
            if joint.rawValue.hasPrefix("left") { return "right" + joint.rawValue.dropFirst(4) }
            if joint.rawValue.hasPrefix("right") { return "left" + joint.rawValue.dropFirst(5) }
            return joint.rawValue
        }
        func makeFrame(position: Int, time: Double, headDX: Double, gripDX: Double) -> CoachingFrameEvidence {
            var frame = CoachingFrameEvidence(position: position, clipTime: time)
            let grip = (0.30 + gripDX, 0.52)
            let head = (0.42 + headDX, 0.80)
            frame.joints = [
                jointName(.leftHip): pt(0.20, 0.50), jointName(.rightHip): pt(0.20, 0.50), jointName(.root): pt(0.20, 0.50),
                jointName(.neck): pt(0.26, 0.34),
                jointName(.rightShoulder): pt(0.25, 0.34), jointName(.leftShoulder): pt(0.27, 0.35),
                jointName(.rightAnkle): pt(0.20, 0.80), jointName(.leftAnkle): pt(0.21, 0.80),
                jointName(.rightElbow): pt(0.27, 0.44), jointName(.leftElbow): pt(0.28, 0.44),
                jointName(.rightWrist): pt(grip.0, grip.1), jointName(.leftWrist): pt(grip.0, grip.1),
                jointName(.nose): pt(0.29, 0.30),
            ]
            frame.shafts = [box(grip, head)]
            frame.clubheads = [spot(head.0, head.1)]
            return frame
        }
        let address = makeFrame(position: 1, time: p1, headDX: 0, gripDX: 0)
        let takeaway = makeFrame(position: 2, time: p2, headDX: -0.10, gripDX: -0.04)
        let track = clubheadMoves.map { makeFrame(position: 0, time: $0.time, headDX: $0.headDX, gripDX: $0.gripDX) }
        return SwingCoachingEvidence(frameWidth: 1080, frameHeight: 1920, timeScale: 8,
                                     frames: [address, takeaway], track: track)
    }

    func testTakeawayStartIgnoresAddressJitterAndSingleSpikeAndInterpolatesSustainedMotion() throws {
        // bodyScale = hypot(0.05, 0.16) + 0.30 ≈ 0.4676 -> 1.5% ≈ 0.007014.
        let bodyScale = hypot(0.05, 0.16) + 0.30
        let evidence = buildTrackEvidence(clubheadMoves: [
            (8.00, 0.000 * bodyScale, 0),
            (8.13, 0.004 * bodyScale, 0),  // resting jitter
            (8.27, 0.018 * bodyScale, 0),  // single-frame noise spike — must be ignored
            (8.40, 0.005 * bodyScale, 0),  // still at address
            (8.53, 0.010 * bodyScale, 0),  // just under 1.5%
            (8.67, 0.020 * bodyScale, 0),  // crosses 1.5% halfway between 8.53 and 8.67 -> 8.60
            (8.80, 0.030 * bodyScale, 0),
            (8.93, 0.045 * bodyScale, 0),
        ])
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: evidence))
        let start = try XCTUnwrap(CoachingCheckpointTiming.takeawayStart(
            geometry: geometry, modelTimes: [1: 8.0, 2: 11.2, 4: 14.4]
        ))
        XCTAssertEqual(start, 8.60, accuracy: 0.005)

        // Left-handed (mirrored) golfer gives the exact same takeaway start.
        let mirroredEvidence = buildTrackEvidence(clubheadMoves: [
            (8.00, 0.000 * bodyScale, 0),
            (8.40, 0.005 * bodyScale, 0),
            (8.53, 0.010 * bodyScale, 0),
            (8.67, 0.020 * bodyScale, 0),
            (8.80, 0.030 * bodyScale, 0),
            (8.93, 0.045 * bodyScale, 0),
        ], mirrored: true)
        let mirroredGeometry = try XCTUnwrap(CoachingSwingGeometry(evidence: mirroredEvidence))
        let mirroredStart = try XCTUnwrap(CoachingCheckpointTiming.takeawayStart(
            geometry: mirroredGeometry, modelTimes: [1: 8.0, 2: 11.2, 4: 14.4]
        ))
        XCTAssertEqual(mirroredStart, 8.60, accuracy: 0.005)
    }

    func testTakeawayStartReturnsNilWhenClubNeverLeavesAddressOrTrackIsTooShort() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        let still = buildTrackEvidence(clubheadMoves: [
            (8.2, 0.005 * bodyScale, 0),
            (8.4, 0.008 * bodyScale, 0),
            (8.6, 0.010 * bodyScale, 0),
            (8.8, 0.006 * bodyScale, 0),
        ])
        let stillGeometry = try XCTUnwrap(CoachingSwingGeometry(evidence: still))
        XCTAssertNil(CoachingCheckpointTiming.takeawayStart(geometry: stillGeometry, modelTimes: [1: 8.0, 2: 11.2]))

        let tooFew = buildTrackEvidence(clubheadMoves: [
            (8.4, 0.03 * bodyScale, 0),
            (8.6, 0.04 * bodyScale, 0),
        ])
        let fewGeometry = try XCTUnwrap(CoachingSwingGeometry(evidence: tooFew))
        XCTAssertNil(CoachingCheckpointTiming.takeawayStart(geometry: fewGeometry, modelTimes: [1: 8.0, 2: 11.2]))
    }

    func testRetimedPositionsStoresTakeawayStartClipTime() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        let evidence = buildTrackEvidence(clubheadMoves: [
            (8.40, 0.005 * bodyScale, 0),
            (8.53, 0.010 * bodyScale, 0),
            (8.67, 0.020 * bodyScale, 0),
            (8.80, 0.030 * bodyScale, 0),
            (8.93, 0.045 * bodyScale, 0),
        ])
        let model = makePositions(p1: 8.0, takeawayStart: nil, p2: 11.2, p4: 14.4, p7: 16.6)
        let retimed = SwingCoachingStore.retimed(model, by: evidence)
        XCTAssertEqual(try XCTUnwrap(retimed.takeawayStartClipTime), 8.60, accuracy: 0.005)
    }

    // MARK: - Session tempo trend

    func testSessionTrendComputesMediansExcludesUnsureAndExcludedAndDetectsDirection() throws {
        func tempo(back: Double, down: Double, low: Bool = false) -> SwingTempo {
            SwingTempo(backswingMilliseconds: back, downswingMilliseconds: down,
                       isLowConfidence: low, takeawayStartClipTime: 8.5)
        }

        let entries: [(id: UUID, tempo: SwingTempo?, excluded: Bool)] = [
            (UUID(), tempo(back: 700, down: 250), false),        // 2.8:1
            (UUID(), tempo(back: 725, down: 250), false),        // 2.9:1
            (UUID(), tempo(back: 400, down: 250, low: true), false),  // low confidence -> excluded
            (UUID(), tempo(back: 500, down: 250), true),              // chip/excluded -> excluded
            (UUID(), nil, false),                                      // missing -> excluded
            (UUID(), tempo(back: 800, down: 250), false),        // 3.2:1
            (UUID(), tempo(back: 825, down: 250), false),        // 3.3:1
        ]
        let trend = SwingTempoTrend.build(from: entries)
        XCTAssertEqual(trend.totalSwings, 7)
        XCTAssertEqual(trend.samples.count, 4)
        XCTAssertEqual(trend.samples.map(\.swingNumber), [1, 2, 6, 7])
        // Median of [2.8, 2.9, 3.2, 3.3] = 3.05 -> "3.1:1"
        XCTAssertEqual(try XCTUnwrap(trend.medianRatio), 3.05, accuracy: 1e-6)
        XCTAssertEqual(trend.medianRatioText, "3.1:1")
        XCTAssertEqual(trend.medianBackswingMS, 763)
        XCTAssertEqual(trend.medianDownswingMS, 250)
        // First half median 2.85, second half median 3.25 (+0.40 >= 0.2) -> slowerBackswing
        XCTAssertEqual(trend.direction, .slowerBackswing)

        // Steady session (within ±0.2)
        let steady = SwingTempoTrend.build(from: [2.8, 2.9, 2.9, 3.0].map { r in
            (UUID(), tempo(back: r * 250, down: 250), false)
        })
        XCTAssertEqual(steady.direction, .steady)

        // Quicker backswing (-0.4 <= -0.2)
        let quicker = SwingTempoTrend.build(from: [3.2, 3.1, 2.7, 2.6].map { r in
            (UUID(), tempo(back: r * 250, down: 250), false)
        })
        XCTAssertEqual(quicker.direction, .quickerBackswing)

        // Too few samples for direction (< 4)
        let short = SwingTempoTrend.build(from: [2.8, 3.2, 3.5].map { r in
            (UUID(), tempo(back: r * 250, down: 250), false)
        })
        XCTAssertNil(short.direction)
    }
}
