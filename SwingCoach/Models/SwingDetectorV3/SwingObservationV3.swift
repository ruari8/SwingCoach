import CoreGraphics
import Foundation

/// Detector-independent facts extracted from one sampled frame. Relationships
/// and decisions are deliberately added by later stages.
nonisolated struct SwingObservationV3 {
    let realTime: Double
    let sourceTime: Double
    let detections: [GolfObjectDetection]
    let humanPoseConfidence: Double
    let handHeight: Double?
    let wristPoint: CGPoint?
    let torsoHeight: Double?
    let lumaMotion: Double

    var clubBoxes: [GolfObjectDetection] { detections.filter { $0.objectClass == .clubhead || $0.objectClass == .clubShaft } }
    var clubheads: [GolfObjectDetection] { detections.filter { $0.objectClass == .clubhead } }
    var balls: [GolfObjectDetection] { detections.filter { $0.objectClass == .golfBallCandidate } }
    var bestClubScore: Double { clubBoxes.map(\.confidence).max() ?? 0 }
    /// The club used for motion evidence must be connected to the golfer.
    /// A class confidence alone does not establish that relationship.
    var heldClub: HeldClubObservationV3? {
        if let wrist = wristPoint, let torso = torsoHeight, torso >= 0.035 {
            let shafts = clubBoxes.filter { $0.objectClass == .clubShaft }
            let anchored = shafts.compactMap { shaft -> (GolfObjectDetection, CGPoint, Double)? in
                let corners = [
                    CGPoint(x: shaft.rect.minX, y: shaft.rect.minY),
                    CGPoint(x: shaft.rect.maxX, y: shaft.rect.minY),
                    CGPoint(x: shaft.rect.minX, y: shaft.rect.maxY),
                    CGPoint(x: shaft.rect.maxX, y: shaft.rect.maxY)
                ]
                guard let grip = corners.min(by: {
                    GeometryV3.distance($0, wrist) < GeometryV3.distance($1, wrist)
                }) else { return nil }
                let distance = GeometryV3.distance(grip, wrist)
                guard distance <= torso else { return nil }
                let tip = CGPoint(x: shaft.rect.minX + shaft.rect.maxX - grip.x,
                                  y: shaft.rect.minY + shaft.rect.maxY - grip.y)
                let support = shaft.confidence / (1 + pow(distance / torso, 2))
                return (shaft, tip, support)
            }
            if let (shaft, tip, _) = anchored.max(by: { $0.2 < $1.2 }) {
                let length = hypot(shaft.rect.width, shaft.rect.height)
                let endpointRadius = max(torso * 0.5, length * 0.3)
                let head = clubheads.filter {
                    GeometryV3.distance($0.center, tip) <= endpointRadius
                }.max {
                    $0.confidence / (1 + GeometryV3.distance($0.center, tip) / endpointRadius)
                        < $1.confidence / (1 + GeometryV3.distance($1.center, tip) / endpointRadius)
                }
                // A visible shaft still supplies its distal end when the small,
                // fast clubhead is blurred or absent from the object detections.
                return HeldClubObservationV3(point: head?.center ?? tip,
                                             boxes: [shaft] + (head.map { [$0] } ?? []))
            }
            // Pose can remain readable when the shaft is not. Keep the same
            // golfer-relative reach used by FullSwingPatternV3, never a fixed
            // region of the image.
            let reachable = clubheads.filter {
                GeometryV3.distance($0.center, wrist) <= 4.5 * torso
            }
            return reachable.max(by: { $0.confidence < $1.confidence }).map {
                HeldClubObservationV3(point: $0.center, boxes: [$0])
            }
        }
        return (clubheads.max(by: { $0.confidence < $1.confidence })
            ?? clubBoxes.max(by: { $0.confidence < $1.confidence })).map {
                HeldClubObservationV3(point: $0.center, boxes: [$0])
            }
    }
}

nonisolated struct HeldClubObservationV3 {
    let point: CGPoint
    let boxes: [GolfObjectDetection]
}

nonisolated struct ObjectObservationTraceV3: Encodable {
    let kind: String
    let confidence: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct FrameObservationTraceV3: Encodable {
    let sourceTime: Double
    let realTime: Double
    let poseConfidence: Double
    let wristX: Double?
    let wristY: Double?
    let torsoHeight: Double?
    let objects: [ObjectObservationTraceV3]
    let ballTracks: [BallTrackV3]
    let selectedTargetID: Int?
}

nonisolated enum GeometryV3 {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
    static func distance(from point: CGPoint, to rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return Double(hypot(dx, dy))
    }
    static func distance(between lhs: CGRect, and rhs: CGRect) -> Double {
        if lhs.intersects(rhs) { return 0 }
        let dx = max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX, 0)
        let dy = max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY, 0)
        return Double(hypot(dx, dy))
    }
    static func ramp(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else { return value >= high ? 1 : 0 }
        return min(1, max(0, (value - low) / (high - low)))
    }
    static func inverseRamp(_ value: Double, low: Double, high: Double) -> Double { 1 - ramp(value, low: low, high: high) }
}
