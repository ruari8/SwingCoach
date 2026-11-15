//
//  CoachingEvidenceExtractor.swift
//  SwingCoach
//
//  Builds a swing's coaching evidence: from its saved clip, or during
//  Auto from the small copies of the camera's frames kept in memory. It
//  follows the club from address to follow-through, uses that to time the
//  club-defined positions, then records what Vision and the club detector
//  see on the frame at each position.
//

import AVFoundation
import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Not thread-safe: run one extraction at a time.
nonisolated final class CoachingEvidenceExtractor: @unchecked Sendable {
    enum ExtractorError: LocalizedError {
        case noVideoTrack
        case frameUnreadable(position: Int)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "The clip has no video track."
            case .frameUnreadable(let position): "The frame at P\(position) could not be read."
            }
        }
    }

    struct Timing {
        var frameSeconds = 0.0
        var poseSeconds = 0.0
        var outlineSeconds = 0.0
        var detectorSeconds = 0.0
        var trackSeconds = 0.0
        var trackSamples = 0
    }

    private static let silhouetteRows = 160
    private static let maskThreshold: UInt8 = 128

    private static let joints: [(CoachingJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    private let objectDetector: GolfObjectDetector
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let outlineRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    init(objectDetector: GolfObjectDetector) {
        self.objectDetector = objectDetector
    }

    /// What the extractor reads from the clip.
    struct Configuration {
        /// How often the club is followed, in real swing time.
        var trackRate = 60.0
        /// The same through the downswing: every frame of a 240 fps capture.
        var downswingTrackRate = 240.0
        /// Frames are reduced to this width before Vision and the detector;
        /// nil keeps them full size.
        var frameWidth: Int?
        /// Read the clip the way Auto's copies are read: each position's
        /// frame is the nearest sampled frame, and the club isn't followed
        /// between them.
        var positionsFromTrack = false

        /// The saved clip at full size: the most accurate, a few seconds a swing.
        static let clip = Configuration()
        /// What Auto holds in memory when a swing is declared: copies 480
        /// wide as the sensor sees them, so 270 across once upright, 30 per
        /// second of real time (LiveSwingPoses). Reads a saved clip the
        /// same way, for the Mac harness.
        static let liveCopies = Configuration(trackRate: 30, downswingTrackRate: 30, frameWidth: 270, positionsFromTrack: true)
    }

    private struct KeptFrame {
        var time: Double
        var image: CGImage
    }

    private struct Track {
        var samples: [CoachingFrameEvidence] = []
        var images: [KeptFrame] = []
    }

    /// One slot of the position model's 30 fps grid, in real seconds.
    private static let slot = 1.0 / 30

    private static let trackJoints: Set<String> = Set([
        CoachingJoint.neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
    ].map(\.rawValue))

    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    /// `timeScale` is how many times slower than real time the clip plays.
    /// `onFrame` receives each position's frame as it is read (the Mac
    /// harness saves them for review sheets).
    func extract(
        asset: AVAsset,
        positions: SwingPositions,
        timeScale: Double,
        configuration: Configuration = .clip,
        onFrame: ((Int, CGImage) -> Void)? = nil
    ) async throws -> (SwingCoachingEvidence, Timing) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractorError.noVideoTrack
        }
        var modelTimes: [Int: Double] = [:]
        for position in positions.positions { modelTimes[position.number] = position.clipTime }
        guard modelTimes[1] != nil else { throw ExtractorError.frameUnreadable(position: 1) }

        var timing = Timing()
        // The club first: it needs nothing from the positions' frames.
        let trackStarted = Date()
        var followed = Track()
        do {
            followed = try await clubTrack(asset: asset, track: track, modelTimes: modelTimes,
                                           timeScale: timeScale, configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // No track: the positions keep the model's times.
        }
        timing.trackSeconds = Date().timeIntervalSince(trackStarted)
        timing.trackSamples = followed.samples.count

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func checkpoint(_ position: Int, clipTime: Double) async throws -> (CoachingFrameEvidence, CGImage) {
            // The store cancels a run when Auto starts recording again.
            try Task.checkCancellation()
            let frameStarted = Date()
            var image: CGImage?
            var time = clipTime
            if configuration.positionsFromTrack {
                var nearest: KeptFrame?
                for kept in followed.images where nearest == nil || abs(kept.time - clipTime) < abs(nearest!.time - clipTime) {
                    nearest = kept
                }
                image = nearest?.image
                time = nearest?.time ?? clipTime
            } else {
                image = try? await generator.image(at: CMTime(seconds: clipTime, preferredTimescale: 600)).image
                if let full = image, let width = configuration.frameWidth { image = reduced(full, toWidth: width) }
            }
            guard let image else { throw ExtractorError.frameUnreadable(position: position) }
            timing.frameSeconds += Date().timeIntervalSince(frameStarted)
            onFrame?(position, image)
            return (evidence(in: image, position: position, clipTime: time, timing: &timing), image)
        }

        let swing = try await assemble(positions: positions, modelTimes: modelTimes, timeScale: timeScale,
                                       track: configuration.positionsFromTrack ? [] : followed.samples,
                                       fromLiveCopies: configuration.positionsFromTrack,
                                       checkpoint: checkpoint)
        return (swing, timing)
    }

    /// Reads each position's frame, address first, re-timing the positions
    /// the club defines once the address frame says which way the golfer
    /// faces (that tells the grip end of the shaft from the head).
    private func assemble(
        positions: SwingPositions,
        modelTimes: [Int: Double],
        timeScale: Double,
        track: [CoachingFrameEvidence],
        fromLiveCopies: Bool,
        checkpoint: (Int, Double) async throws -> (CoachingFrameEvidence, CGImage)
    ) async throws -> SwingCoachingEvidence {
        guard let addressTime = modelTimes[1] else { throw ExtractorError.frameUnreadable(position: 1) }
        let (address, addressImage) = try await checkpoint(1, addressTime)
        var swing = SwingCoachingEvidence(frameWidth: addressImage.width, frameHeight: addressImage.height,
                                          timeScale: timeScale, frames: [address], track: track,
                                          fromLiveCopies: fromLiveCopies ? true : nil)

        var times = modelTimes
        if let geometry = CoachingSwingGeometry(evidence: swing) {
            let refined = CoachingCheckpointTiming.refine(geometry: geometry, modelTimes: modelTimes)
            times = CoachingCheckpointTiming.accepting(refined, over: modelTimes, timeScale: timeScale)
        }

        for position in positions.positions where position.number != 1 {
            let (frame, _) = try await checkpoint(position.number, times[position.number] ?? position.clipTime)
            swing.frames.append(frame)
        }
        return swing
    }

    /// Evidence from Auto's copies of the swing's frames, so a swing can
    /// be coached before its clip is saved. `positions` are on the
    /// recording's timeline like the copies; the evidence comes back on
    /// it too, in real time (`timeScale` 1).
    ///
    /// Only the ten position frames are read. The club isn't followed
    /// between them: the checks made from these copies are the body ones
    /// (`CoachingMetricDefinition.needsClip`), and following the club
    /// changed none of them on three range sessions.
    func extract(copies: [SwingLiveCopy], positions: SwingPositions) async throws -> (SwingCoachingEvidence, Timing) {
        var modelTimes: [Int: Double] = [:]
        for position in positions.positions { modelTimes[position.number] = position.clipTime }
        var timing = Timing()
        func checkpoint(_ position: Int, time: Double) throws -> (CoachingFrameEvidence, CGImage) {
            try Task.checkCancellation()
            let frameStarted = Date()
            guard let copy = copies.min(by: { abs($0.time - time) < abs($1.time - time) }),
                  abs(copy.time - time) <= Self.slot,
                  let image = imageContext.createCGImage(
                      CIImage(cvPixelBuffer: copy.buffer).oriented(copy.orientation),
                      from: CGRect(origin: .zero, size: Self.uprightSize(of: copy)))
            else { throw ExtractorError.frameUnreadable(position: position) }
            timing.frameSeconds += Date().timeIntervalSince(frameStarted)
            return (evidence(in: image, position: position, clipTime: copy.time, timing: &timing), image)
        }
        let swing = try await assemble(positions: positions, modelTimes: modelTimes, timeScale: 1,
                                       track: [], fromLiveCopies: true, checkpoint: checkpoint)
        return (swing, timing)
    }

    private static func uprightSize(of copy: SwingLiveCopy) -> CGSize {
        let width = CVPixelBufferGetWidth(copy.buffer), height = CVPixelBufferGetHeight(copy.buffer)
        switch copy.orientation {
        case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: height, height: width)
        default: return CGSize(width: width, height: height)
        }
    }

    /// Reads the clip from address to follow-through once and records the
    /// arms, club and ball on a schedule of frames. With `positionsFromTrack`
    /// it reads on to the finish and keeps each sampled frame.
    private func clubTrack(
        asset: AVAsset,
        track: AVAssetTrack,
        modelTimes: [Int: Double],
        timeScale: Double,
        configuration: Configuration
    ) async throws -> Track {
        let last = configuration.positionsFromTrack ? modelTimes[10] : nil
        guard let start = modelTimes[1], let end = last ?? modelTimes[9] ?? modelTimes[8], end > start else { return Track() }
        var dense: ClosedRange<Double>?
        if let halfwayDown = modelTimes[5], let impact = modelTimes[7], impact > halfwayDown {
            dense = (halfwayDown - Self.slot * timeScale)...(impact + 2.5 * Self.slot * timeScale)
        }

        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let orientation = Self.orientation(for: transform)
        let turned = orientation == .right || orientation == .left
        let orientedSize = turned ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        // A little past the end, so the last position has a sample at or after it.
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end + Self.slot * timeScale, preferredTimescale: 600))
        guard reader.startReading() else { return Track() }

        var samples: [CoachingFrameEvidence] = []
        var images: [KeptFrame] = []
        var lastSampled = -Double.infinity
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time.isFinite else { continue }
            let rate = dense?.contains(time) == true ? configuration.downswingTrackRate : configuration.trackRate
            // Half a frame of slack, so a 240 fps clip is read at every
            // frame, not every other one, at the downswing rate.
            guard time - lastSampled >= timeScale / rate - timeScale / 480 else { continue }
            lastSampled = time

            // Vision and Core ML leave autoreleased buffers behind; drain
            // them every frame instead of at the end of the swing.
            let sample: CoachingFrameEvidence? = autoreleasepool {
                var sample = CoachingFrameEvidence(position: 0, clipTime: time)
                let handler: VNImageRequestHandler
                let detections: [GolfObjectDetection]?
                if let width = configuration.frameWidth {
                    // The small upright copy Auto would hold.
                    let upright = CIImage(cvPixelBuffer: pixels).oriented(orientation)
                    let scale = CGFloat(width) / upright.extent.width
                    let small = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    guard let image = imageContext.createCGImage(small, from: small.extent) else { return nil }
                    if configuration.positionsFromTrack {
                        // Only the frames are wanted: the club isn't
                        // followed from Auto's copies (see `extract(copies:)`).
                        images.append(KeptFrame(time: time, image: image))
                        return nil
                    }
                    handler = VNImageRequestHandler(cgImage: image, options: [:])
                    detections = try? objectDetector.detect(in: image)
                } else {
                    handler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: orientation, options: [:])
                    detections = try? objectDetector.detect(in: buffer, orientation: orientation, orientedImageSize: orientedSize)
                }
                if (try? handler.perform([poseRequest])) != nil {
                    sample.joints = Self.golferJoints(from: poseRequest.results ?? []).filter { Self.trackJoints.contains($0.key) }
                }
                if let detections {
                    sample.clubheads = Array(Self.boxes(.clubhead, in: detections).prefix(3))
                    sample.shafts = Array(Self.boxes(.clubShaft, in: detections).prefix(2))
                    sample.balls = Array(Self.boxes(.golfBallCandidate, in: detections).prefix(4))
                }
                return sample
            }
            if let sample { samples.append(sample) }
        }
        return Track(samples: samples, images: images)
    }

    private func reduced(_ image: CGImage, toWidth width: Int) -> CGImage? {
        let source = CIImage(cgImage: image)
        let scale = CGFloat(width) / source.extent.width
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return imageContext.createCGImage(small, from: small.extent)
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let degrees = (Int(atan2(transform.b, transform.a) * 180 / .pi) + 360) % 360
        switch degrees {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    private static func boxes(_ objectClass: GolfObjectClass, in detections: [GolfObjectDetection]) -> [CoachingBox] {
        detections
            .filter { $0.objectClass == objectClass }
            .sorted { $0.confidence > $1.confidence }
            .map {
                CoachingBox(x: rounded($0.rect.minX), y: rounded($0.rect.minY), width: rounded($0.rect.width),
                            height: rounded($0.rect.height), confidence: rounded($0.confidence, places: 100))
            }
    }

    /// Four decimals is a fifth of a pixel at 1080p and keeps stored
    /// evidence small.
    private static func rounded(_ value: Double, places: Double = 10_000) -> Double {
        (value * places).rounded() / places
    }

    func evidence(in image: CGImage, position: Int, clipTime: Double, timing: inout Timing) -> CoachingFrameEvidence {
        var frame = CoachingFrameEvidence(position: position, clipTime: clipTime)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let poseStarted = Date()
        if (try? handler.perform([poseRequest])) != nil {
            frame.joints = Self.golferJoints(from: poseRequest.results ?? [])
        }
        timing.poseSeconds += Date().timeIntervalSince(poseStarted)

        let outlineStarted = Date()
        if (try? handler.perform([outlineRequest])) != nil, let mask = outlineRequest.results?.first?.pixelBuffer {
            frame.silhouette = Self.silhouette(from: mask, joints: frame.joints)
        }
        timing.outlineSeconds += Date().timeIntervalSince(outlineStarted)

        let detectorStarted = Date()
        if let detections = try? objectDetector.detect(in: image) {
            frame.clubheads = Self.boxes(.clubhead, in: detections)
            frame.shafts = Self.boxes(.clubShaft, in: detections)
            frame.balls = Self.boxes(.golfBallCandidate, in: detections)
        }
        timing.detectorSeconds += Date().timeIntervalSince(detectorStarted)
        return frame
    }

    // MARK: - Pose

    /// The golfer is the person who takes up the most of the frame; other
    /// range users behind are smaller.
    private static func golferJoints(from observations: [VNHumanBodyPoseObservation]) -> [String: CoachingPoint] {
        var best: (area: Double, joints: [String: CoachingPoint])?
        for observation in observations {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            var joints: [String: CoachingPoint] = [:]
            var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0
            for (joint, name) in Self.joints {
                guard let point = points[name], point.confidence > 0 else { continue }
                let x = rounded(Double(point.location.x)), y = rounded(Double(1 - point.location.y))
                joints[joint.rawValue] = CoachingPoint(x: x, y: y, confidence: rounded(Double(point.confidence), places: 100))
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            guard !joints.isEmpty else { continue }
            let area = (maxX - minX) * (maxY - minY)
            if best == nil || area > best!.area {
                best = (area, joints)
            }
        }
        return best?.joints ?? [:]
    }

    // MARK: - Outline

    /// Row-by-row left and right edge of the person the joints belong to.
    /// The mask is reduced to a small grid, and only the connected region
    /// containing the golfer's hips is kept, so other people are left out.
    static func silhouette(from mask: CVPixelBuffer, joints: [String: CoachingPoint]) -> CoachingSilhouette? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0 else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let rows = silhouetteRows
        let columns = max(1, Int((Double(rows) * Double(width) / Double(height)).rounded()))
        var grid = [Bool](repeating: false, count: rows * columns)
        for row in 0..<rows {
            let sourceY = min(height - 1, Int((Double(row) + 0.5) / Double(rows) * Double(height)))
            for column in 0..<columns {
                let sourceX = min(width - 1, Int((Double(column) + 0.5) / Double(columns) * Double(width)))
                grid[row * columns + column] = pixels[sourceY * bytesPerRow + sourceX] >= maskThreshold
            }
        }

        guard let seed = seedCell(grid: grid, rows: rows, columns: columns, joints: joints) else { return nil }
        var kept = [Bool](repeating: false, count: rows * columns)
        var stack = [seed]
        kept[seed] = true
        while let cell = stack.popLast() {
            let row = cell / columns, column = cell % columns
            for (nextRow, nextColumn) in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)] {
                guard nextRow >= 0, nextRow < rows, nextColumn >= 0, nextColumn < columns else { continue }
                let next = nextRow * columns + nextColumn
                guard grid[next], !kept[next] else { continue }
                kept[next] = true
                stack.append(next)
            }
        }

        var left = [Double](repeating: -1, count: rows)
        var right = [Double](repeating: -1, count: rows)
        for row in 0..<rows {
            var first: Int?, last: Int?
            for column in 0..<columns where kept[row * columns + column] {
                if first == nil { first = column }
                last = column
            }
            if let first, let last {
                left[row] = rounded(Double(first) / Double(columns))
                right[row] = rounded(Double(last + 1) / Double(columns))
            }
        }
        return CoachingSilhouette(left: left, right: right)
    }

    /// The mask cell at the golfer's hips, or the nearest mask cell to it.
    private static func seedCell(grid: [Bool], rows: Int, columns: Int, joints: [String: CoachingPoint]) -> Int? {
        let hipNames: [CoachingJoint] = [.root, .leftHip, .rightHip]
        let hips = hipNames.compactMap { joints[$0.rawValue] }
        let anchors = hips.isEmpty ? Array(joints.values) : hips
        guard !anchors.isEmpty else { return nil }
        let x = anchors.map(\.x).reduce(0, +) / Double(anchors.count)
        let y = anchors.map(\.y).reduce(0, +) / Double(anchors.count)
        let seedRow = min(max(Int(y * Double(rows)), 0), rows - 1)
        let seedColumn = min(max(Int(x * Double(columns)), 0), columns - 1)
        if grid[seedRow * columns + seedColumn] { return seedRow * columns + seedColumn }

        var best: (distance: Int, cell: Int)?
        let reach = rows / 8
        for row in max(0, seedRow - reach)...min(rows - 1, seedRow + reach) {
            for column in max(0, seedColumn - reach)...min(columns - 1, seedColumn + reach) where grid[row * columns + column] {
                let distance = (row - seedRow) * (row - seedRow) + (column - seedColumn) * (column - seedColumn)
                if best == nil || distance < best!.distance {
                    best = (distance, row * columns + column)
                }
            }
        }
        return best?.cell
    }
}
