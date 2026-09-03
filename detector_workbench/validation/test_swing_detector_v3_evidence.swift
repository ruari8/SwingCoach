import CoreGraphics
import Foundation

@main
struct EvidenceRegression {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ value: Bool) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures.append(name) }
        }

        // Reflect and translate the same physical relationship. No screen region
        // should determine which club belongs to the golfer.
        for mirrored in [false, true] {
            for shift in [0.0, -0.12] {
                func move(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: mirrored ? 1 - point.x : point.x, y: point.y + shift)
                }
                let target = move(CGPoint(x: 0.6, y: 0.7))
                let lock = makeLock(target)
                let wrists = [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.4, y: 0.25), CGPoint(x: 0.42, y: 0.52)]
                let heads = [CGPoint(x: 0.6, y: 0.7), CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.6, y: 0.7)]
                func frames(distractor: Bool, missingReturnHead: Bool = false) -> [SwingObservationV3] {
                    zip(wrists, heads).enumerated().map { index, pair in
                        let wrist = move(pair.0), head = move(pair.1)
                        var boxes = [shaft(wrist, head)]
                        if !(missingReturnHead && index == 2) { boxes.append(box(.clubhead, head, confidence: 0.65)) }
                        if distractor { boxes.append(box(.clubhead, move(CGPoint(x: 0.95, y: 0.9)), confidence: 0.99)) }
                        return observation(Double(index) * 0.3, boxes, wrist: wrist)
                    }
                }
                let tracker = ClubTrackerV3()
                let clean = tracker.evidence(in: frames(distractor: false)[...], lock: lock)
                let distracted = tracker.evidence(in: frames(distractor: true)[...], lock: lock)
                let hiddenHead = tracker.evidence(in: frames(distractor: true, missingReturnHead: true)[...], lock: lock)
                check("clean club sequence mirror=\(mirrored) shift=\(shift)", clean.swingSequenceScore > 0)
                check("unrelated clubhead cannot erase sequence mirror=\(mirrored) shift=\(shift)",
                      distracted.swingSequenceScore > 0)
                check("visible shaft supports hidden clubhead mirror=\(mirrored) shift=\(shift)",
                      hiddenHead.swingSequenceScore > 0)
            }
        }

        let target = CGPoint(x: 0.6, y: 0.7)
        let lock = makeLock(target)
        let motion = ClubEvidenceV3(clubNearPatch: 1, clubSpeedNearPatch: 1,
                                   takeawayScore: 1, sweepScore: 1, arcScore: 1, swingSequenceScore: 1)
        func drive(post: (Int) -> [GolfObjectDetection]) -> [ResolvedSwingCandidateV3] {
            let engine = SwingDecisionEngineV3(configuration: .live())
            var resolved: [ResolvedSwingCandidateV3] = []
            for index in 0..<20 {
                let boxes = index < 2 ? [box(.golfBallCandidate, target)] : post(index)
                let frame = observation(Double(index) * 0.1, boxes)
                let patch = TargetRegionObserverV3.observe(frame: frame, lock: lock)
                if let event = engine.update(frame: frame, lock: lock, patch: patch, club: motion) {
                    resolved.append(event)
                }
            }
            return resolved
        }
        check("club-covered ball cannot resolve after timeout", drive { _ in [box(.clubhead, target)] }.isEmpty)
        check("visible ball during practice does not resolve", drive { _ in [box(.golfBallCandidate, target)] }.isEmpty)
        check("temporary cover then ball return does not resolve", drive { index in
            [box(index < 7 ? .clubhead : .golfBallCandidate, target)]
        }.isEmpty)
        check("clear departure resolves", !drive { _ in [] }.isEmpty)
        check("brief impact occlusion then clear departure resolves", !drive { index in
            index < 4 ? [box(.clubhead, target)] : []
        }.isEmpty)

        print("\(failures.count) failed checks")
        if !failures.isEmpty { exit(1) }
    }

    static func box(_ kind: GolfObjectClass, _ center: CGPoint, confidence: Double = 0.9) -> GolfObjectDetection {
        GolfObjectDetection(objectClass: kind, confidence: confidence,
                            rect: CGRect(x: center.x - 0.01, y: center.y - 0.01, width: 0.02, height: 0.02))
    }

    static func shaft(_ wrist: CGPoint, _ head: CGPoint) -> GolfObjectDetection {
        GolfObjectDetection(objectClass: .clubShaft, confidence: 0.9,
                            rect: CGRect(x: min(wrist.x, head.x), y: min(wrist.y, head.y),
                                         width: max(0.01, abs(head.x - wrist.x)),
                                         height: max(0.01, abs(head.y - wrist.y))))
    }

    static func observation(_ time: Double, _ boxes: [GolfObjectDetection],
                            wrist: CGPoint = CGPoint(x: 0.4, y: 0.5)) -> SwingObservationV3 {
        SwingObservationV3(realTime: time, sourceTime: time, detections: boxes,
                           humanPoseConfidence: 1, handHeight: nil, wristPoint: wrist,
                           torsoHeight: 0.15, lumaMotion: 0)
    }

    static func makeLock(_ point: CGPoint) -> TargetLockV3 {
        TargetLockV3(patchRect: CGRect(x: point.x - 0.025, y: point.y - 0.025, width: 0.05, height: 0.05),
                     ballCenter: point, lockedAtReal: 0, stabilityScore: 1,
                     clubAssociationScore: 1, revision: 0, selectionReason: "test_address",
                     currentClubheadAssociationScore: 1, endpointCouplingScore: 1,
                     ballConfidence: 1, addressBallCount: 1)
    }
}
