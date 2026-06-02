//
//  AddressMonitor.swift
//  SwingCoach
//
//  Finds and locks the strike location: a stationary, low-in-frame ball with a
//  clubhead/shaft resting nearby. Once locked, the rest of the detector watches
//  that one patch. Each swing locks its OWN fresh address wherever the ball is
//  — no assumption that a new ball returns to a previous location.
//
//  First implementation target: stable low ball + nearby club association.
//

import CoreGraphics
import Foundation

nonisolated struct AddressLock: Equatable {
    var patchRect: CGRect
    var ballCenter: CGPoint
    var lockedAtReal: Double
    var stabilityScore: Double
    var clubAssociationScore: Double
    var revision: Int
    var selectionReason: String
    var currentClubheadAssociationScore: Double
    var endpointCouplingScore: Double
    var ballConfidence: Double
    var addressBallCount: Int
}

nonisolated final class AddressMonitor {
    private(set) var currentLock: AddressLock?
    private var suppressedUntilRealTime = -Double.greatestFiniteMagnitude
    private var addressEndpointLostSinceRealTime: Double?

    /// A strike-area ball must sit at least this low in frame (normalized y).
    var minBallY = 0.68
    /// Minimum YOLO confidence to consider a ball as an address candidate.
    var minBallConfidence = 0.30
    /// Patch is the ball box dilated by this factor.
    var patchDilation = 3.6
    /// Real-time window used to prove a stable addressed ball.
    var lockWindowDuration = 1.15
    /// Require an actual address-duration window, not just three early samples.
    var minLockWindowSpan = 0.95
    /// Max normalized distance for detections to belong to the same ball track.
    var clusterDistance = 0.045
    /// Early-takeaway retargeting: when the clubhead reveals a different ball
    /// before impact, the provisional address can switch to that ball.
    var retargetMinClubheadAssociation = 0.32
    var retargetImprovementMargin = 0.12
    var retargetMinSeparation = 0.050
    /// Address is only armed when the address window shows the clubhead, or a
    /// compact inferred shaft endpoint, coupled to the locked ball patch.
    var minAddressEndpointCoupling = 0.50
    /// Once locked, address must keep seeing periodic endpoint coupling while
    /// the state machine is still only addressed. A backswing is handled by the
    /// swing state, not by this hold monitor.
    var minAddressHoldEndpointCoupling = 0.28
    var maxAddressHoldEndpointGap = 1.35

    func reset() {
        currentLock = nil
        suppressedUntilRealTime = -Double.greatestFiniteMagnitude
        addressEndpointLostSinceRealTime = nil
    }

    /// Drop the current lock (e.g. after a confirmed swing, or address lost).
    func invalidate() {
        currentLock = nil
        addressEndpointLostSinceRealTime = nil
    }

    /// Clear the active lock and prevent immediate re-locking from the same
    /// follow-through/waggle frames.
    func suppressLocks(until realTime: Double) {
        currentLock = nil
        addressEndpointLostSinceRealTime = nil
        suppressedUntilRealTime = max(suppressedUntilRealTime, realTime)
    }

    /// Update with the newest sampled frame and the recent buffer (real-time).
    /// Returns the current lock if one is held.
    @discardableResult
    func update(
        frame: FrameSampleV2,
        recent: [FrameSampleV2],
        allowsRetargeting: Bool = false,
        monitorsAddressHold: Bool = false
    ) -> AddressLock? {
        guard frame.realTime >= suppressedUntilRealTime else {
            return nil
        }

        let windowStart = max(0, frame.realTime - lockWindowDuration)
        let window = recent.filter { $0.realTime >= windowStart && $0.realTime <= frame.realTime }
        guard window.count >= 3 else { return nil }
        guard let first = window.first, frame.realTime - first.realTime >= minLockWindowSpan else {
            return nil
        }

        if let currentLock {
            guard !monitorsAddressHold || holdsAddress(lock: currentLock, frame: frame) else {
                self.currentLock = nil
                return nil
            }

            guard allowsRetargeting,
                  let retarget = retargetCandidate(
                    frame: frame,
                    recentWindow: window,
                    currentLock: currentLock
                  )
            else {
                return currentLock
            }

            let lock = AddressLock(
                patchRect: patchRect(center: retarget.center, meanRect: retarget.meanRect),
                ballCenter: retarget.center,
                lockedAtReal: frame.realTime,
                stabilityScore: retarget.stabilityScore,
                clubAssociationScore: retarget.clubAssociationScore,
                revision: currentLock.revision + 1,
                selectionReason: retarget.selectionReason,
                currentClubheadAssociationScore: retarget.currentClubheadAssociationScore,
                endpointCouplingScore: retarget.endpointCouplingScore,
                ballConfidence: retarget.ballConfidence,
                addressBallCount: retarget.addressBallCount
            )
            self.currentLock = lock
            addressEndpointLostSinceRealTime = nil
            return lock
        }

        guard let best = bestStableAddress(frame: frame, window: window) else {
            return nil
        }

        let lock = AddressLock(
            patchRect: patchRect(center: best.center, meanRect: best.meanRect),
            ballCenter: best.center,
            lockedAtReal: frame.realTime,
            stabilityScore: best.stabilityScore,
            clubAssociationScore: best.clubAssociationScore,
            revision: 0,
            selectionReason: best.selectionReason,
            currentClubheadAssociationScore: best.currentClubheadAssociationScore,
            endpointCouplingScore: best.endpointCouplingScore,
            ballConfidence: best.ballConfidence,
            addressBallCount: best.addressBallCount
        )
        currentLock = lock
        addressEndpointLostSinceRealTime = nil
        return lock
    }

    private func holdsAddress(lock: AddressLock, frame: FrameSampleV2) -> Bool {
        let endpointCoupling = addressEndpointCouplingScore(
            for: lock.ballCenter,
            frame: frame
        )
        if endpointCoupling >= minAddressHoldEndpointCoupling {
            addressEndpointLostSinceRealTime = nil
            return true
        }

        if addressEndpointLostSinceRealTime == nil {
            addressEndpointLostSinceRealTime = frame.realTime
        }

        let lostDuration = frame.realTime - (addressEndpointLostSinceRealTime ?? frame.realTime)
        return lostDuration < maxAddressHoldEndpointGap
    }

    private func bestStableAddress(frame: FrameSampleV2, window: [FrameSampleV2]) -> ScoredAddress? {
        let addressBallCount = addressBallCount(in: frame)
        var clusters: [BallCluster] = []
        for sample in window {
            for ball in sample.balls
            where ball.confidence >= minBallConfidence && ball.center.y >= minBallY {
                let center = ball.center
                if let index = clusters.firstIndex(where: { GeometryV2.distance($0.center, center) <= clusterDistance }) {
                    clusters[index].append(ball: ball, frame: sample)
                } else {
                    clusters.append(BallCluster(ball: ball, frame: sample))
                }
            }
        }

        let scored = clusters.compactMap { cluster -> ScoredAddress? in
            guard let currentBall = currentFrameMatch(for: cluster.center, frame: frame) else {
                return nil
            }

            let distinctFrameCount = Set(cluster.frameIndices).count
            let presenceRatio = Double(distinctFrameCount) / Double(window.count)
            guard presenceRatio >= 0.30 else { return nil }

            let movement = cluster.boundsDiagonal
            let movementScore = GeometryV2.inverseRamp(movement, low: 0.012, high: 0.075)
            let presenceScore = GeometryV2.ramp(presenceRatio, low: 0.30, high: 0.78)
            let confidenceScore = GeometryV2.ramp(cluster.meanConfidence, low: minBallConfidence, high: 0.82)
            let meanMotion = window.reduce(0) { $0 + $1.lumaMotion } / Double(max(1, window.count))
            let quietAddressScore = GeometryV2.inverseRamp(meanMotion, low: 0.012, high: 0.035)
            let rawStability = min(1, max(0, 0.42 * presenceScore + 0.34 * movementScore + 0.24 * confidenceScore))
            let stabilityScore = rawStability * (0.20 + 0.80 * quietAddressScore)

            let clubAssociation = clubAssociationScore(for: cluster.center, in: window)
            guard stabilityScore >= 0.34, clubAssociation >= 0.28 else { return nil }

            let currentClubheadAssociation = currentClubheadAssociationScore(
                for: cluster.center,
                frame: frame
            )
            let endpointCoupling = addressEndpointCouplingScore(
                for: cluster.center,
                in: window
            )
            guard endpointCoupling >= minAddressEndpointCoupling else { return nil }

            let combined = stabilityScore * 0.64 + clubAssociation * 0.36
            return ScoredAddress(
                center: cluster.center,
                meanRect: cluster.meanRect,
                stabilityScore: stabilityScore,
                clubAssociationScore: clubAssociation,
                combinedScore: combined,
                selectionReason: "stable_address",
                currentClubheadAssociationScore: currentClubheadAssociation,
                endpointCouplingScore: endpointCoupling,
                ballConfidence: currentBall.confidence,
                addressBallCount: addressBallCount
            )
        }

        return scored.max(by: { $0.combinedScore < $1.combinedScore })
    }

    private func retargetCandidate(
        frame: FrameSampleV2,
        recentWindow: [FrameSampleV2],
        currentLock: AddressLock
    ) -> ScoredAddress? {
        let currentAssociation = currentClubheadAssociationScore(
            for: currentLock.ballCenter,
            frame: frame
        )
        let addressBallCount = addressBallCount(in: frame)

        let candidates = frame.balls.compactMap { ball -> ScoredAddress? in
            guard ball.confidence >= minBallConfidence, ball.center.y >= minBallY else {
                return nil
            }
            let separation = GeometryV2.distance(ball.center, currentLock.ballCenter)
            guard separation >= retargetMinSeparation else { return nil }

            let clubheadAssociation = currentClubheadAssociationScore(for: ball.center, frame: frame)
            guard clubheadAssociation >= retargetMinClubheadAssociation,
                  clubheadAssociation >= currentAssociation + retargetImprovementMargin
            else { return nil }
            let endpointCoupling = addressEndpointCouplingScore(for: ball.center, frame: frame)

            let stability = recentBallStabilityScore(for: ball.center, in: recentWindow)
            let confidence = GeometryV2.ramp(ball.confidence, low: minBallConfidence, high: 0.88)
            let score = clubheadAssociation * 0.66 + confidence * 0.22 + stability * 0.12
            return ScoredAddress(
                center: ball.center,
                meanRect: ball.rect,
                stabilityScore: max(0.34, stability),
                clubAssociationScore: max(currentLock.clubAssociationScore, clubheadAssociation),
                combinedScore: score,
                selectionReason: "takeaway_retarget",
                currentClubheadAssociationScore: clubheadAssociation,
                endpointCouplingScore: max(clubheadAssociation, endpointCoupling),
                ballConfidence: ball.confidence,
                addressBallCount: addressBallCount
            )
        }

        return candidates.max(by: { $0.combinedScore < $1.combinedScore })
    }

    private func clubAssociationScore(for point: CGPoint, in window: [FrameSampleV2]) -> Double {
        var best = 0.0
        var frameScores: [Double] = []
        var associatedPoints: [CGPoint] = []
        for sample in window {
            var frameBest = 0.0
            var framePoint: CGPoint?
            for club in sample.clubBoxes where club.confidence >= 0.25 {
                let distance = GeometryV2.distance(from: point, to: club.rect)
                let proximity = GeometryV2.inverseRamp(distance, low: 0.0, high: 0.16)
                let confidence = GeometryV2.ramp(club.confidence, low: 0.25, high: 0.80)
                let score = proximity * (0.55 + 0.45 * confidence)
                if score > frameBest {
                    frameBest = score
                    framePoint = Self.nearestPoint(to: point, in: club.rect)
                }
            }
            frameScores.append(frameBest)
            if frameBest >= 0.16, let framePoint {
                associatedPoints.append(framePoint)
            }
            best = max(best, frameBest)
        }
        guard !frameScores.isEmpty else { return 0 }

        let activeRatio = Double(frameScores.filter { $0 >= 0.16 }.count) / Double(frameScores.count)
        let mean = frameScores.reduce(0, +) / Double(frameScores.count)
        let activeScore = GeometryV2.ramp(activeRatio, low: 0.28, high: 0.75)
        let meanScore = GeometryV2.ramp(mean, low: 0.10, high: 0.52)
        let pathSpan = Self.pathSpan(associatedPoints)
        let stabilityScore = GeometryV2.inverseRamp(pathSpan, low: 0.018, high: 0.12)
        let persistenceScore = min(1, best * 0.30 + activeScore * 0.45 + meanScore * 0.25)
        return persistenceScore * (0.15 + 0.85 * stabilityScore)
    }

    private func currentClubheadAssociationScore(for point: CGPoint, frame: FrameSampleV2) -> Double {
        var best = 0.0
        for clubhead in frame.clubheads where clubhead.confidence >= 0.25 {
            let distance = GeometryV2.distance(point, clubhead.center)
            let proximity = GeometryV2.inverseRamp(distance, low: 0.035, high: 0.13)
            let confidence = GeometryV2.ramp(clubhead.confidence, low: 0.25, high: 0.82)
            best = max(best, proximity * (0.55 + 0.45 * confidence))
        }
        return best
    }

    private func addressEndpointCouplingScore(for point: CGPoint, frame: FrameSampleV2) -> Double {
        var best = 0.0

        for clubhead in frame.clubheads where clubhead.confidence >= 0.45 {
            let distance = GeometryV2.distance(point, clubhead.center)
            let proximity = GeometryV2.inverseRamp(distance, low: 0.030, high: 0.110)
            let confidence = GeometryV2.ramp(clubhead.confidence, low: 0.45, high: 0.86)
            best = max(best, proximity * (0.58 + 0.42 * confidence))
        }

        for shaft in frame.detections
        where shaft.objectClass == .clubShaft && shaft.confidence >= 0.50 {
            let distance = GeometryV2.distance(from: point, to: shaft.rect)
            let proximity = GeometryV2.inverseRamp(distance, low: 0.0, high: 0.045)
            let confidence = GeometryV2.ramp(shaft.confidence, low: 0.50, high: 0.88)
            let shape = Self.shaftEndpointReliability(shaft.rect)
            best = max(best, proximity * shape * (0.55 + 0.45 * confidence))
        }

        return best
    }

    private func addressEndpointCouplingScore(for point: CGPoint, in window: [FrameSampleV2]) -> Double {
        let frameScores = window.map { addressEndpointCouplingScore(for: point, frame: $0) }
        guard !frameScores.isEmpty else { return 0 }

        let best = frameScores.max() ?? 0
        let mean = frameScores.reduce(0, +) / Double(frameScores.count)
        let activeRatio = Double(frameScores.filter { $0 >= minAddressEndpointCoupling }.count) / Double(frameScores.count)
        let meanScore = GeometryV2.ramp(mean, low: 0.10, high: 0.42)
        let activeScore = GeometryV2.ramp(activeRatio, low: 0.18, high: 0.50)
        return min(1, best * 0.45 + meanScore * 0.25 + activeScore * 0.30)
    }

    private func recentBallStabilityScore(for point: CGPoint, in window: [FrameSampleV2]) -> Double {
        let matches = window.compactMap { sample -> CGPoint? in
            sample.balls
                .filter {
                    $0.confidence >= minBallConfidence
                    && $0.center.y >= minBallY
                    && GeometryV2.distance($0.center, point) <= clusterDistance
                }
                .max(by: { $0.confidence < $1.confidence })?
                .center
        }
        guard !matches.isEmpty else { return 0 }
        let ratio = Double(matches.count) / Double(max(1, window.count))
        let persistence = GeometryV2.ramp(ratio, low: 0.10, high: 0.45)
        let movement = Self.pathSpan(matches)
        let stillness = GeometryV2.inverseRamp(movement, low: 0.012, high: 0.075)
        return persistence * stillness
    }

    private func currentFrameMatch(for point: CGPoint, frame: FrameSampleV2) -> GolfObjectDetection? {
        frame.balls
            .filter {
                $0.confidence >= minBallConfidence
                && $0.center.y >= minBallY
                && GeometryV2.distance($0.center, point) <= clusterDistance
            }
            .max(by: { $0.confidence < $1.confidence })
    }

    private func addressBallCount(in frame: FrameSampleV2) -> Int {
        frame.balls.filter {
            $0.confidence >= minBallConfidence && $0.center.y >= minBallY
        }.count
    }

    private func patchRect(center: CGPoint, meanRect: CGRect) -> CGRect {
        let baseWidth = max(0.030, meanRect.width * patchDilation)
        let baseHeight = max(0.030, meanRect.height * patchDilation)
        let width = min(0.18, baseWidth)
        let height = min(0.18, baseHeight)
        let x = min(max(0, center.x - width / 2), 1 - width)
        let y = min(max(0, center.y - height / 2), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private extension AddressMonitor {
    nonisolated static func pathSpan(_ points: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 1 }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width * width + height * height).squareRoot()
    }

    nonisolated static func nearestPoint(to point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    nonisolated static func shaftEndpointReliability(_ rect: CGRect) -> Double {
        let width = Double(rect.width)
        let height = Double(rect.height)
        let diagonal = (width * width + height * height).squareRoot()
        return GeometryV2.inverseRamp(diagonal, low: 0.20, high: 0.42)
    }

}

nonisolated private struct BallCluster {
    private(set) var weightedX: CGFloat
    private(set) var weightedY: CGFloat
    private(set) var totalWeight: CGFloat
    private(set) var rects: [CGRect]
    private(set) var confidences: [Double]
    private(set) var frameIndices: [Int]

    init(ball: GolfObjectDetection, frame: FrameSampleV2) {
        let weight = CGFloat(max(0.001, ball.confidence))
        weightedX = ball.center.x * weight
        weightedY = ball.center.y * weight
        totalWeight = weight
        rects = [ball.rect]
        confidences = [ball.confidence]
        frameIndices = [Int((frame.realTime * 1000).rounded())]
    }

    var center: CGPoint {
        CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)
    }

    var meanConfidence: Double {
        confidences.reduce(0, +) / Double(max(1, confidences.count))
    }

    var meanRect: CGRect {
        guard !rects.isEmpty else {
            return CGRect(x: center.x - 0.015, y: center.y - 0.015, width: 0.03, height: 0.03)
        }
        let minX = rects.map(\.minX).reduce(0, +) / CGFloat(rects.count)
        let minY = rects.map(\.minY).reduce(0, +) / CGFloat(rects.count)
        let width = rects.map(\.width).reduce(0, +) / CGFloat(rects.count)
        let height = rects.map(\.height).reduce(0, +) / CGFloat(rects.count)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    var boundsDiagonal: Double {
        let centers = rects.map { CGPoint(x: $0.midX, y: $0.midY) }
        guard !centers.isEmpty else { return 0 }
        let xs = centers.map(\.x)
        let ys = centers.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width * width + height * height).squareRoot()
    }

    mutating func append(ball: GolfObjectDetection, frame: FrameSampleV2) {
        let weight = CGFloat(max(0.001, ball.confidence))
        weightedX += ball.center.x * weight
        weightedY += ball.center.y * weight
        totalWeight += weight
        rects.append(ball.rect)
        confidences.append(ball.confidence)
        frameIndices.append(Int((frame.realTime * 1000).rounded()))
    }
}

nonisolated private struct ScoredAddress {
    let center: CGPoint
    let meanRect: CGRect
    let stabilityScore: Double
    let clubAssociationScore: Double
    let combinedScore: Double
    let selectionReason: String
    let currentClubheadAssociationScore: Double
    let endpointCouplingScore: Double
    let ballConfidence: Double
    let addressBallCount: Int
}
