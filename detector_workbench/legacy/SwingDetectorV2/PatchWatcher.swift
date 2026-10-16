//
//  PatchWatcher.swift
//  SwingCoach
//
//  Answers the smaller question: is the ball still present in this locked patch?
//
//  v1 is YOLO-only: a lower in-patch confidence threshold than the global
//  detector uses, because the address lock supplies the context that makes weak
//  in-patch detections trustworthy. (No classical luma/template fallback yet.)
//
//  Critical timing: at the strike the clubhead box sits over the patch, so the
//  ball reads absent purely from occlusion. `clubOverlapsPatch` lets the state
//  machine count only POST-sweep frames toward disappearance persistence.
//

import CoreGraphics
import Foundation

nonisolated struct PatchObservation: Equatable {
    let ballPresent: Bool
    let ballConfidence: Double
    let clubOverlapsPatch: Bool
}

nonisolated enum PatchWatcher {
    /// Lower than the global detector threshold; valid because we already know a
    /// ball was addressed in this exact patch.
    static let inPatchBallThreshold = 0.15

    static func observe(frame: FrameSampleV2, lock: AddressLock) -> PatchObservation {
        var bestBall = 0.0
        for ball in frame.balls where ball.confidence >= inPatchBallThreshold {
            if lock.patchRect.contains(ball.center) || lock.patchRect.intersects(ball.rect) {
                bestBall = max(bestBall, ball.confidence)
            }
        }

        let clubOverlaps = frame.clubBoxes.contains { box in
            box.confidence >= 0.30 && box.rect.intersects(lock.patchRect)
        }

        return PatchObservation(
            ballPresent: bestBall >= inPatchBallThreshold,
            ballConfidence: bestBall,
            clubOverlapsPatch: clubOverlaps
        )
    }
}
