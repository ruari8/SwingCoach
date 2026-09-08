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
                let clean = ClubTrackerV3.evidence(in: frames(distractor: false)[...], lock: lock)
                let distracted = ClubTrackerV3.evidence(in: frames(distractor: true)[...], lock: lock)
                let hiddenHead = ClubTrackerV3.evidence(in: frames(distractor: true, missingReturnHead: true)[...], lock: lock)
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

        do {
            let url = URL(fileURLWithPath: "detector_workbench/validation/fixtures/2026-09-04-duplicate-swing-observations.json")
            let frames = try JSONDecoder().decode([RecordedObservation].self, from: Data(contentsOf: url))
            func replay(practice: Bool, ballVisible: Bool = true, repeats: Int = 1, occludesTarget: Bool = false) throws -> [DetectedSwing] {
                let detector = SwingDetectorV3(configuration: .live(allowsPracticeSwings: practice))
                var exportedIDs: Set<UUID> = []
                var exports: [DetectedSwing] = []
                for repetition in 0..<repeats {
                    for frame in frames {
                        detector.processObservation(try frame.observation(offset: Double(repetition) * 8, ballVisible: ballVisible, occludesTarget: occludesTarget))
                        for detection in detector.currentDetections() where exportedIDs.insert(detection.id).inserted {
                            exports.append(detection)
                        }
                    }
                }
                return exports
            }
            let both = try replay(practice: true)
            let contact = try replay(practice: false)
            check("one range swing offers exactly one Auto export with practice enabled (got \(both.count))", both.count == 1)
            check("contact confirmation keeps its impact, declaration, and confidence",
                  both.count == 1 && both.first?.impactTime == contact.first?.impactTime
                  && both.first?.declaredAt == contact.first?.declaredAt
                  && both.first?.confidence == contact.first?.confidence)
            let occluded = try replay(practice: true, occludesTarget: true)
            check("unresolved contact still falls back to practice after its deadline",
                  occluded.count == 1 && (occluded.first?.declaredAt ?? 0) >= 32.28)
            check("contact-only mode retains the same swing", contact.count == 1)
            check("ball-free full swing remains capturable", try replay(practice: true, ballVisible: false).count == 1)
            check("contact-only mode excludes the ball-free swing", try replay(practice: false, ballVisible: false).isEmpty)
            check("two successive range swings offer two Auto exports", try replay(practice: true, repeats: 2).count == 2)
        } catch {
            check("load duplicate-swing observation fixture: \(error)", false)
        }

        do {
            // Exact Mac model/pose observations from the September 6 Auto exports.
            // Source playback is 8x real movement time. Exercise both acceptance modes.
            for name in ["fp_auto_swing_C066ED04", "auto_swing_07BCC95D",
                         "auto_swing_129C3634", "auto_swing_1F843DE5"] {
                let url = URL(fileURLWithPath: "detector_workbench/validation/fixtures/\(name)-observations.json")
                let frames = try JSONDecoder().decode([RecordedObservation].self, from: Data(contentsOf: url))
                for practice in [false, true] {
                    let detector = SwingDetectorV3(configuration: .live(sourceTimeScale: 8, allowsPracticeSwings: practice))
                    for frame in frames {
                        detector.processObservation(try frame.observation(offset: 0, ballVisible: true, occludesTarget: false))
                    }
                    let expected = name.hasPrefix("fp_") ? 0 : 1
                    check("range export \(name), practice=\(practice), expected=\(expected), got=\(detector.currentDetections().count)",
                          detector.currentDetections().count == expected)
                }
            }
        } catch {
            check("load September 6 observation fixtures: \(error)", false)
        }

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

// Model/pose observations from the user's 2026-09-04 continuous range recording.
// Keep inference out of the regression, but exercise the production contact and
// practice paths together and consume incremental detections as Auto does.
private struct RecordedObservation: Decodable {
    let realTime: Double
    let sourceTime: Double
    let poseConfidence: Double
    let wristX: Double?
    let wristY: Double?
    let torsoHeight: Double?
    let handHeight: Double?
    let lumaMotion: Double
    let objects: [RecordedObject]

    func observation(offset: Double, ballVisible: Bool, occludesTarget: Bool) throws -> SwingObservationV3 {
        let wrist = wristX.flatMap { x in wristY.map { CGPoint(x: x, y: $0) } }
        var boxes = try objects.map { object -> GolfObjectDetection in
            guard let kind = GolfObjectClass.allCases.first(where: { $0.name == object.kind }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown golf object: \(object.kind)"))
            }
            return GolfObjectDetection(
                objectClass: kind,
                confidence: object.confidence,
                rect: CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            )
        }.filter { ballVisible || $0.objectClass != .golfBallCandidate }
        if occludesTarget, realTime >= 31.93 {
            // Cover the fixture's locked target before five absence samples can arrive.
            boxes.append(GolfObjectDetection(objectClass: .clubhead, confidence: 0.9,
                                             rect: CGRect(x: 0.5847, y: 0.7084, width: 0.02, height: 0.02)))
        }
        return SwingObservationV3(realTime: realTime + offset, sourceTime: sourceTime + offset,
                                  detections: boxes, humanPoseConfidence: poseConfidence,
                                  handHeight: handHeight, wristPoint: wrist,
                                  torsoHeight: torsoHeight, lumaMotion: lumaMotion)
    }
}

private struct RecordedObject: Decodable {
    let kind: String
    let confidence: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
