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

    // MARK: - Missing / invalid / low-confidence / excluded cases

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

    // MARK: - SavedSwing gating, exclusions & Codable backwards compatibility

    @MainActor
    func testSavedSwingTempoIsDownTheLineKnownRateAndUnexcludedOnly() throws {
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
        XCTAssertEqual(swing.tempo(excluding: nil)?.ratioText, "3.0:1")

        // Swings coaching refuses to judge get no tempo.
        for exclusion in [CoachingExclusion.shortSwing, .cameraMoved, .positionsUnclear] {
            XCTAssertNil(swing.tempo(excluding: exclusion), "Excluded (\(exclusion.rawValue)) must hide tempo")
        }

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
        addressHasClubhead: Bool = true,
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
        func makeFrame(position: Int, time: Double, headDX: Double, gripDX: Double, includeHead: Bool = true) -> CoachingFrameEvidence {
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
            if includeHead {
                frame.clubheads = [spot(head.0, head.1)]
            }
            return frame
        }
        let address = makeFrame(position: 1, time: p1, headDX: 0, gripDX: 0, includeHead: addressHasClubhead)
        let takeaway = makeFrame(position: 2, time: p2, headDX: -0.10, gripDX: -0.04)
        var track = clubheadMoves.map { makeFrame(position: 0, time: $0.time, headDX: $0.headDX, gripDX: $0.gripDX) }
        // Later backswing/downswing samples past P2 (as in a real swing track), so
        // CoachingSwingGeometry's stationary-bag junk filter does not mistake the
        // address clubhead for a static object occupying >40% of the whole clip.
        for step in 1...24 {
            let t = p2 + Double(step) * 0.25
            let move = -0.10 - Double(step) * 0.01
            track.append(makeFrame(position: 0, time: t, headDX: move, gripDX: -0.04))
        }
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
            (8.40, 0.005 * bodyScale, 0),  // still at address (still sample 1)
            (8.53, 0.010 * bodyScale, 0),  // still at address (still sample 2, < 1.1%)
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

    func testTakeawayStartReturnsNilWhenAlreadyMovingAtFirstSample() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        // No still baseline after P1: club is already displaced on sample 0.
        let alreadyMoving = buildTrackEvidence(clubheadMoves: [
            (8.13, 0.025 * bodyScale, 0),
            (8.27, 0.035 * bodyScale, 0),
            (8.40, 0.045 * bodyScale, 0),
            (8.53, 0.055 * bodyScale, 0),
            (8.67, 0.065 * bodyScale, 0),
        ])
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: alreadyMoving))
        XCTAssertNil(
            CoachingCheckpointTiming.takeawayStart(geometry: geometry, modelTimes: [1: 8.0, 2: 11.2]),
            "Must not fall back to P1+17ms when there is no still baseline after P1"
        )
    }

    func testTakeawayStartReturnsNilWhenAddressShaftHasNoDetectedClubhead() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        // Address frame has a shaft box only (no clubhead detection): comparing box corner
        // against tracked clubhead centres would invent fake displacement.
        let noHead = buildTrackEvidence(clubheadMoves: [
            (8.27, 0.004 * bodyScale, 0),
            (8.40, 0.005 * bodyScale, 0),
            (8.53, 0.010 * bodyScale, 0),
            (8.67, 0.020 * bodyScale, 0),
            (8.80, 0.030 * bodyScale, 0),
            (8.93, 0.045 * bodyScale, 0),
        ], addressHasClubhead: false)
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: noHead))
        XCTAssertNil(CoachingCheckpointTiming.takeawayStart(geometry: geometry, modelTimes: [1: 8.0, 2: 11.2]))
    }

    func testTakeawayStartSkipsWaggleThatReturnsToStillAndResistsForeshorteningDip() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        // Golfer stands still, waggles out to 4% for 4 samples, returns to still at address
        // (< 1.1% for 2 samples), then starts the real takeaway at 9.80 (halfway 9.73..9.87),
        // followed by a brief single-sample DTL foreshortening dip to 1.2% at 10.40.
        let withWaggle = buildTrackEvidence(clubheadMoves: [
            (8.13, 0.003 * bodyScale, 0),  // still
            (8.27, 0.004 * bodyScale, 0),  // still
            (8.40, 0.025 * bodyScale, 0),  // waggle starts
            (8.53, 0.040 * bodyScale, 0),
            (8.67, 0.035 * bodyScale, 0),
            (8.80, 0.020 * bodyScale, 0),
            (9.40, 0.006 * bodyScale, 0),  // returned to still at address (1)
            (9.60, 0.004 * bodyScale, 0),  // returned to still at address (2)
            (9.73, 0.010 * bodyScale, 0),  // just under 1.5%
            (9.87, 0.020 * bodyScale, 0),  // real takeaway crosses 1.5% at 9.80
            (10.00, 0.035 * bodyScale, 0),
            (10.13, 0.050 * bodyScale, 0),
            (10.40, 0.012 * bodyScale, 0), // brief DTL foreshortening dip (> 1.1%, must not reset)
            (10.53, 0.040 * bodyScale, 0),
            (10.67, 0.080 * bodyScale, 0),
            (10.80, 0.120 * bodyScale, 0),
        ])
        let geometry = try XCTUnwrap(CoachingSwingGeometry(evidence: withWaggle))
        let start = try XCTUnwrap(CoachingCheckpointTiming.takeawayStart(
            geometry: geometry, modelTimes: [1: 8.0, 2: 11.2]
        ))
        XCTAssertEqual(start, 9.80, accuracy: 0.005, "Must skip the waggle and stay locked across the foreshortening dip")
    }

    func testTakeawayStartReturnsNilWhenClubNeverLeavesAddressOrTrackIsTooShort() throws {
        let bodyScale = hypot(0.05, 0.16) + 0.30
        let still = buildTrackEvidence(clubheadMoves: [
            (8.2, 0.005 * bodyScale, 0),
            (8.4, 0.008 * bodyScale, 0),
            (8.6, 0.010 * bodyScale, 0),
            (8.8, 0.006 * bodyScale, 0),
            (9.0, 0.005 * bodyScale, 0),
        ])
        let stillGeometry = try XCTUnwrap(CoachingSwingGeometry(evidence: still))
        XCTAssertNil(CoachingCheckpointTiming.takeawayStart(geometry: stillGeometry, modelTimes: [1: 8.0, 2: 11.2]))

        let tooFew = buildTrackEvidence(clubheadMoves: [
            (8.4, 0.004 * bodyScale, 0),
            (8.6, 0.03 * bodyScale, 0),
            (8.8, 0.04 * bodyScale, 0),
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

    func testSessionTrendComputesMediansExcludesUnsureAndExcludedAndAttributesDirection() throws {
        func tempo(back: Double, down: Double, low: Bool = false) -> SwingTempo {
            SwingTempo(backswingMilliseconds: back, downswingMilliseconds: down,
                       isLowConfidence: low, takeawayStartClipTime: 8.5)
        }

        // Backswing lengthens 700/750 -> 800/850 ms (+100 ms >= 60 ms), downswing steady 250 ms.
        // Ratio shifts 2.9 -> 3.3 (+0.4 >= 0.4) -> .longerBackswing.
        let entries: [(id: UUID, tempo: SwingTempo?, excluded: Bool)] = [
            (UUID(), tempo(back: 700, down: 250), false),        // 2.8:1
            (UUID(), tempo(back: 750, down: 250), false),        // 3.0:1
            (UUID(), tempo(back: 400, down: 250, low: true), false),  // low confidence -> excluded
            (UUID(), tempo(back: 500, down: 250), true),              // chip/excluded -> excluded
            (UUID(), nil, false),                                      // missing -> excluded
            (UUID(), tempo(back: 800, down: 250), false),        // 3.2:1
            (UUID(), tempo(back: 850, down: 250), false),        // 3.4:1
        ]
        let trend = SwingTempoTrend.build(from: entries)
        XCTAssertEqual(trend.totalSwings, 7)
        XCTAssertEqual(trend.samples.count, 4)
        XCTAssertEqual(trend.samples.map(\.swingNumber), [1, 2, 6, 7])
        XCTAssertEqual(try XCTUnwrap(trend.medianRatio), 3.1, accuracy: 1e-6)
        XCTAssertEqual(trend.medianRatioText, "3.1:1")
        XCTAssertEqual(trend.medianBackswingMS, 775)
        XCTAssertEqual(trend.medianDownswingMS, 250)
        XCTAssertEqual(trend.direction, .longerBackswing)
        XCTAssertEqual(trend.direction?.label, "Longer backswing")

        // Steady backswing (750 ms) with quicker downswing (280 -> 230 ms, -50 ms >= 40 ms;
        // ratio 2.68 -> 3.26, +0.58 >= 0.4) must read "Quicker downswing", never "Longer backswing".
        let downswingQuicker = SwingTempoTrend.build(from: [
            (UUID(), tempo(back: 750, down: 280), false),
            (UUID(), tempo(back: 750, down: 280), false),
            (UUID(), tempo(back: 750, down: 230), false),
            (UUID(), tempo(back: 750, down: 230), false),
        ])
        XCTAssertEqual(downswingQuicker.direction, .quickerDownswing)
        XCTAssertEqual(downswingQuicker.direction?.label, "Quicker downswing")

        // Steady backswing (750 ms) with slower downswing (230 -> 280 ms) -> "Slower downswing".
        let downswingSlower = SwingTempoTrend.build(from: [
            (UUID(), tempo(back: 750, down: 230), false),
            (UUID(), tempo(back: 750, down: 230), false),
            (UUID(), tempo(back: 750, down: 280), false),
            (UUID(), tempo(back: 750, down: 280), false),
        ])
        XCTAssertEqual(downswingSlower.direction, .slowerDownswing)

        // One-slot P4 quantisation shift (+33 ms backswing, -33 ms downswing) stays "Steady".
        let p4OneSlotNoise = SwingTempoTrend.build(from: [
            (UUID(), tempo(back: 720, down: 280), false),
            (UUID(), tempo(back: 720, down: 280), false),
            (UUID(), tempo(back: 753, down: 247), false),
            (UUID(), tempo(back: 753, down: 247), false),
        ])
        XCTAssertEqual(p4OneSlotNoise.direction, .steady)

        // Quicker backswing (820 -> 700 ms, steady 250 ms downswing) -> "Quicker backswing".
        let quicker = SwingTempoTrend.build(from: [
            (UUID(), tempo(back: 820, down: 250), false),
            (UUID(), tempo(back: 800, down: 250), false),
            (UUID(), tempo(back: 700, down: 250), false),
            (UUID(), tempo(back: 680, down: 250), false),
        ])
        XCTAssertEqual(quicker.direction, .quickerBackswing)

        // Too few samples for direction (< 4).
        let short = SwingTempoTrend.build(from: [
            (UUID(), tempo(back: 700, down: 250), false),
            (UUID(), tempo(back: 800, down: 250), false),
            (UUID(), tempo(back: 900, down: 250), false),
        ])
        XCTAssertNil(short.direction)
    }
}
