//
//  ClubTracker.swift
//  SwingCoach
//
//  Tracks the clubhead/shaft relative to the locked patch and emits CONTINUOUS
//  evidence — never booleans (a hidden threshold inside a component would just
//  relocate the OR-branch problem one level down).
//
//  The takeaway signal is direction-agnostic: DTL vs face-on and left- vs
//  right-handed golfers flip "up and back", so takeaway is measured as the club
//  leaving the patch and accelerating, not a specific screen direction.
//
//  First implementation target: graded proximity, speed, takeaway, sweep, and
//  arc scores from the recent sampled-frame window.
//

import CoreGraphics
import Foundation

nonisolated struct ClubEvidence: Equatable {
    var clubNearPatch: Double = 0
    var clubSpeedNearPatch: Double = 0
    var takeawayScore: Double = 0
    var sweepScore: Double = 0
    var arcScore: Double = 0
    var swingSequenceScore: Double = 0
}

nonisolated final class ClubTracker {
    func reset() {}

    func update(frame: FrameSampleV2, lock: AddressLock?) {
        // Stateless in v1. Evidence is computed from the supplied frame window.
    }

    /// Evidence over a real-time window [start, end] of the recent buffer.
    func evidence(
        in window: ArraySlice<FrameSampleV2>,
        lock: AddressLock?
    ) -> ClubEvidence {
        guard let lock, !window.isEmpty else { return ClubEvidence() }

        var bestNear = 0.0
        var bestSpeedNear = 0.0
        var points: [(time: Double, point: CGPoint)] = []
        var clubFrameCount = 0
        var maxLumaMotion = 0.0

        for frame in window {
            maxLumaMotion = max(maxLumaMotion, frame.lumaMotion)
            if let point = frame.bestClubPoint {
                points.append((frame.realTime, point))
            }

            var frameNear = 0.0
            for box in frame.clubBoxes where box.confidence >= 0.25 {
                let distance = GeometryV2.distance(between: box.rect, and: lock.patchRect)
                let proximity = GeometryV2.inverseRamp(distance, low: 0.0, high: 0.16)
                let confidence = GeometryV2.ramp(box.confidence, low: 0.25, high: 0.82)
                frameNear = max(frameNear, proximity * (0.55 + 0.45 * confidence))
            }
            if frameNear > 0 {
                clubFrameCount += 1
            }
            bestNear = max(bestNear, frameNear)
        }

        if points.count >= 2 {
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let dt = current.time - previous.time
                guard dt > 0, dt <= 0.85 else { continue }
                let speed = GeometryV2.distance(previous.point, current.point) / dt
                let speedScore = GeometryV2.ramp(speed, low: 0.05, high: 0.34)
                let nearPatch = max(
                    GeometryV2.inverseRamp(GeometryV2.distance(previous.point, lock.ballCenter), low: 0.0, high: 0.22),
                    GeometryV2.inverseRamp(GeometryV2.distance(current.point, lock.ballCenter), low: 0.0, high: 0.22)
                )
                bestSpeedNear = max(bestSpeedNear, speedScore * max(0.25, nearPatch))
            }
        }

        let pointValues = points.map(\.point)
        let pathSpan = Self.pathSpan(pointValues)
        let verticalSpan = Self.verticalSpan(pointValues)
        let pathScore = GeometryV2.ramp(pathSpan, low: 0.06, high: 0.36)
        let verticalScore = GeometryV2.ramp(verticalSpan, low: 0.08, high: 0.34)
        let swingShapeScore = min(1, pathScore * max(0.15, verticalScore))
        let sequenceScore = Self.nearAwayNearSequence(points, ballCenter: lock.ballCenter)
        let lumaScore = GeometryV2.ramp(maxLumaMotion, low: 0.006, high: 0.050)
        let clubCoverage = Double(clubFrameCount) / Double(max(1, window.count))
        let coverageScore = GeometryV2.ramp(clubCoverage, low: 0.05, high: 0.30)

        let addressAssociation = max(0.35, min(1, bestNear + coverageScore))
        let takeawayScore = min(1, (swingShapeScore * 0.82 + lumaScore * 0.18) * addressAssociation)
        let sweepScore = min(1, (bestNear * 0.62 + bestSpeedNear * 0.38) * max(0.30, swingShapeScore))
        let arcScore = min(1, swingShapeScore * 0.82 + coverageScore * 0.10 + lumaScore * 0.08)

        return ClubEvidence(
            clubNearPatch: bestNear,
            clubSpeedNearPatch: bestSpeedNear,
            takeawayScore: takeawayScore,
            sweepScore: sweepScore,
            arcScore: arcScore,
            swingSequenceScore: sequenceScore
        )
    }

    private static func pathSpan(_ points: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width * width + height * height).squareRoot()
    }

    private static func verticalSpan(_ points: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        let ys = points.map(\.y)
        return Double((ys.max() ?? 0) - (ys.min() ?? 0))
    }

    private static func nearAwayNearSequence(
        _ points: [(time: Double, point: CGPoint)],
        ballCenter: CGPoint
    ) -> Double {
        guard points.count >= 3 else { return 0 }

        let samples = points.map { sample in
            let distance = GeometryV2.distance(sample.point, ballCenter)
            return (
                near: GeometryV2.inverseRamp(distance, low: 0.0, high: 0.22),
                away: GeometryV2.ramp(distance, low: 0.16, high: 0.46)
            )
        }

        var prefixNear = Array(repeating: 0.0, count: samples.count)
        var suffixNear = Array(repeating: 0.0, count: samples.count)
        for index in samples.indices {
            prefixNear[index] = max(index > 0 ? prefixNear[index - 1] : 0, samples[index].near)
        }
        for index in samples.indices.reversed() {
            suffixNear[index] = max(index < samples.count - 1 ? suffixNear[index + 1] : 0, samples[index].near)
        }

        var best = 0.0
        for index in 1..<(samples.count - 1) {
            best = max(best, prefixNear[index - 1] * samples[index].away * suffixNear[index + 1])
        }
        return best
    }
}
