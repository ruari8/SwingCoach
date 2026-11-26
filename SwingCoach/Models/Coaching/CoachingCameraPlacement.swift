//
//  CoachingCameraPlacement.swift
//  SwingCoach
//
//  Where the camera stood for a down-the-line swing, read off the address
//  frame. The club checks are a flat picture of where the club points, so
//  they only mean the same thing from one swing to the next when the
//  camera looks down the hand line from hand height. This says whether it
//  did; the club checks are judged only when it did.
//
//  Two facts about a picture do the work, with the phone held upright:
//  - Everything at the camera's own height sits on the frame's middle row.
//    So the hands' distance above or below that row is the camera's height
//    below or above the hands.
//  - Lines along the target line meet at one point on that row, and that
//    point is straight ahead of the camera. The feet give one such line:
//    the trail ankle is nearer the camera than the lead ankle. Where the
//    line through them reaches the middle row, against the hands, is how
//    far the camera stands to the side of the hand line.
//
//  Both are shares of body scale, like every other offset. They assume an
//  upright phone and feet square to the target line; nothing here is a
//  measured distance in metres.
//

import Foundation

nonisolated struct CoachingCameraPlacement: Codable, Equatable {
    /// Camera height against the hands at address, as a share of body
    /// scale in percent. Positive is above the hands. Nil when the hands
    /// or the body weren't found at address.
    var heightAboveHands: Double?
    /// The camera's line against the hand line, as a share of body scale
    /// in percent. Positive is toward the ball, negative toward the feet.
    /// Nil when the feet don't give a line.
    var offHandLine: Double?
    /// How far `offHandLine` could be out either way, same unit. The feet
    /// are close together in the picture, so their line is followed a long
    /// way to the middle row and a small slip in an ankle grows with it.
    var lineUncertainty: Double?
    /// Camera to golfer in body scales, from the lens the swing was
    /// recorded with. Nil without lens data.
    var distance: Double?

    /// The camera counts as at hand height within this much, percent of
    /// body scale: about 20 cm on an adult.
    static let heightTolerance = 15.0
    /// And as on the hand line within this much: about 27 cm.
    static let lineTolerance = 20.0
    /// A line reading that could be out by more than this isn't used.
    static let lineUncertaintyLimit = 15.0
    /// Nearer than this many body scales (about 2 m) the club grows and
    /// shrinks in the picture as it swings toward and away from the camera.
    static let nearestDistance = 1.5
    /// Further than this (about 6 m) the golfer is too small to measure.
    /// A camera rarely gets here as "far": the feet's line is followed
    /// about (distance / stance width) times its length, so past 3 to 4 m
    /// the line reading goes over `lineUncertaintyLimit` and the result is
    /// unsure first. This limit catches a far camera with a wide stance.
    static let furthestDistance = 4.5
    /// An ankle joint's wander on a tripod clip, percent of body scale.
    static let ankleNoise = 1.0

    enum Problem: String, Codable, CaseIterable {
        case high, low, towardBall, towardFeet, close, far
    }

    enum Verdict: Equatable {
        /// On the hand line at hand height: the club checks are judged.
        case good
        /// Known to be off, in these ways.
        case off([Problem])
        /// Couldn't be told from this swing's address. Not a pass.
        case unsure
    }

    var verdict: Verdict {
        var problems: [Problem] = []
        if let heightAboveHands, abs(heightAboveHands) > Self.heightTolerance {
            problems.append(heightAboveHands > 0 ? .high : .low)
        }
        let line = lineIsSure ? offHandLine : nil
        if let line, abs(line) > Self.lineTolerance {
            problems.append(line > 0 ? .towardBall : .towardFeet)
        }
        if let distance {
            if distance < Self.nearestDistance { problems.append(.close) }
            if distance > Self.furthestDistance { problems.append(.far) }
        }
        if !problems.isEmpty { return .off(problems) }
        // Height and line both have to be known. Distance is checked when
        // the swing has lens data and passed over when it doesn't.
        return heightAboveHands != nil && line != nil ? .good : .unsure
    }

    /// True when the club checks can be judged.
    var passes: Bool { verdict == .good }

    private var lineIsSure: Bool {
        guard offHandLine != nil, let lineUncertainty else { return false }
        return lineUncertainty <= Self.lineUncertaintyLimit
    }
}

nonisolated extension CoachingCameraPlacement {
    /// The middle row of the frame: the camera's own height on an upright
    /// phone.
    private static let horizon = 0.5

    /// Read off the address frame. `lens` adds the distance.
    init(geometry: CoachingSwingGeometry, lens: CameraLensData? = nil) {
        let scale = geometry.bodyScale
        // The same bar a check has to clear: a shaky shaft at address
        // gives no hands to read the camera from.
        let hands = geometry.shaft(at: 1).flatMap { $0.confidence >= CoachingAnalyzer.minimumConfidence ? $0.grip : nil }
        heightAboveHands = hands.map { ($0.y - Self.horizon) / scale * 100 }

        // The trail ankle is nearer the camera, so from above ankle height
        // it sits lower in the picture than the lead ankle. Without that
        // drop there is no line to follow. Both feet are under the middle
        // row from any camera above the ground; an ankle over it is a slip.
        if let hands,
           let trail = geometry.joint(geometry.trailSide.ankle, at: 1),
           let lead = geometry.joint(geometry.leadSide.ankle, at: 1),
           lead.y > Self.horizon, trail.y - lead.y > 0.02 * scale {
            let reach = (trail.y - Self.horizon) / (trail.y - lead.y)
            let ahead = trail.x + reach * (lead.x - trail.x)
            offHandLine = (ahead - hands.x) * geometry.facing / scale * 100
            // Either ankle can slip `ankleNoise` across the line.
            lineUncertainty = Self.ankleNoise * 2.0.squareRoot() * reach
        }

        if let lens, geometry.evidence.frameHeight > 0 {
            let focal = lens.focalLengthPixels(forWidth: geometry.evidence.frameWidth, height: geometry.evidence.frameHeight)
            let bodyPixels = scale * Double(geometry.evidence.frameHeight)
            if focal > 0, bodyPixels > 0 { distance = focal / bodyPixels }
        }
    }
}
