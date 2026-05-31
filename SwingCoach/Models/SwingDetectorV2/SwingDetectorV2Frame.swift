//
//  SwingDetectorV2Frame.swift
//  SwingCoach
//
//  One sampled frame's worth of evidence, in real-time seconds.
//

import CoreGraphics
import Foundation

nonisolated struct FrameSampleV2 {
    let realTime: Double
    let sourceTime: Double
    let detections: [GolfObjectDetection]
    /// Mean absolute luma difference vs the previous sampled frame, 0...1.
    let lumaMotion: Double

    var clubBoxes: [GolfObjectDetection] {
        detections.filter { $0.objectClass == .clubhead || $0.objectClass == .clubShaft }
    }

    var clubheads: [GolfObjectDetection] {
        detections.filter { $0.objectClass == .clubhead }
    }

    var balls: [GolfObjectDetection] {
        detections.filter { $0.objectClass == .golfBallCandidate }
    }

    var bestClubScore: Double {
        clubBoxes.map(\.confidence).max() ?? 0
    }

    var bestClubPoint: CGPoint? {
        if let clubhead = clubheads.max(by: { $0.confidence < $1.confidence }) {
            return clubhead.center
        }
        return clubBoxes.max { $0.confidence < $1.confidence }?.center
    }
}

nonisolated enum GeometryV2 {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Shortest distance from a point to a rect (0 if inside), in normalized units.
    static func distance(from point: CGPoint, to rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return Double((dx * dx + dy * dy).squareRoot())
    }

    /// Shortest distance between two rects (0 if intersecting), in normalized units.
    static func distance(between lhs: CGRect, and rhs: CGRect) -> Double {
        if lhs.intersects(rhs) {
            return 0
        }
        let dx = max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX, 0)
        let dy = max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY, 0)
        return Double((dx * dx + dy * dy).squareRoot())
    }

    /// Smoothly ramp a value across [low, high] into 0...1.
    static func ramp(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else { return value >= high ? 1 : 0 }
        return min(1, max(0, (value - low) / (high - low)))
    }

    /// Same as ramp but inverted: 1 when value <= low, 0 when value >= high.
    static func inverseRamp(_ value: Double, low: Double, high: Double) -> Double {
        1 - ramp(value, low: low, high: high)
    }
}
