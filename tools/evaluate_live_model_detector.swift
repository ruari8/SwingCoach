import AVFoundation
import CoreGraphics
import CoreMedia
import CoreML
import CoreVideo
import Darwin
import Foundation
import ImageIO
import Vision

private struct PoseWindowDiagnostics: Encodable, Equatable {
    let attemptedSampleCount: Int
    let validSampleCount: Int
    let coverage: Double
    let peakHandSpeed: Double
    let handTravel: Double
    let verticalHandTravel: Double
    let horizontalHandTravel: Double
    let addressToFinishDistance: Double
    let bodyDrift: Double
}

private struct DetectionOutput: Encodable {
    let start: Double
    let end: Double
    let confidence: Double
    let declaredAt: Double?
    let latencyFromEnd: Double?
    let latencyFromMatchedLabelEnd: Double?
    let matchedLabelIndices: [Int]
    let diagnostics: ObjectSwingWindowDiagnostics?
}

private struct ImpactDetectionOutput: Encodable {
    let start: Double
    let end: Double
    let impactTime: Double
    let confidence: Double
    let declaredAt: Double?
    let latencyFromImpact: Double?
    let latencyFromEnd: Double?
    let latencyFromMatchedLabelEnd: Double?
    let matchedLabelIndices: [Int]
    let diagnostics: ObjectSwingWindowDiagnostics
    let poseDiagnostics: PoseWindowDiagnostics?
}

private struct PerformanceSample: Encodable {
    let sourceTime: Double
    let detectorTime: Double
    let elapsedWallTime: Double
    let processingLag: Double
    let decodedFrames: Int
    let processedFrames: Int
    let poseSampledFrames: Int
    let detectorThroughputFPS: Double
    let realtimeRatio: Double
}

private struct EvaluationOutput: Encodable {
    let video: String
    let model: String
    let computeUnits: String
    let duration: Double
    let evaluatedStart: Double
    let evaluatedEnd: Double
    let detectorDuration: Double
    let sourceTimeScale: Double
    let detectorTimelineScale: Double
    let configuration: String
    let targetSampleFPS: Double
    let targetSourceSampleFPS: Double
    let impactConfirmationPostRoll: Double
    let declarationPollInterval: Double
    let acceptanceMaxClubTopY: Double
    let wallClockElapsedSeconds: Double
    let realtimeRatio: Double
    let finalProcessingLagSeconds: Double
    let decodedFrames: Int
    let skippedDecodedFrames: Int
    let processedFrames: Int
    let effectiveDetectorFPS: Double
    let detectorThroughputFPS: Double
    let poseSampledFrames: Int
    let poseValidFrames: Int
    let averageProcessingTimeMS: Double
    let lastProcessingTimeMS: Double
    let averagePoseProcessingTimeMS: Double
    let lastPoseProcessingTimeMS: Double
    let performanceSamples: [PerformanceSample]
    let featureSummary: ObjectSwingFeatureSummary
    let candidateWindows: [ObjectSwingWindowDiagnostics]
    let impactDebugReports: [ObjectSwingImpactDebugReport]
    let detections: [DetectionOutput]
    let impactCenteredDetections: [ImpactDetectionOutput]
    let hybridImpactDetections: [ImpactDetectionOutput]
    let matchedCount: Int?
    let missedLabelIndices: [Int]?
    let falsePositiveCount: Int?
}

private struct DeclarationRecord {
    let start: Double
    let end: Double
    let declaredAt: Double
}

private struct LabelPayload: Decodable {
    let positiveSwingWindows: [LabelWindow]

    enum CodingKeys: String, CodingKey {
        case positiveSwingWindows = "positive_swing_windows"
    }
}

private struct LabelWindow: Decodable {
    let start: Double
    let end: Double
}

private typealias PoseFeature = ObjectSwingPoseFeature

