//
//  CoachingSwingGeometry.swift
//  SwingCoach
//
//  Turns raw evidence into the points the metrics measure: hands, shaft,
//  clubhead, ball, the golfer's backside and head, for each swing position.
//
//  Works in "height units": x is multiplied by the frame's aspect ratio so
//  one unit is the frame height in both directions and angles are true.
//  Down-the-line only.
//

import Foundation

typealias CoachingVector = SIMD2<Double>

nonisolated extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }

    func distance(to other: SIMD2<Double>) -> Double { (self - other).length }
}

nonisolated struct CoachingShaft {
    /// Top of the visible shaft, where the hands hold it.
    var grip: CoachingVector
    var head: CoachingVector
    /// True when a clubhead detection backs the head end; false when it is
    /// only the far corner of the shaft box.
    var headDetected: Bool
    var confidence: Double

    var length: Double { grip.distance(to: head) }
}

nonisolated struct CoachingSwingGeometry {
    let evidence: SwingCoachingEvidence
    let aspect: Double
    /// +1 when the golfer faces the right of the frame (a right-hander
    /// filmed down the line), -1 when facing left. "Toward the ball" is
    /// `facing` along x.
    let facing: Double
    /// Trail shoulder to hip plus hip to ankle at address, in height units.
    /// Offsets are reported as a share of this, so they don't depend on how
    /// far the golfer stands from the camera.
    let bodyScale: Double
    let ball: CoachingVector?
    private let junkClubheads: [CoachingVector]

    var isRightHanded: Bool { facing > 0 }
    var leadSide: Side { isRightHanded ? .left : .right }
    var trailSide: Side { isRightHanded ? .right : .left }

    enum Side {
        case left, right

        var shoulder: CoachingJoint { self == .left ? .leftShoulder : .rightShoulder }
        var elbow: CoachingJoint { self == .left ? .leftElbow : .rightElbow }
        var wrist: CoachingJoint { self == .left ? .leftWrist : .rightWrist }
        var hip: CoachingJoint { self == .left ? .leftHip : .rightHip }
        var knee: CoachingJoint { self == .left ? .leftKnee : .rightKnee }
        var ankle: CoachingJoint { self == .left ? .leftAnkle : .rightAnkle }
    }

    /// Nil when the address frame lacks the body points every metric needs.
    init?(evidence: SwingCoachingEvidence) {
        self.evidence = evidence
        aspect = evidence.aspect
        guard let address = evidence.frame(1) else { return nil }
        let aspect = aspect
        func vector(_ point: CoachingPoint) -> CoachingVector { CoachingVector(point.x * aspect, point.y) }
        func joint(_ joint: CoachingJoint) -> CoachingVector? { address.joint(joint).map(vector) }

        guard let hipCentre = Self.mean([joint(.leftHip), joint(.rightHip), joint(.root)].compactMap { $0 }) else {
            return nil
        }
        // The club sits on the ball side of the golfer at address.
        let ballSide: Double? = address.shafts.first.map { vector($0.center).x }
            ?? address.clubheads.first.map { vector($0.center).x }
            ?? address.balls.first.map { vector($0.center).x }
            ?? joint(.nose)?.x
        guard let ballSide else { return nil }
        facing = ballSide >= hipCentre.x ? 1 : -1
        let trail: Side = facing > 0 ? .right : .left
        let lead: Side = facing > 0 ? .left : .right

        func legLength(_ side: Side) -> Double? {
            guard let shoulder = joint(side.shoulder), let hip = joint(side.hip), let ankle = joint(side.ankle) else {
                return nil
            }
            return shoulder.distance(to: hip) + hip.distance(to: ankle)
        }
        guard let scale = legLength(trail) ?? legLength(lead), scale > 0.05 else { return nil }
        bodyScale = scale

        // A "clubhead" seen in the same place in most frames is something
        // lying on the range (a bag, a spare club), not the club in motion.
        let everyFrame = evidence.frames + evidence.track
        let allHeads = everyFrame.flatMap { frame in frame.clubheads.map { vector($0.center) } }
        var junk: [CoachingVector] = []
        for head in allHeads where !junk.contains(where: { $0.distance(to: head) < 0.02 }) {
            let framesWithIt = everyFrame.filter { frame in
                frame.clubheads.contains { vector($0.center).distance(to: head) < 0.012 }
            }.count
            if framesWithIt >= max(5, everyFrame.count * 2 / 5) { junk.append(head) }
        }
        junkClubheads = junk

        // The ball is the candidate that stays put through the backswing,
        // nearest to where the club was soled.
        let soled = address.clubheads.map { vector($0.center) }.first { head in
            !junk.contains { $0.distance(to: head) < 0.02 }
        } ?? address.shafts.first.map { box in
            box.corners.map(vector).max { $0.y < $1.y }!
        }
        // Track samples after impact can't add to it: the ball has gone.
        let early = evidence.frames.filter { $0.position <= 5 } + evidence.track
        var clusters: [(centre: CoachingVector, members: [CoachingVector])] = []
        for frame in early {
            for candidate in frame.balls.prefix(4) where candidate.confidence >= 0.3 {
                let point = vector(candidate.center)
                if let index = clusters.firstIndex(where: { $0.centre.distance(to: point) < 0.012 }) {
                    clusters[index].members.append(point)
                } else {
                    clusters.append((point, [point]))
                }
            }
        }
        let steady = clusters.filter { $0.members.count >= 3 }
        var chosen: [CoachingVector]?
        if let soled {
            chosen = steady.filter { $0.centre.distance(to: soled) < 0.3 * scale }
                .min { $0.centre.distance(to: soled) < $1.centre.distance(to: soled) }?.members
        } else {
            chosen = steady.max { $0.members.count < $1.members.count }?.members
        }
        ball = chosen.flatMap(Self.mean)
    }

    // MARK: - Points

    func vector(_ point: CoachingPoint) -> CoachingVector {
        CoachingVector(point.x * aspect, point.y)
    }

    /// Back to normalized frame coordinates, for drawing.
    func point(_ vector: CoachingVector, confidence: Double = 1) -> CoachingPoint {
        CoachingPoint(x: vector.x / aspect, y: vector.y, confidence: confidence)
    }

    func joint(_ joint: CoachingJoint, at position: Int, minimumConfidence: Double = 0.3) -> CoachingVector? {
        evidence.frame(position).flatMap { self.joint(joint, in: $0, minimumConfidence: minimumConfidence) }
    }

    func joint(_ joint: CoachingJoint, in frame: CoachingFrameEvidence, minimumConfidence: Double = 0.3) -> CoachingVector? {
        frame.joint(joint, minimumConfidence: minimumConfidence).map(vector)
    }

    func hipCentre(at position: Int) -> CoachingVector? {
        Self.mean([joint(.leftHip, at: position), joint(.rightHip, at: position), joint(.root, at: position)]
            .compactMap { $0 })
    }

    func shoulderCentre(at position: Int) -> CoachingVector? {
        joint(.neck, at: position)
            ?? Self.mean([joint(.leftShoulder, at: position), joint(.rightShoulder, at: position)].compactMap { $0 })
    }

    /// Midpoint of the wrists when Vision is sure of both.
    func wrists(at position: Int) -> CoachingVector? {
        evidence.frame(position).flatMap(wrists(in:))
    }

    func wrists(in frame: CoachingFrameEvidence) -> CoachingVector? {
        guard let lead = joint(leadSide.wrist, in: frame), let trail = joint(trailSide.wrist, in: frame) else {
            return nil
        }
        return (lead + trail) / 2
    }

    /// Where the hands roughly are, however unsure: used only to tell the
    /// grip end of the shaft from the head end.
    private func handsHint(in frame: CoachingFrameEvidence) -> CoachingVector? {
        let wrists = [leadSide.wrist, trailSide.wrist].compactMap { joint($0, in: frame, minimumConfidence: 0.05) }
        if let hint = Self.mean(wrists) { return hint }
        let elbows = [leadSide.elbow, trailSide.elbow].compactMap { joint($0, in: frame, minimumConfidence: 0.15) }
        if let hint = Self.mean(elbows) { return hint }
        return joint(.neck, in: frame)
            ?? Self.mean([joint(.leftShoulder, in: frame), joint(.rightShoulder, in: frame)].compactMap { $0 })
    }

    private func isJunk(_ head: CoachingVector) -> Bool {
        junkClubheads.contains { $0.distance(to: head) < 0.02 }
    }

    /// The club at a position. Where the frame itself doesn't show the
    /// clubhead (a level shaft points at the camera), the club track around
    /// that moment fills in.
    func shaft(at position: Int) -> CoachingShaft? {
        guard let frame = evidence.frame(position) else { return nil }
        let seen = shaft(in: frame)
        if let seen, seen.headDetected { return seen }
        // A shaft box on the frame itself, even without its clubhead, beats
        // a shaky line drawn between track samples.
        guard let tracked = trackedShaft(atTime: frame.clipTime) else { return seen }
        guard let seen else { return tracked }
        return tracked.confidence > seen.confidence ? tracked : seen
    }

    /// How far the feet appear to move between address and the top, as a
    /// share of body scale. Both feet are planted until then, so more than
    /// joint jitter (about 5%) means the camera moved or zoomed.
    var footShiftAtTop: Double? {
        let shifts = [CoachingJoint.leftAnkle, .rightAnkle].compactMap { ankle -> Double? in
            guard let address = joint(ankle, at: 1), let top = joint(ankle, at: 4) else { return nil }
            return address.distance(to: top) / bodyScale
        }
        return shifts.max()
    }

    /// True when P1 and P7 look like address and impact: the club hangs
    /// down from the hands at address, and the hands at impact are back
    /// near where they started. False on a clip that opens on a rehearsal,
    /// or where impact landed on the follow-through.
    var positionsLookRight: Bool {
        guard let address = shaft(at: 1), address.head.y - address.grip.y > 0.3 * address.length else { return false }
        // Blur often hides the shaft at impact; the wrists will do. With
        // neither, impact can't be told from the follow-through.
        guard let impactHands = shaft(at: 7)?.grip ?? wrists(at: 7),
              impactHands.distance(to: address.grip) <= 0.25 * bodyScale
        else { return false }
        // The top has to be seen to tell a chip from a full swing and a
        // moved camera from a steady one: unknown is not a pass.
        return handsAboveShoulderAtTop != nil && footShiftAtTop != nil
    }

    /// How far above the trail shoulder the hands get at the top, as a share
    /// of body scale. Negative on a chip or pitch.
    var handsAboveShoulderAtTop: Double? {
        guard let hands = wrists(at: 4) ?? hands(at: 4),
              let shoulder = joint(trailSide.shoulder, at: 4) ?? joint(.neck, at: 4)
        else { return nil }
        return (shoulder.y - hands.y) / bodyScale
    }

    /// The club in every track sample that shows its head, in time order,
    /// without the odd detection that jumps away from both its neighbours.
    func trackedShafts() -> [(time: Double, shaft: CoachingShaft)] {
        let seen: [(time: Double, shaft: CoachingShaft)] = evidence.track
            .sorted { $0.clipTime < $1.clipTime }
            .compactMap { sample in
                guard let shaft = shaft(in: sample), shaft.headDetected else { return nil }
                return (sample.clipTime, shaft)
            }
        guard seen.count >= 3 else { return seen }
        let jump = 0.35 * bodyScale
        return seen.enumerated().filter { index, entry in
            guard index > 0, index < seen.count - 1 else { return true }
            let before = seen[index - 1].shaft.head, after = seen[index + 1].shaft.head
            let together = before.distance(to: after) < jump
            let away = entry.shaft.head.distance(to: before) > jump && entry.shaft.head.distance(to: after) > jump
            return !(together && away)
        }.map(\.element)
    }

    /// The club at a clip time, between the track samples either side.
    func trackedShaft(atTime time: Double) -> CoachingShaft? {
        let shafts = trackedShafts()
        // A tenth of a second of real time: further apart than that, the
        // club has moved too far to draw a straight line between samples.
        let reach = 0.1 * evidence.timeScale
        let before = shafts.last { $0.time <= time }
        let after = shafts.first { $0.time >= time }
        switch (before, after) {
        case let (before?, after?):
            guard after.time - before.time <= reach else { return nil }
            let span = after.time - before.time
            let share = span > 1e-9 ? (time - before.time) / span : 0
            // A sample at exactly this time is as good as itself; halfway
            // between two samples is the least sure.
            let between = 1 - abs(2 * share - 1)
            return CoachingShaft(
                grip: before.shaft.grip + share * (after.shaft.grip - before.shaft.grip),
                head: before.shaft.head + share * (after.shaft.head - before.shaft.head),
                headDetected: true,
                confidence: min(before.shaft.confidence, after.shaft.confidence) * (1 - 0.4 * between)
            )
        case let (near?, nil), let (nil, near?):
            // Past the end of the track: only a sample right beside it, and
            // no surer than a midpoint.
            guard abs(near.time - time) <= reach / 4 else { return nil }
            var shaft = near.shaft
            shaft.confidence *= 0.6
            return shaft
        default:
            return nil
        }
    }

    /// The club in one frame: the detector's shaft box gives a diagonal,
    /// the corner nearest the hands is the grip, and a clubhead detection
    /// near the far corner sharpens the head end.
    func shaft(in frame: CoachingFrameEvidence) -> CoachingShaft? {
        guard let hint = handsHint(in: frame) else { return nil }
        let heads = frame.clubheads.map { (vector($0.center), $0.confidence) }.filter { !isJunk($0.0) }

        for box in frame.shafts {
            let corners = box.corners.map(vector)
            guard let grip = corners.min(by: { $0.distance(to: hint) < $1.distance(to: hint) }),
                  grip.distance(to: hint) < 0.3 * bodyScale
            else { continue }
            let far = corners.max { $0.distance(to: grip) < $1.distance(to: grip) }!
            let reach = max(0.35 * grip.distance(to: far), 0.08 * bodyScale)
            if let head = heads.filter({ $0.0.distance(to: far) < reach }).max(by: { $0.1 < $1.1 }) {
                return CoachingShaft(grip: grip, head: head.0, headDetected: true, confidence: min(box.confidence, head.1))
            }
            return CoachingShaft(grip: grip, head: far, headDetected: false, confidence: box.confidence * 0.7)
        }

        // No shaft box: a clubhead within a club's length of confident wrists.
        guard let hands = wrists(in: frame), let clubLength = addressClubLength else { return nil }
        let reachable = heads.filter {
            let distance = $0.0.distance(to: hands)
            return distance > 0.15 * clubLength && distance < 1.25 * clubLength
        }
        guard let head = reachable.max(by: { $0.1 < $1.1 }) else { return nil }
        return CoachingShaft(grip: hands, head: head.0, headDetected: true, confidence: head.1 * 0.7)
    }

    var addressClubLength: Double? {
        guard let frame = evidence.frame(1), let box = frame.shafts.first else { return nil }
        let corners = box.corners.map(vector)
        return corners[0].distance(to: corners[3])
    }

    /// Hands for position-to-position comparisons: the grip end of the shaft
    /// when the club is seen (wrists are hidden at address and impact),
    /// otherwise the wrists.
    func hands(at position: Int) -> CoachingVector? {
        shaft(at: position)?.grip ?? wrists(at: position)
    }

    /// Rearmost point of the golfer's backside: the outline's back edge in
    /// a band around hip height.
    func backside(at position: Int) -> CoachingVector? {
        guard let silhouette = evidence.frame(position)?.silhouette, let hips = hipCentre(at: position) else {
            return nil
        }
        let top = hips.y - 0.04 * bodyScale
        let bottom = hips.y + 0.12 * bodyScale
        var best: CoachingVector?
        for row in silhouette.row(atY: top)...silhouette.row(atY: bottom) {
            let y = silhouette.y(ofRow: row)
            guard let extent = silhouette.extent(atY: y) else { continue }
            let edge = (facing > 0 ? extent.left : extent.right) * aspect
            if best == nil || (edge - best!.x) * facing < 0 {
                best = CoachingVector(edge, y)
            }
        }
        return best
    }

    /// Centre of the face joints both frames share, so a joint Vision drops
    /// in one frame doesn't shift the head.
    func head(at position: Int, sharedWith other: Int) -> (here: CoachingVector, there: CoachingVector)? {
        let faceJoints: [CoachingJoint] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
        let shared = faceJoints.filter { joint($0, at: position) != nil && joint($0, at: other) != nil }
        if !shared.isEmpty,
           let here = Self.mean(shared.compactMap { joint($0, at: position) }),
           let there = Self.mean(shared.compactMap { joint($0, at: other) }) {
            return (here, there)
        }
        guard let here = joint(.neck, at: position), let there = joint(.neck, at: other) else { return nil }
        return (here, there)
    }

    /// True while the ball is still seen on its spot in this frame.
    func ballPresent(in frame: CoachingFrameEvidence) -> Bool {
        guard let ball else { return false }
        return frame.balls.contains { vector($0.center).distance(to: ball) < 0.012 }
    }

    // MARK: - Maths

    static func mean(_ points: [CoachingVector]) -> CoachingVector? {
        guard !points.isEmpty else { return nil }
        return points.reduce(CoachingVector(0, 0), +) / Double(points.count)
    }

    /// Angle of a direction above the horizontal that points away from
    /// the ball, in degrees: 0 is flat back, 90 straight up, past 90 leans
    /// toward the ball, negative points down. Keeping the side lets two
    /// lines leaning opposite ways read as far apart, not the same.
    func angleFromBack(_ vector: CoachingVector) -> Double {
        atan2(-vector.y, -vector.x * facing) * 180 / .pi
    }

    /// The unit vector at that angle.
    func direction(atAngleFromBack degrees: Double) -> CoachingVector {
        let angle = degrees * .pi / 180
        return CoachingVector(-facing * cos(angle), -sin(angle))
    }

    /// Signed distance of `point` from the line a→b; positive is on the
    /// left of the direction of travel.
    static func signedDistance(of point: CoachingVector, fromLine a: CoachingVector, _ b: CoachingVector) -> Double {
        let direction = b - a
        let length = direction.length
        guard length > 1e-9 else { return 0 }
        let offset = point - a
        return (direction.x * offset.y - direction.y * offset.x) / length
    }

    /// x where the line through a and b reaches height y, or nil when the
    /// line is too flat to reach it nearby.
    static func x(ofLine a: CoachingVector, _ b: CoachingVector, atY y: Double) -> Double? {
        let delta = b - a
        guard abs(delta.y) > 1e-6 else { return nil }
        return a.x + (y - a.y) / delta.y * delta.x
    }
}
