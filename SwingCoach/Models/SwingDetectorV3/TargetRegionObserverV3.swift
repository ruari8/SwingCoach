//
//  TargetRegionObserverV3.swift
//  SwingCoach
//
//  Answers the smaller question: is the ball still present in this locked patch?
//
//  v1 is YOLO-only: a lower in-patch confidence threshold than the global
//  detector uses, because the address lock supplies the context that makes weak
//  in-patch detections trustworthy. (No classical luma/template fallback yet.)
//
//  A missing ball detection is not departure evidence while a club covers its
//  patch. Keep that unknown state distinct from an unobstructed absence.
//

import CoreGraphics
import Foundation

nonisolated enum TargetRegionObservationV3: Equatable {
    case present(confidence: Double)
    case clubCovered
    case clearAbsent

    var isPresent: Bool {
        if case .present = self { return true }
        return false
    }

    var isReadable: Bool { self != .clubCovered }
}

nonisolated enum TargetRegionObserverV3 {
    /// Lower than the global detector threshold; valid because we already know a
    /// ball was addressed in this exact patch.
    static let inPatchBallThreshold = 0.15

    static func observe(frame: SwingObservationV3, lock: TargetLockV3) -> TargetRegionObservationV3 {
        var bestBall = 0.0
        for ball in frame.balls where ball.confidence >= inPatchBallThreshold {
            if lock.patchRect.contains(ball.center) || lock.patchRect.intersects(ball.rect) {
                bestBall = max(bestBall, ball.confidence)
            }
        }

        let clubOverlaps = frame.clubBoxes.contains { box in
            box.confidence >= 0.30 && box.rect.intersects(lock.patchRect)
        }

        if bestBall >= inPatchBallThreshold { return .present(confidence: bestBall) }
        return clubOverlaps ? .clubCovered : .clearAbsent
    }
}
