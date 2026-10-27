import XCTest
@testable import SwingCoach

final class SwingPositionsTests: XCTestCase {
    private func pose(hip: SIMD2<Float>, shoulderLift: Float, wrist: SIMD2<Float>) -> SwingPositionPose {
        var pose = SwingPositionPose(xy: Array(repeating: .zero, count: 19), confidence: Array(repeating: 0, count: 19))
        for (joint, point) in [(6, hip + [-0.05, -shoulderLift]), (7, hip + [0.05, -shoulderLift]),
                               (13, hip + [-0.05, 0]), (14, hip + [0.05, 0]), (10, wrist)] {
            pose.xy[joint] = point
            pose.confidence[joint] = 0.9
        }
        return pose
    }

    func testFeaturesCentreOnHipsScaleByMedianTorsoAndZeroMissingFrames() {
        let grid: [SwingPositionPose?] = [
            pose(hip: [0.5, 0.6], shoulderLift: 0.2, wrist: [0.6, 0.6]),
            nil,
            pose(hip: [0.5, 0.6], shoulderLift: 0.4, wrist: [0.5, 0.2]),
        ]
        let f = SwingPositionFeatures.build(grid)
        let n = SwingPositionFeatures.featureCount
        XCTAssertEqual(f.count, 3 * n)

        // Median torso of 0.2 and 0.4 is 0.3; the wrist (joint 10) sits 0.1
        // right of the mid-hip on frame 0.
        XCTAssertEqual(f[20], 0.1 / 0.3, accuracy: 1e-6)
        XCTAssertEqual(f[21], 0, accuracy: 1e-6)
        XCTAssertEqual(f[38 + 10], 0.9, accuracy: 1e-6)
        XCTAssertEqual(f[95], 1)
        XCTAssertEqual(f[57 + 20], 0, "row 0 has no velocity")

        // No body: position, confidence and the body flag are zero; velocity
        // into and out of the row is measured against those zeros, as in
        // training.
        XCTAssertTrue(f[n..<(n + 57)].allSatisfy { $0 == 0 })
        XCTAssertEqual(f[n + 95], 0)
        XCTAssertEqual(f[n + 57 + 20], -0.1 / 0.3, accuracy: 1e-6)
        XCTAssertEqual(f[2 * n + 57 + 21], f[2 * n + 21], accuracy: 1e-6)
        XCTAssertEqual(f[2 * n + 21], -0.4 / 0.3, accuracy: 1e-6)

        // Club and view channels stay zero for the pose-only DTL model.
        for t in 0..<3 {
            XCTAssertTrue(f[(t * n + 96)..<((t + 1) * n)].allSatisfy { $0 == 0 })
        }
    }

    func testDecoderPicksPeaksInOrderAndKeepsTheEarliestTie() {
        let frames = 30
        func logits(peaks: [Int]) -> [Float] {
            var l = [Float](repeating: -5, count: frames * 10)
            for (p, t) in peaks.enumerated() { l[t * 10 + p] = 5 }
            return l
        }
        let peaks = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
        XCTAssertEqual(SwingPositionFeatures.decode(logits: logits(peaks: peaks), frameCount: frames), peaks)

        // P3's peak falls before P2's; the decoder must still return
        // strictly increasing frames.
        let decoded = SwingPositionFeatures.decode(logits: logits(peaks: [2, 9, 6, 11, 14, 17, 20, 23, 26, 29]), frameCount: frames)!
        XCTAssertEqual(decoded, decoded.sorted())
        XCTAssertEqual(Set(decoded).count, 10)

        // Flat logits: every position takes the earliest frame it can.
        XCTAssertEqual(SwingPositionFeatures.decode(logits: Array(repeating: 0, count: frames * 10), frameCount: frames),
                       Array(0..<10))
        XCTAssertNil(SwingPositionFeatures.decode(logits: Array(repeating: 0, count: 90), frameCount: 9))
    }

    func testPositionTimesStayInsideTheClip() {
        // 24 s clip at 8x: 90 slots, first frame at 0.1 s, last at 24.05 s.
        let playable = 0.1...24.05
        func time(_ position: Int, _ slot: Int) -> Double {
            SwingPositionAnalyzer.clipTime(position: position, slot: slot, timeScale: 8, playable: playable)
        }
        XCTAssertEqual(time(6, 45), 0.1 + 45.0 / 30 * 8, accuracy: 1e-9, "middle positions are uncorrected")
        XCTAssertEqual(time(0, 30), 0.1 + 28.6 / 30 * 8, accuracy: 1e-9, "P1 moves 1.4 slots earlier")
        XCTAssertEqual(time(0, 0), 0.1, "P1 at slot 0 stays on the first frame")
        XCTAssertEqual(time(9, 60), 0.1 + 61.8 / 30 * 8, accuracy: 1e-9, "P10 moves 1.8 slots later")
        XCTAssertEqual(time(9, 89), 24.05, "P10 at the last slot stays on the last frame")
    }

    @MainActor
    func testSavedSwingDecodesWithoutPositionsAndRoundTripsThem() throws {
        let legacy = """
        {"id":"0CF6A785-0D68-4644-A9C6-DD176A6556D3","photoAssetID":"","vantage":"DTL","duration":23.2,
         "createdAt":0,"analyzed":false}
        """
        var swing = try JSONDecoder().decode(SavedSwing.self, from: Data(legacy.utf8))
        XCTAssertNil(swing.sourceTimeScale)
        XCTAssertNil(swing.swingPositions)
        XCTAssertFalse(SwingPositionProcessor.canFindPositions(for: swing), "imports have no known time scale")

        swing.sourceTimeScale = 8
        swing.swingPositions = SwingPositions(model: SwingPositions.currentModel, positions: (1...10).map {
            SwingPosition(number: $0, clipTime: Double($0), confidence: 0.8)
        })
        XCTAssertTrue(SwingPositionProcessor.canFindPositions(for: swing))
        let decoded = try JSONDecoder().decode(SavedSwing.self, from: JSONEncoder().encode(swing))
        XCTAssertEqual(decoded, swing)
        XCTAssertEqual(decoded.swingPositions?.positions[6].name, "Impact")
    }
}
