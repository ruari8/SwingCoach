import CoreGraphics
import Foundation

nonisolated struct BallTrackV3: Equatable, Encodable {
    let id: Int
    var centerX: Double
    var centerY: Double
    var meanWidth: Double
    var meanHeight: Double
    var meanConfidence: Double
    var firstSeenReal: Double
    var lastSeenReal: Double
    var observationCount: Int
    var consecutiveMisses: Int

    var center: CGPoint { CGPoint(x: centerX, y: centerY) }
    var meanRect: CGRect { CGRect(x: centerX - meanWidth / 2, y: centerY - meanHeight / 2, width: meanWidth, height: meanHeight) }
}

nonisolated struct SceneSnapshotV3: Encodable {
    let sourceTime: Double
    let ballTracks: [BallTrackV3]
}

/// Maintains one-to-one ball identities. A detection can update at most one
/// track and a track can consume at most one detection in a frame.
nonisolated final class SceneTrackerV3 {
    private(set) var ballTracks: [BallTrackV3] = []
    private var nextBallID = 1
    private let associationDistance = 0.045
    private let retentionSeconds = 1.6

    func reset() {
        ballTracks.removeAll(keepingCapacity: true)
        nextBallID = 1
    }

    func update(with frame: SwingObservationV3) -> SceneSnapshotV3 {
        var pairs: [(distance: Double, track: Int, detection: Int)] = []
        let balls = frame.balls.filter { $0.confidence >= 0.25 }
        for ti in ballTracks.indices {
            for di in balls.indices {
                let d = GeometryV3.distance(ballTracks[ti].center, balls[di].center)
                if d <= associationDistance { pairs.append((d, ti, di)) }
            }
        }
        pairs.sort { $0.distance < $1.distance }
        var usedTracks = Set<Int>()
        var usedDetections = Set<Int>()
        for pair in pairs where !usedTracks.contains(pair.track) && !usedDetections.contains(pair.detection) {
            update(trackAt: pair.track, with: balls[pair.detection], at: frame.realTime)
            usedTracks.insert(pair.track)
            usedDetections.insert(pair.detection)
        }
        for index in ballTracks.indices where !usedTracks.contains(index) { ballTracks[index].consecutiveMisses += 1 }
        for index in balls.indices where !usedDetections.contains(index) {
            let ball = balls[index]
            ballTracks.append(BallTrackV3(
                id: nextBallID, centerX: ball.center.x, centerY: ball.center.y,
                meanWidth: ball.rect.width, meanHeight: ball.rect.height,
                meanConfidence: ball.confidence, firstSeenReal: frame.realTime,
                lastSeenReal: frame.realTime, observationCount: 1, consecutiveMisses: 0
            ))
            nextBallID += 1
        }
        ballTracks.removeAll { frame.realTime - $0.lastSeenReal > retentionSeconds }
        return SceneSnapshotV3(sourceTime: frame.sourceTime, ballTracks: ballTracks)
    }

    func track(id: Int) -> BallTrackV3? { ballTracks.first { $0.id == id } }

    private func update(trackAt index: Int, with ball: GolfObjectDetection, at time: Double) {
        let old = ballTracks[index]
        let n = Double(min(old.observationCount, 15))
        let alpha = 1 / (n + 1)
        ballTracks[index].centerX = old.centerX * (1 - alpha) + Double(ball.center.x) * alpha
        ballTracks[index].centerY = old.centerY * (1 - alpha) + Double(ball.center.y) * alpha
        ballTracks[index].meanWidth = old.meanWidth * (1 - alpha) + Double(ball.rect.width) * alpha
        ballTracks[index].meanHeight = old.meanHeight * (1 - alpha) + Double(ball.rect.height) * alpha
        ballTracks[index].meanConfidence = old.meanConfidence * (1 - alpha) + ball.confidence * alpha
        ballTracks[index].lastSeenReal = time
        ballTracks[index].observationCount += 1
        ballTracks[index].consecutiveMisses = 0
    }
}
