//
//  CoachingEvidence.swift
//  SwingCoach
//
//  What the phone saw at each swing position: body joints, the golfer's
//  outline, and the club and ball. Coaching metrics are computed from this
//  and nothing else, so a stored swing can be re-scored without its video.
//
//  Coordinates are normalized to the displayed frame: x 0...1 left to right,
//  y 0...1 top to bottom.
//

import CoreGraphics
import Foundation

nonisolated struct CoachingPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var confidence: Double

    init(x: Double, y: Double, confidence: Double = 1) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

nonisolated struct CoachingBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double

    var center: CoachingPoint {
        CoachingPoint(x: x + width / 2, y: y + height / 2, confidence: confidence)
    }

    var corners: [CoachingPoint] {
        [
            CoachingPoint(x: x, y: y, confidence: confidence),
            CoachingPoint(x: x + width, y: y, confidence: confidence),
            CoachingPoint(x: x, y: y + height, confidence: confidence),
            CoachingPoint(x: x + width, y: y + height, confidence: confidence),
        ]
    }
}

/// Vision body joints the metrics use. Raw values are the JSON keys.
nonisolated enum CoachingJoint: String, Codable, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, leftShoulder, rightShoulder
    case leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// The golfer's outline from Vision person segmentation: for each of
/// `left.count` evenly spaced rows down the frame, the left and right edge
/// of the golfer. Rows the golfer doesn't reach hold -1.
nonisolated struct CoachingSilhouette: Codable, Equatable {
    var left: [Double]
    var right: [Double]

    var rowCount: Int { left.count }

    func row(atY y: Double) -> Int {
        min(max(Int(y * Double(rowCount)), 0), rowCount - 1)
    }

    func y(ofRow row: Int) -> Double {
        (Double(row) + 0.5) / Double(rowCount)
    }

    /// Left and right edge at height `y`, or nil where the outline is empty.
    func extent(atY y: Double) -> (left: Double, right: Double)? {
        guard rowCount > 0 else { return nil }
        let index = row(atY: y)
        guard left[index] >= 0, right[index] >= 0 else { return nil }
        return (left[index], right[index])
    }

    /// Top of the outline (smallest y with any golfer), or nil when empty.
    var top: Double? {
        left.firstIndex { $0 >= 0 }.map(y(ofRow:))
    }
}

/// Everything seen on the frame at one swing position.
nonisolated struct CoachingFrameEvidence: Codable, Equatable {
    /// 1...10.
    let position: Int
    /// Seconds on the saved clip's timeline.
    let clipTime: Double
    var joints: [String: CoachingPoint] = [:]
    var silhouette: CoachingSilhouette?
    /// Detector candidates, most confident first.
    var clubheads: [CoachingBox] = []
    var shafts: [CoachingBox] = []
    var balls: [CoachingBox] = []

    func joint(_ joint: CoachingJoint, minimumConfidence: Double = 0.15) -> CoachingPoint? {
        guard let point = joints[joint.rawValue], point.confidence >= minimumConfidence else { return nil }
        return point
    }
}

nonisolated struct SwingCoachingEvidence: Codable, Equatable {
    /// Bumped when the extractor changes what it stores, so older evidence
    /// can be rebuilt from the clip.
    var version: Int = SwingCoachingEvidence.currentVersion
    /// Displayed frame size in pixels; metrics need the aspect ratio.
    var frameWidth: Int
    var frameHeight: Int
    /// How many times slower than real time the clip's timeline runs.
    var timeScale: Double
    /// One entry per swing position. P2, P6 and P7 sit at the times the club
    /// track gives (shaft level, ball struck) when it could be followed,
    /// otherwise at the position model's times.
    var frames: [CoachingFrameEvidence]
    /// The club followed through the swing, address to follow-through, in
    /// time order: arm joints, club and ball only, no outline. `position` is
    /// 0 on these.
    var track: [CoachingFrameEvidence] = []
    /// True when built from the small copies Auto holds in memory when a
    /// swing is declared, not from the saved clip: 30 frames a second, 270
    /// pixels across. Nil in stored evidence means the clip.
    var fromLiveCopies: Bool?

    static let currentVersion = 4

    var aspect: Double {
        frameHeight > 0 ? Double(frameWidth) / Double(frameHeight) : 1
    }

    func frame(_ position: Int) -> CoachingFrameEvidence? {
        frames.first { $0.position == position }
    }
}
