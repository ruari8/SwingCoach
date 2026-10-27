//
//  SwingPositions.swift
//  SwingCoach
//
//  P1-P10 swing positions found after capture by SwingPositionTCN.mlpackage
//  (detectSwings run tcn_vision_v2: Apple Vision pose in, per-frame position
//  logits out). The feature builder and decoder here mirror
//  detectSwings/event_model/dataset.py `build_features` (POSE_BACKEND=vision,
//  club channels off) and model.py `decode_monotonic`. The model is only
//  valid on inputs built exactly that way, so change them together.
//

import CoreGraphics
import Foundation

/// The ten positions found for one down-the-line swing, stored on SavedSwing.
nonisolated struct SwingPositions: Codable, Equatable {
    /// Training run that produced the positions, so results from an older
    /// model can be recomputed.
    let model: String
    /// P1...P10 in order.
    let positions: [SwingPosition]

    static let currentModel = "tcn_vision_v2"
}

nonisolated struct SwingPosition: Codable, Equatable {
    /// 1...10.
    let number: Int
    /// Seconds on the saved clip's own (slow-motion) timeline.
    let clipTime: Double
    /// Sigmoid of the model's logit at the chosen frame. Low values mean the
    /// model found no clear peak for this position.
    let confidence: Double

    var label: String { "P\(number)" }
    var name: String { Self.names[number - 1] }

    static let names = [
        "Address", "Takeaway", "Lead arm parallel", "Top", "Lead arm parallel down",
        "Shaft parallel down", "Impact", "Shaft parallel through", "Arm parallel through", "Finish",
    ]
}

/// One Vision body-pose result on the training extractor's conventions:
/// 19 joints in `jointOrder`, normalized display coordinates with a top-left
/// origin, and (0, 0) with confidence 0 for joints Vision did not report.
nonisolated struct SwingPositionPose {
    var xy: [SIMD2<Float>]
    var confidence: [Float]

    /// Any joint reported (dataset.py `ok`).
    var hasBody: Bool { confidence.contains { $0 > 0 } }
}

nonisolated enum SwingPositionFeatures {
    static let gridFPS = 30.0
    static let jointCount = 19
    static let featureCount = 107
    static let positionCount = 10

    // Indices in vision_pose_extract.swift's joint order.
    private static let leftShoulder = 6, rightShoulder = 7, leftHip = 13, rightHip = 14

    /// Feature rows for a clip sampled on the 30 fps real-time grid; nil
    /// slots are frames with no body. Row layout (dataset.py):
    ///   0..<38   joint xy centred on mid-hip, divided by the median torso
    ///            length; zero rows when no body
    ///   38..<57  joint confidences
    ///   57..<95  xy change from the previous row (zero on row 0)
    ///   95       body-present flag
    ///   96..<107 club channels and view flag, all zero (pose-only run, DTL)
    static func build(_ grid: [SwingPositionPose?]) -> [Float] {
        let frameCount = grid.count
        var rows = [Float](repeating: 0, count: frameCount * featureCount)
        guard frameCount > 0 else { return rows }

        var midHips = [SIMD2<Float>](repeating: .zero, count: frameCount)
        var torsoLengths: [Float] = []
        for (t, pose) in grid.enumerated() {
            guard let pose, pose.hasBody else { continue }
            let midHip = (pose.xy[leftHip] + pose.xy[rightHip]) / 2
            let midShoulder = (pose.xy[leftShoulder] + pose.xy[rightShoulder]) / 2
            midHips[t] = midHip
            let torso = length(midShoulder - midHip)
            if torso > 1e-4 { torsoLengths.append(torso) }
        }
        let scale = max(median(torsoLengths) ?? 0.25, 1e-4)

        var previous = [Float](repeating: 0, count: jointCount * 2)
        for t in 0..<frameCount {
            let base = t * featureCount
            var centred = [Float](repeating: 0, count: jointCount * 2)
            if let pose = grid[t], pose.hasBody {
                for j in 0..<jointCount {
                    // Missing joints keep their raw (0, 0) before centring, as
                    // in training; their confidence channel reads 0.
                    centred[j * 2] = (pose.xy[j].x - midHips[t].x) / scale
                    centred[j * 2 + 1] = (pose.xy[j].y - midHips[t].y) / scale
                    rows[base + 38 + j] = pose.confidence[j]
                }
                rows[base + 95] = 1
            }
            for c in 0..<(jointCount * 2) {
                rows[base + c] = centred[c]
                rows[base + 57 + c] = t == 0 ? 0 : centred[c] - previous[c]
            }
            previous = centred
        }
        return rows
    }

    /// numpy.median: the mean of the two middle values for an even count.
    static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    private static func length(_ v: SIMD2<Float>) -> Float {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    /// Strictly increasing frame per position that maximizes the summed
    /// logits (model.py decode_monotonic). `logits` is row-major (frame,
    /// position). Ties keep the earliest frame, matching numpy.argmax.
    static func decode(logits: [Float], frameCount: Int) -> [Int]? {
        let positions = positionCount
        guard frameCount >= positions, logits.count == frameCount * positions else { return nil }
        var score = [Double](repeating: -.infinity, count: positions * frameCount)
        var back = [Int](repeating: 0, count: positions * frameCount)
        for t in 0..<frameCount {
            score[t] = Double(logits[t * positions])
        }
        for p in 1..<positions {
            var runBest = -Double.infinity
            var runArg = 0
            for t in p..<frameCount {
                let candidate = score[(p - 1) * frameCount + t - 1]
                if candidate > runBest {
                    runBest = candidate
                    runArg = t - 1
                }
                score[p * frameCount + t] = runBest + Double(logits[t * positions + p])
                back[p * frameCount + t] = runArg
            }
        }
        var frames = [Int](repeating: 0, count: positions)
        let last = (positions - 1) * frameCount
        var best = 0
        for t in 1..<frameCount where score[last + t] > score[last + best] {
            best = t
        }
        frames[positions - 1] = best
        for p in stride(from: positions - 1, to: 0, by: -1) {
            frames[p - 1] = back[p * frameCount + frames[p]]
        }
        return frames
    }
}