@main
struct EvaluateLiveModelDetector {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let videoPath = arguments.first else {
                fputs("usage: evaluate_live_model_detector <video-path> [model-path] [sample-fps] [source-time-scale] [max-frames] [labels-path] [min-strong-motion-frames] [min-mean-club-motion] [min-club-path-span] [max-club-top-y] [detector-timeline-scale] [source-start] [source-end] [impact-confirmation-post-roll] [compute-units: all|cpu|cpuOnly|cpuAndGPU|cpuAndNeuralEngine] [declaration-poll-interval]\n", stderr)
                exit(2)
            }

            let modelPath = arguments.count > 1
                ? arguments[1]
                : "SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"
            let requestedSampleFPS = arguments.count > 2 ? Double(arguments[2]) ?? 16.0 : 16.0
            let sourceTimeScale = arguments.count > 3 ? Double(arguments[3]) ?? 8.0 : 8.0
            let maxFrames = arguments.count > 4 ? Int(arguments[4]) ?? 18_000 : 18_000
            let labelsPath = arguments.count > 5 && !arguments[5].isEmpty ? arguments[5] : nil

            let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw EvaluationError.invalidDuration
            }

            let detectorTimelineScale = arguments.count > 10 ? Double(arguments[10]) ?? sourceTimeScale : sourceTimeScale
            let evaluatedStart = arguments.count > 11 ? max(0.0, Double(arguments[11]) ?? 0.0) : 0.0
            let requestedEvaluatedEnd = arguments.count > 12 ? Double(arguments[12]) : nil
            let evaluatedEnd = min(
                durationSeconds,
                max(evaluatedStart, requestedEvaluatedEnd ?? durationSeconds)
            )
            let evaluatedDuration = max(0.0, evaluatedEnd - evaluatedStart)

            let detectorDuration = evaluatedDuration / max(1.0, sourceTimeScale)
            let effectiveInterval = max(
                1 / max(1.0, requestedSampleFPS),
                detectorDuration / Double(max(12, maxFrames))
            )
            var configuration = ObjectSwingDetectorConfiguration.liveObjectModel(
                sampleFPS: 1 / effectiveInterval,
                timelineScale: detectorTimelineScale
            )
            if arguments.count > 6 {
                configuration.acceptanceMinStrongMotionFrames = max(1, Int(arguments[6]) ?? configuration.acceptanceMinStrongMotionFrames)
            }
            if arguments.count > 7 {
                configuration.acceptanceMinMeanClubMotion = max(0, Double(arguments[7]) ?? configuration.acceptanceMinMeanClubMotion)
            }
            if arguments.count > 8 {
                configuration.acceptanceMinClubPathSpan = max(0, Double(arguments[8]) ?? configuration.acceptanceMinClubPathSpan)
            }
            if arguments.count > 9 {
                configuration.acceptanceMaxClubTopY = min(1.0, max(0.0, Double(arguments[9]) ?? configuration.acceptanceMaxClubTopY))
            }
            if arguments.count > 13 {
                configuration.impactConfirmationPostRoll = max(0.10, Double(arguments[13]) ?? configuration.impactConfirmationPostRoll)
            }
            let computeUnits = arguments.count > 14 ? computeUnits(named: arguments[14]) : .all
            let declarationPollInterval = arguments.count > 15 ? max(0, Double(arguments[15]) ?? 0) : 0
            let modelURL = URL(fileURLWithPath: modelPath)

            let result = try await detectSwings(
                in: asset,
                videoPath: videoPath,
                modelPath: modelPath,
                modelURL: modelURL,
                durationSeconds: durationSeconds,
                evaluatedStart: evaluatedStart,
                evaluatedEnd: evaluatedEnd,
                detectorDuration: detectorDuration,
                sourceTimeScale: sourceTimeScale,
                configuration: configuration,
                computeUnits: computeUnits,
                declarationPollInterval: declarationPollInterval,
                labelsPath: labelsPath
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("live model detector evaluation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func detectSwings(
        in asset: AVAsset,
        videoPath: String,
        modelPath: String,
        modelURL: URL,
        durationSeconds: Double,
        evaluatedStart: Double,
        evaluatedEnd: Double,
        detectorDuration: Double,
        sourceTimeScale: Double,
        configuration: ObjectSwingDetectorConfiguration,
        computeUnits: MLComputeUnits,
        declarationPollInterval: Double,
        labelsPath: String?
    ) async throws -> EvaluationOutput {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EvaluationError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        if evaluatedStart > 0 || evaluatedEnd < durationSeconds {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: evaluatedStart, preferredTimescale: 600),
                duration: CMTime(seconds: max(0.0, evaluatedEnd - evaluatedStart), preferredTimescale: 600)
            )
        }
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false
        output.videoComposition = try await orientedVideoComposition(
            for: videoTrack,
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )

        guard reader.canAdd(output) else {
            throw EvaluationError.readerSetupFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? EvaluationError.readerSetupFailed
        }

        let detector = LiveModelSwingDetector(
            configuration: configuration,
            modelURL: modelURL,
            computeUnits: computeUnits
        )
        detector.reset(enabled: true, configuration: configuration)
        var firstSampleTime: CMTime?
        var lastSubmittedDetectorTime = -Double.greatestFiniteMagnitude
        var lastDetectorTime = 0.0
        var lastSourceTime = evaluatedStart
        var strictDeclarations: [DeclarationRecord] = []
        var impactDeclarations: [DeclarationRecord] = []
        let poseRequest = VNDetectHumanBodyPoseRequest()
        var lastPoseDetectorTime = -Double.greatestFiniteMagnitude
        var poseAttemptTimes: [Double] = []
        var poseFeatures: [PoseFeature] = []
        var decodedFrameCount = 0
        var poseProcessingTotalMS = 0.0
        var poseProcessingSampleCount = 0
        var lastPoseProcessingTimeMS = 0.0
        var performanceSamples: [PerformanceSample] = []
        var nextPerformanceSampleDetectorTime = 0.0
        var lastDeclarationPollDetectorTime = -Double.greatestFiniteMagnitude
        let startedAt = Date()

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            decodedFrameCount += 1

            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstSampleTime == nil {
                firstSampleTime = sampleTime
            }
            guard let firstSampleTime else { continue }

            let sourceTime = evaluatedStart + CMTimeGetSeconds(CMTimeSubtract(sampleTime, firstSampleTime))
            guard sourceTime.isFinite else { continue }

            let detectorTime = sourceTime / max(1.0, sourceTimeScale)
            guard detectorTime - lastSubmittedDetectorTime + 0.001 >= configuration.targetSampleInterval else { continue }

            lastSubmittedDetectorTime = detectorTime
            lastDetectorTime = detectorTime
            lastSourceTime = sourceTime
            let orientedSize = orientedImageSize(from: sampleBuffer)
            _ = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: detectorTime,
                orientation: .up,
                orientedImageSize: orientedSize
            )
            let poseSampleInterval = max(0.12, configuration.targetSampleInterval * 2.0)
            if detectorTime - lastPoseDetectorTime >= poseSampleInterval {
                lastPoseDetectorTime = detectorTime
                poseAttemptTimes.append(detectorTime)
                let poseStartedAt = Date()
                if let feature = poseFeature(
                    from: sampleBuffer,
                    at: detectorTime,
                    orientation: .up,
                    request: poseRequest
                ) {
                    poseFeatures.append(feature)
                }
                lastPoseProcessingTimeMS = Date().timeIntervalSince(poseStartedAt) * 1_000
                poseProcessingTotalMS += lastPoseProcessingTimeMS
                poseProcessingSampleCount += 1
            }
            if declarationPollInterval == 0
                || detectorTime - lastDeclarationPollDetectorTime >= declarationPollInterval {
                lastDeclarationPollDetectorTime = detectorTime
                recordDeclarations(
                    sourceTimelineDetections(detector.currentDetections(), timeScale: sourceTimeScale),
                    declaredAt: sourceTime,
                    records: &strictDeclarations
                )
                recordImpactDeclarations(
                    sourceTimelineImpactCandidates(
                        detector.currentImpactCenteredDetections(
                            videoDuration: detectorTime,
                            declaredAt: detectorTime
                        ),
                        timeScale: sourceTimeScale
                    ),
                    records: &impactDeclarations
                )
            }
            if detectorTime >= nextPerformanceSampleDetectorTime {
                performanceSamples.append(
                    performanceSample(
                        sourceTime: sourceTime,
                        detectorTime: detectorTime,
                        startedAt: startedAt,
                        decodedFrameCount: decodedFrameCount,
                        processedFrameCount: detector.currentSnapshot().processedFrameCount,
                        poseSampledFrameCount: poseAttemptTimes.count
                    )
                )
                nextPerformanceSampleDetectorTime = detectorTime + 10.0
            }
        }

        if reader.status == .failed {
            throw reader.error ?? EvaluationError.readerSetupFailed
        }

        let detectorDetections = detector.finish(recordingTime: lastDetectorTime)
        let diagnostics = detector.currentDetectionDiagnostics()
        let detections = sourceTimelineDetections(detectorDetections, timeScale: sourceTimeScale)
        recordDeclarations(
            detections,
            declaredAt: lastSourceTime,
            records: &strictDeclarations
        )
        let detectorImpactCenteredDetections = detector.currentImpactCenteredDetections(
            videoDuration: lastDetectorTime,
            declaredAt: lastDetectorTime
        )
        let impactCenteredDetections = sourceTimelineImpactCandidates(
            detectorImpactCenteredDetections,
            timeScale: sourceTimeScale
        )
        recordImpactDeclarations(
            impactCenteredDetections,
            records: &impactDeclarations
        )
        let impactPoseDiagnostics = detectorImpactCenteredDetections.map {
            poseDiagnostics(for: $0, attempts: poseAttemptTimes, features: poseFeatures)
        }
        let snapshot = detector.currentSnapshot()
        let wallClockElapsed = Date().timeIntervalSince(startedAt)
        let finalProcessingLag = wallClockElapsed - max(0.001, lastDetectorTime)
        let averagePoseProcessingTimeMS = poseProcessingSampleCount > 0
            ? poseProcessingTotalMS / Double(poseProcessingSampleCount)
            : 0
        let featureSummary = detector.currentFeatureSummary()
        let candidateWindows = sourceTimelineDiagnostics(
            detector.currentCandidateDiagnostics(),
            timeScale: sourceTimeScale
        )
        let impactDebugReports = sourceTimelineImpactDebugReports(
            detector.currentImpactDebugReports(
                videoDuration: lastDetectorTime,
                declaredAt: lastDetectorTime
            ),
            timeScale: sourceTimeScale
        )
        let labels = try labelsPath.map { try loadLabels(path: $0) }
        let scoredDetections = scoreDetections(
            detections,
            labels: labels,
            diagnostics: sourceTimelineDiagnostics(diagnostics, timeScale: sourceTimeScale),
            declarations: strictDeclarations
        )
        let scoredImpactDetections = scoreImpactDetections(
            impactCenteredDetections,
            labels: labels,
            declarations: impactDeclarations,
            poseDiagnostics: impactPoseDiagnostics
        )
        let detectorHybridImpactCandidates = ObjectSwingImpactSelector.hybridImpactCandidates(
            detectorImpactCenteredDetections,
            attemptTimes: poseAttemptTimes,
            poseFeatures: poseFeatures
        )
        let hybridImpactCandidates = sourceTimelineImpactCandidates(
            detectorHybridImpactCandidates,
            timeScale: sourceTimeScale
        )
        let hybridPoseDiagnostics = detectorHybridImpactCandidates.map {
            poseDiagnostics(for: $0, attempts: poseAttemptTimes, features: poseFeatures)
        }
        let scoredHybridImpactDetections = scoreImpactDetections(
            hybridImpactCandidates,
            labels: labels,
            declarations: impactDeclarations,
            poseDiagnostics: hybridPoseDiagnostics
        )
        let missed = missedLabelIndices(scoredDetections: scoredDetections, labels: labels)
        let falsePositiveCount = labels == nil
            ? nil
            : scoredDetections.filter { $0.matchedLabelIndices.isEmpty }.count

        return EvaluationOutput(
            video: videoPath,
            model: modelPath,
            computeUnits: computeUnitsDescription(computeUnits),
            duration: durationSeconds,
            evaluatedStart: evaluatedStart,
            evaluatedEnd: evaluatedEnd,
            detectorDuration: detectorDuration,
            sourceTimeScale: sourceTimeScale,
            detectorTimelineScale: configuration.timelineScale,
            configuration: configuration.name,
            targetSampleFPS: configuration.targetSampleFPS,
            targetSourceSampleFPS: configuration.targetSampleFPS / max(1.0, sourceTimeScale),
            impactConfirmationPostRoll: configuration.impactConfirmationPostRoll,
            declarationPollInterval: declarationPollInterval,
            acceptanceMaxClubTopY: configuration.acceptanceMaxClubTopY,
            wallClockElapsedSeconds: wallClockElapsed,
            realtimeRatio: wallClockElapsed / max(0.001, detectorDuration),
            finalProcessingLagSeconds: finalProcessingLag,
            decodedFrames: decodedFrameCount,
            skippedDecodedFrames: max(0, decodedFrameCount - snapshot.processedFrameCount),
            processedFrames: snapshot.processedFrameCount,
            effectiveDetectorFPS: lastDetectorTime > 0 ? Double(snapshot.processedFrameCount) / lastDetectorTime : 0,
            detectorThroughputFPS: wallClockElapsed > 0 ? Double(snapshot.processedFrameCount) / wallClockElapsed : 0,
            poseSampledFrames: poseAttemptTimes.count,
            poseValidFrames: poseFeatures.count,
            averageProcessingTimeMS: snapshot.averageProcessingTimeMS,
            lastProcessingTimeMS: snapshot.lastProcessingTimeMS,
            averagePoseProcessingTimeMS: averagePoseProcessingTimeMS,
            lastPoseProcessingTimeMS: lastPoseProcessingTimeMS,
            performanceSamples: performanceSamples,
            featureSummary: featureSummary,
            candidateWindows: candidateWindows,
            impactDebugReports: impactDebugReports,
            detections: scoredDetections,
            impactCenteredDetections: scoredImpactDetections,
            hybridImpactDetections: scoredHybridImpactDetections,
            matchedCount: labels.map { $0.count - (missed?.count ?? 0) },
            missedLabelIndices: missed,
            falsePositiveCount: falsePositiveCount
        )
    }

    private static func scoreDetections(
        _ detections: [DetectedSwing],
        labels: [LabelWindow]?,
        diagnostics: [ObjectSwingWindowDiagnostics],
        declarations: [DeclarationRecord]
    ) -> [DetectionOutput] {
        detections.enumerated().map { index, detection in
            let start = CMTimeGetSeconds(detection.startTime)
            let end = CMTimeGetSeconds(detection.endTime)
            let declaredAt = declarationTime(forStart: start, end: end, declarations: declarations)
            let matched = labels?.enumerated().compactMap { index, label in
                overlaps(start, end, label.start, label.end) ? index + 1 : nil
            } ?? []
            return DetectionOutput(
                start: start,
                end: end,
                confidence: detection.confidence,
                declaredAt: declaredAt,
                latencyFromEnd: declaredAt.map { max(0, $0 - end) },
                latencyFromMatchedLabelEnd: labelEndLatency(
                    declaredAt: declaredAt,
                    matchedLabelIndices: matched,
                    labels: labels
                ),
                matchedLabelIndices: matched,
                diagnostics: diagnostics.indices.contains(index) ? diagnostics[index] : nil
            )
        }
    }

    private static func scoreImpactDetections(
        _ detections: [ObjectSwingImpactCandidate],
        labels: [LabelWindow]?,
        declarations: [DeclarationRecord],
        poseDiagnostics: [PoseWindowDiagnostics?]
    ) -> [ImpactDetectionOutput] {
        detections.enumerated().map { index, detection in
            let declaredAt = declarationTime(
                forStart: detection.start,
                end: detection.end,
                declarations: declarations,
                exactMatch: true
            ) ?? detection.declaredAt
            let matched = labels?.enumerated().compactMap { index, label in
                overlaps(detection.start, detection.end, label.start, label.end) ? index + 1 : nil
            } ?? []
            return ImpactDetectionOutput(
                start: detection.start,
                end: detection.end,
                impactTime: detection.impactTime,
                confidence: detection.confidence,
                declaredAt: declaredAt,
                latencyFromImpact: max(0, declaredAt - detection.impactTime),
                latencyFromEnd: max(0, declaredAt - detection.end),
                latencyFromMatchedLabelEnd: labelEndLatency(
                    declaredAt: declaredAt,
                    matchedLabelIndices: matched,
                    labels: labels
                ),
                matchedLabelIndices: matched,
                diagnostics: detection.diagnostics,
                poseDiagnostics: poseDiagnostics.indices.contains(index) ? poseDiagnostics[index] : nil
            )
        }
    }

    private static func labelEndLatency(
        declaredAt: Double?,
        matchedLabelIndices: [Int],
        labels: [LabelWindow]?
    ) -> Double? {
        guard let declaredAt, let labels, !matchedLabelIndices.isEmpty else { return nil }
        let matchedLabelEnd = matchedLabelIndices
            .compactMap { index -> Double? in
                let labelIndex = index - 1
                guard labels.indices.contains(labelIndex) else { return nil }
                return labels[labelIndex].end
            }
            .max()
        return matchedLabelEnd.map { max(0, declaredAt - $0) }
    }

    private static func poseDiagnostics(
        for detection: ObjectSwingImpactCandidate,
        attempts: [Double],
        features: [PoseFeature]
    ) -> PoseWindowDiagnostics? {
        let attempted = attempts.filter { $0 >= detection.start && $0 <= detection.end }
        let windowFeatures = features.filter { $0.time >= detection.start && $0.time <= detection.end }
        guard !attempted.isEmpty else { return nil }

        let coverage = Double(windowFeatures.count) / Double(attempted.count)
        let bounds = pointBounds(windowFeatures.map(\.relativeHands))
        let bodyBounds = pointBounds(windowFeatures.map(\.bodyCenter))
        let peakSpeed = peakHandSpeed(windowFeatures)
        let addressToFinishDistance = averagePoint(
            Array(windowFeatures.prefix(max(1, min(3, windowFeatures.count / 3))))
        ).map { addressPoint in
            averagePoint(
                Array(windowFeatures.suffix(max(1, min(3, windowFeatures.count / 3))))
            ).map { finishPoint in
                distance(addressPoint, finishPoint)
            } ?? 0
        } ?? 0

        return PoseWindowDiagnostics(
            attemptedSampleCount: attempted.count,
            validSampleCount: windowFeatures.count,
            coverage: coverage,
            peakHandSpeed: peakSpeed,
            handTravel: bounds.diagonal,
            verticalHandTravel: bounds.height,
            horizontalHandTravel: bounds.width,
            addressToFinishDistance: addressToFinishDistance,
            bodyDrift: bodyBounds.diagonal
        )
    }

    private static func peakHandSpeed(_ features: [PoseFeature]) -> Double {
        guard features.count >= 2 else { return 0 }

        var peak = 0.0
        for index in 1..<features.count {
            let dt = features[index].time - features[index - 1].time
            guard dt > 0, dt <= 0.6 else { continue }
            peak = max(peak, distance(features[index].relativeHands, features[index - 1].relativeHands) / dt)
        }
        return peak
    }

    private static func pointBounds(_ points: [CGPoint]) -> (width: Double, height: Double, diagonal: Double) {
        guard !points.isEmpty else { return (0, 0, 0) }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width, height, sqrt(width * width + height * height))
    }

    private static func averagePoint(_ features: [PoseFeature]) -> CGPoint? {
        guard !features.isEmpty else { return nil }
        let sum = features.reduce(CGPoint.zero) { partial, feature in
            CGPoint(
                x: partial.x + feature.relativeHands.x,
                y: partial.y + feature.relativeHands.y
            )
        }
        return CGPoint(
            x: sum.x / CGFloat(features.count),
            y: sum.y / CGFloat(features.count)
        )
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return sqrt(dx * dx + dy * dy)
    }

    private static func poseFeature(
        from sampleBuffer: CMSampleBuffer,
        at time: Double,
        orientation: CGImagePropertyOrientation,
        request: VNDetectHumanBodyPoseRequest
    ) -> PoseFeature? {
        ObjectSwingImpactSelector.poseFeature(
            from: sampleBuffer,
            at: time,
            orientation: orientation,
            request: request
        )
    }

    private static func missedLabelIndices(
        scoredDetections: [DetectionOutput],
        labels: [LabelWindow]?
    ) -> [Int]? {
        guard let labels else { return nil }
        let matched = Set(scoredDetections.flatMap(\.matchedLabelIndices))
        return labels.indices.map { $0 + 1 }.filter { !matched.contains($0) }
    }

    private static func loadLabels(path: String) throws -> [LabelWindow] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(LabelPayload.self, from: data).positiveSwingWindows
    }

    private static func overlaps(_ aStart: Double, _ aEnd: Double, _ bStart: Double, _ bEnd: Double) -> Bool {
        aStart <= bEnd && bStart <= aEnd
    }

    private static func sourceTimelineDetections(
        _ detections: [DetectedSwing],
        timeScale: Double
    ) -> [DetectedSwing] {
        detections.map { detection in
            DetectedSwing(
                startTime: CMTimeMultiplyByFloat64(detection.startTime, multiplier: timeScale),
                endTime: CMTimeMultiplyByFloat64(detection.endTime, multiplier: timeScale),
                confidence: detection.confidence,
                impactTime: detection.impactTime.map { $0 * timeScale },
                declaredAt: detection.declaredAt.map { $0 * timeScale }
            )
        }
    }

    private static func sourceTimelineImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate],
        timeScale: Double
    ) -> [ObjectSwingImpactCandidate] {
        detections.map { detection in
            ObjectSwingImpactCandidate(
                start: detection.start * timeScale,
                end: detection.end * timeScale,
                impactTime: detection.impactTime * timeScale,
                declaredAt: detection.declaredAt * timeScale,
                confidence: detection.confidence,
                diagnostics: sourceTimelineDiagnostics([detection.diagnostics], timeScale: timeScale)[0]
            )
        }
    }

    private static func recordDeclarations(
        _ detections: [DetectedSwing],
        declaredAt: Double,
        records: inout [DeclarationRecord]
    ) {
        for detection in detections {
            let start = CMTimeGetSeconds(detection.startTime)
            let end = CMTimeGetSeconds(detection.endTime)
            guard !records.contains(where: { overlaps(start, end, $0.start, $0.end) }) else {
                continue
            }
            records.append(DeclarationRecord(start: start, end: end, declaredAt: declaredAt))
        }
    }

    private static func recordImpactDeclarations(
        _ detections: [ObjectSwingImpactCandidate],
        records: inout [DeclarationRecord]
    ) {
        for detection in detections {
            guard !records.contains(where: { overlaps(detection.start, detection.end, $0.start, $0.end) }) else {
                continue
            }
            records.append(
                DeclarationRecord(
                    start: detection.start,
                    end: detection.end,
                    declaredAt: detection.declaredAt
                )
            )
        }
    }

    private static func declarationTime(
        forStart start: Double,
        end: Double,
        declarations: [DeclarationRecord],
        exactMatch: Bool = false
    ) -> Double? {
        let tolerance = 0.05
        return declarations
            .filter {
                if exactMatch {
                    return abs(start - $0.start) <= tolerance && abs(end - $0.end) <= tolerance
                }
                return overlaps(start, end, $0.start, $0.end)
            }
            .map(\.declaredAt)
            .min()
    }

    private static func sourceTimelineDiagnostics(
        _ diagnostics: [ObjectSwingWindowDiagnostics],
        timeScale: Double
    ) -> [ObjectSwingWindowDiagnostics] {
        diagnostics.map { diagnostic in
            ObjectSwingWindowDiagnostics(
                start: diagnostic.start * timeScale,
                end: diagnostic.end * timeScale,
                peakMotion: diagnostic.peakMotion,
                strongMotionFrameCount: diagnostic.strongMotionFrameCount,
                meanClubMotion: diagnostic.meanClubMotion,
                clubPathSpan: diagnostic.clubPathSpan,
                clubTopY: diagnostic.clubTopY,
                clubFrameRatio: diagnostic.clubFrameRatio,
                ballFrameRatio: diagnostic.ballFrameRatio
            )
        }
    }

    private static func sourceTimelineImpactDebugReports(
        _ reports: [ObjectSwingImpactDebugReport],
        timeScale: Double
    ) -> [ObjectSwingImpactDebugReport] {
        reports.map { report in
            ObjectSwingImpactDebugReport(
                anchorX: report.anchorX,
                anchorY: report.anchorY,
                result: report.result,
                disappearanceTime: report.disappearanceTime.map { $0 * timeScale },
                preFeatureCount: report.preFeatureCount,
                postFeatureCount: report.postFeatureCount,
                prePresence: report.prePresence,
                postPresence: report.postPresence,
                clubMinDistance: report.clubMinDistance,
                clubNearRatio: report.clubNearRatio,
                localPeakMotion: report.localPeakMotion,
                localMeanClubMotion: report.localMeanClubMotion,
                windowPeakMotion: report.windowPeakMotion,
                windowMeanClubMotion: report.windowMeanClubMotion,
                clubPathSpan: report.clubPathSpan
            )
        }
    }

    private static func performanceSample(
        sourceTime: Double,
        detectorTime: Double,
        startedAt: Date,
        decodedFrameCount: Int,
        processedFrameCount: Int,
        poseSampledFrameCount: Int
    ) -> PerformanceSample {
        let elapsed = Date().timeIntervalSince(startedAt)
        let safeDetectorTime = max(0.001, detectorTime)
        let elapsedForRate = max(0.001, elapsed)
        return PerformanceSample(
            sourceTime: sourceTime,
            detectorTime: safeDetectorTime,
            elapsedWallTime: elapsed,
            processingLag: elapsed - safeDetectorTime,
            decodedFrames: decodedFrameCount,
            processedFrames: processedFrameCount,
            poseSampledFrames: poseSampledFrameCount,
            detectorThroughputFPS: Double(processedFrameCount) / elapsedForRate,
            realtimeRatio: elapsed / safeDetectorTime
        )
    }

    private static func orientedImageSize(from sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .zero
        }

        return CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
    }

    private static func orientedVideoComposition(for track: AVAssetTrack, duration: CMTime) async throws -> AVVideoComposition {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let renderTransform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -transformedRect.minX,
                y: -transformedRect.minY
            )
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(renderTransform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(30, Int32(nominalFrameRate.rounded())))
        )
        composition.instructions = [instruction]
        return composition
    }

    private static func computeUnits(named value: String) -> MLComputeUnits {
        switch value.lowercased() {
        case "cpu", "cpuonly":
            return .cpuOnly
        case "cpuandgpu", "cpu+gpu", "gpu":
            return .cpuAndGPU
        case "cpuandneuralengine", "cpu+ne", "ne", "neuralengine":
            return .cpuAndNeuralEngine
        default:
            return .all
        }
    }

    private static func computeUnitsDescription(_ computeUnits: MLComputeUnits) -> String {
        switch computeUnits {
        case .cpuOnly:
            return "cpuOnly"
        case .cpuAndGPU:
            return "cpuAndGPU"
        case .cpuAndNeuralEngine:
            return "cpuAndNeuralEngine"
        case .all:
            return "all"
        @unknown default:
            return "unknown"
        }
    }
}

private enum EvaluationError: Error {
    case invalidDuration
    case noVideoTrack
    case readerSetupFailed
}
