//
//  SwingDetectorV3.swift
//  SwingCoach
//
//  The V3 swing detector core. Reuses GolfObjectDetector for per-frame objects,
//  runs the locked-patch + evidence-vector + state-machine pipeline, and exposes
//  the same live interface (`LiveSwingDetecting`) as the legacy detector plus a
//  few debug accessors used by the offline evaluator.
//
//  All internal logic runs in real-time seconds; inputs/outputs convert to the
//  source timeline via `configuration.sourceTimeScale`.
//

import AVFoundation
import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

nonisolated final class SwingDetectorV3: LiveSwingDetecting {
    enum DetectorError: Error {
        case modelUnavailable
    }

    private let configuration: SwingDetectorV3Configuration
    private let modelURL: URL?
    private let computeUnits: MLComputeUnits

    private var detector: GolfObjectDetector?
    private let targetSelector: TargetSelectorV3
    private let clubTracker: ClubTrackerV3
    private let decisionEngine: SwingDecisionEngineV3
    private let scorer: SwingScorer
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    private var features: [SwingObservationV3] = []
    private var detections: [DetectedSwing] = []
    private var traces: [SwingCandidateTrace] = []
    private var samplingTraces: [SwingSamplingTrace] = []
    private var observationTraces: [FrameObservationTraceV3] = []
    private var decisionTraces: [SwingDecisionTraceV3] = []
    private var previousGray: [UInt8]?
    private var lastProcessedSourceTime = -Double.greatestFiniteMagnitude
    private var lastSnapshot = LiveSwingDetectionSnapshot.idle
    private var modelLoadError: Error?
    private var processedFrameCount = 0
    private var skippedFrameCount = 0
    private var totalProcessingMS = 0.0
    private var lastProcessingMS = 0.0
    private var nextCandidateId = 1
    private var enabled = false
    private var startupInFlightResolved = false
    private var startupEvaluatedImpactTimes: [Double] = []
    private var lastPracticeSwingRealTime = -Double.greatestFiniteMagnitude

    private let featureRetentionLimit = 4_000
    private let startupInFlightEndRealTime = 2.25
    private let startupInFlightResolveEndRealTime = 2.90
    private let startupInFlightMinBallY: CGFloat = 0.0

    init(
        configuration: SwingDetectorV3Configuration = .live(),
        modelURL: URL? = nil,
        computeUnits: MLComputeUnits = .all
    ) {
        self.configuration = configuration
        self.modelURL = modelURL
        self.computeUnits = computeUnits
        self.targetSelector = TargetSelectorV3()
        self.clubTracker = ClubTrackerV3()
        self.decisionEngine = SwingDecisionEngineV3(configuration: configuration)
        self.scorer = configuration.scorer
    }

    // MARK: - Sampling

    /// Desired sampling interval in SOURCE seconds (the timeline incoming
    /// timestamps live in). Burst rate while the machine is armed.
    func currentSampleInterval(recordingTime: Double? = nil) -> Double {
        let realTime = configuration.realTime(fromSource: recordingTime ?? features.last?.sourceTime ?? 0)
        let realInterval = wantsBurstSampling(atRealTime: realTime)
            ? configuration.burstSampleInterval
            : configuration.lowSampleInterval
        return configuration.sourceInterval(forRealInterval: realInterval)
    }

    private func wantsStartupBurst(atRealTime realTime: Double) -> Bool {
        realTime <= configuration.startupBurstDuration + 0.0001
    }

    private func wantsBurstSampling(atRealTime realTime: Double) -> Bool {
        wantsStartupBurst(atRealTime: realTime) || decisionEngine.wantsBurst(atRealTime: realTime)
    }

    // MARK: - LiveSwingDetecting

    func reset(enabled: Bool) {
        self.enabled = enabled
        features.removeAll(keepingCapacity: true)
        detections.removeAll(keepingCapacity: true)
        traces.removeAll(keepingCapacity: true)
        samplingTraces.removeAll(keepingCapacity: true)
        observationTraces.removeAll(keepingCapacity: true)
        decisionTraces.removeAll(keepingCapacity: true)
        previousGray = nil
        lastProcessedSourceTime = -Double.greatestFiniteMagnitude
        modelLoadError = nil
        processedFrameCount = 0
        skippedFrameCount = 0
        totalProcessingMS = 0
        lastProcessingMS = 0
        nextCandidateId = 1
        startupInFlightResolved = false
        startupEvaluatedImpactTimes.removeAll(keepingCapacity: true)
        lastPracticeSwingRealTime = -Double.greatestFiniteMagnitude
        targetSelector.reset()
        clubTracker.reset()
        decisionEngine.reset()

        guard enabled else {
            detector = nil
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .disabled,
                primaryMessage: "Auto detect off",
                detailMessage: "Recording normally; trim manually after stop.",
                detectorConfigurationName: configuration.name
            )
            return
        }

        do {
            detector = try GolfObjectDetector(modelURL: modelURL, computeUnits: computeUnits)
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .searchingBall,
                primaryMessage: "v3 detector ready",
                detailMessage: "Scanning sampled frames while recording.",
                targetSampleFPS: configuration.lowSampleFPS,
                detectorConfigurationName: configuration.name
            )
        } catch {
            detector = nil
            modelLoadError = error
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "v3 detector unavailable",
                detailMessage: "The YOLO Core ML model could not be loaded.",
                detectorConfigurationName: configuration.name
            )
        }
    }

    @discardableResult
    func process(
        sampleBuffer: CMSampleBuffer,
        recordingTime: Double,
        orientation: CGImagePropertyOrientation,
        orientedImageSize: CGSize
    ) -> LiveSwingDetectionSnapshot {
        let sampleInterval = currentSampleInterval(recordingTime: recordingTime)
        guard recordingTime.isFinite,
              recordingTime - lastProcessedSourceTime + 0.0001 >= sampleInterval
        else {
            skippedFrameCount += 1
            return lastSnapshot
        }
        lastProcessedSourceTime = recordingTime

        guard let detector else {
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "v3 detector unavailable",
                detailMessage: modelLoadError == nil ? "Detector not started." : "Model failed to load.",
                detectorConfigurationName: configuration.name
            )
            return lastSnapshot
        }

        let startedAt = Date()
        let realTime = configuration.realTime(fromSource: recordingTime)
        let startupBurstActiveForFrame = wantsStartupBurst(atRealTime: realTime)
        let stateBurstActiveForFrame = decisionEngine.wantsBurst(atRealTime: realTime)
        let burstActiveForFrame = startupBurstActiveForFrame || stateBurstActiveForFrame
        let targetFPSForFrame = burstActiveForFrame ? configuration.burstSampleFPS : configuration.lowSampleFPS
        let stateBeforeFrame = decisionEngine.state.rawValue

        let gray = Self.downsampledLuma(from: sampleBuffer)
        let lumaMotion = Self.visualMotion(current: gray, previous: previousGray)
        previousGray = gray

        let objects: [GolfObjectDetection]
        do {
            objects = try detector.detect(
                in: sampleBuffer,
                orientation: orientation,
                orientedImageSize: orientedImageSize
            )
        } catch {
            modelLoadError = error
            recordProcessing(startedAt: startedAt)
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "v3 detector unavailable",
                detailMessage: "The YOLO model failed on a frame.",
                detectorConfigurationName: configuration.name
            )
            return lastSnapshot
        }

        let pose = detectPoseSample(in: sampleBuffer, orientation: orientation)
        let frame = SwingObservationV3(
            realTime: realTime,
            sourceTime: recordingTime,
            detections: objects,
            humanPoseConfidence: pose.coreJointConfidence,
            handHeight: pose.handHeight,
            wristPoint: pose.wristPoint,
            torsoHeight: pose.torsoHeight,
            lumaMotion: lumaMotion
        )
        features.append(frame)
        if features.count > featureRetentionLimit {
            features.removeFirst(features.count - featureRetentionLimit)
        }

        let lock = targetSelector.update(
            frame: frame,
            recent: features,
            // Target identity becomes immutable once a motion episode starts.
            allowsRetargeting: decisionEngine.state == .addressed,
            monitorsAddressHold: decisionEngine.state == .addressed
        )
        if configuration.recordsDebugTrace {
            observationTraces.append(
                FrameObservationTraceV3(
                    sourceTime: recordingTime,
                    realTime: realTime,
                    poseConfidence: frame.humanPoseConfidence,
                    wristX: frame.wristPoint.map { Double($0.x) },
                    wristY: frame.wristPoint.map { Double($0.y) },
                    torsoHeight: frame.torsoHeight,
                    objects: objects.map {
                        ObjectObservationTraceV3(
                            kind: $0.objectClass.name,
                            confidence: $0.confidence,
                            x: $0.rect.minX,
                            y: $0.rect.minY,
                            width: $0.rect.width,
                            height: $0.rect.height
                        )
                    },
                    ballTracks: targetSelector.latestSceneSnapshot?.ballTracks ?? [],
                    selectedTargetID: lock?.targetID
                )
            )
            if observationTraces.count > featureRetentionLimit {
                observationTraces.removeFirst(observationTraces.count - featureRetentionLimit)
            }
        }
        samplingTraces.append(
            SwingSamplingTrace(
                sourceTime: recordingTime,
                realTime: realTime,
                targetFPS: targetFPSForFrame,
                burstActive: burstActiveForFrame,
                startupBurstActive: startupBurstActiveForFrame,
                stateBurstActive: stateBurstActiveForFrame,
                stateBeforeFrame: stateBeforeFrame,
                lockCenterX: lock.map { Double($0.ballCenter.x) },
                lockCenterY: lock.map { Double($0.ballCenter.y) },
                lockRevision: lock?.revision,
                lockSelectionReason: lock?.selectionReason,
                lockCurrentClubheadAssociationScore: lock?.currentClubheadAssociationScore,
                lockEndpointCouplingScore: lock?.endpointCouplingScore,
                lockBallConfidence: lock?.ballConfidence,
                addressBallCount: lock?.addressBallCount
            )
        )
        clubTracker.update(frame: frame, lock: lock)
        let patch = lock.map { TargetRegionObserverV3.observe(frame: frame, lock: $0) }
        let clubWindowSamples = featuresInWindow(
            start: max(0, realTime - configuration.clubEvidenceWindowDuration),
            end: realTime
        )
        let clubWindow = clubTracker.evidence(in: clubWindowSamples[...], lock: lock)

        if let resolved = decisionEngine.update(frame: frame, lock: lock, patch: patch, club: clubWindow) {
            evaluate(resolved: resolved, club: clubWindow)
        }
        evaluateStartupInFlightIfNeeded(frame: frame, lock: lock)
        evaluatePracticeSwingIfNeeded(frame: frame)

        recordProcessing(startedAt: startedAt)
        lastSnapshot = makeSnapshot(frame: frame, lock: lock, targetFPS: targetFPSForFrame)
        return lastSnapshot
    }

    func finish(recordingTime: Double?) -> [DetectedSwing] {
        appendProgressTraceIfNeeded()
        return detections
    }

    func currentSnapshot() -> LiveSwingDetectionSnapshot {
        lastSnapshot
    }

    // MARK: - Debug accessors (offline evaluator)

    func currentDetections() -> [DetectedSwing] { detections }
    func currentTraces() -> [SwingCandidateTrace] { traces }
    func currentSamplingTrace() -> [SwingSamplingTrace] { samplingTraces }
    func currentObservationTrace() -> [FrameObservationTraceV3] { observationTraces }
    func currentDecisionTrace() -> [SwingDecisionTraceV3] { decisionTraces }
    var configurationName: String { configuration.name }
    var averageProcessingMS: Double { processedFrameCount > 0 ? totalProcessingMS / Double(processedFrameCount) : 0 }
    var processedFrames: Int { processedFrameCount }

    // MARK: - Candidate evaluation

    /// detectSwings design: the pose full-swing pattern (top → dip → finish)
    /// carries the swing conviction on its own; ball logic then splits real
    /// shots from practice swings. Ball-departure swings are handled by the
    /// main candidate path, so any full-swing pattern left over — with a club
    /// anchored near the wrists and no ball event nearby — is a practice
    /// swing. A dip confirms ~2.5s after impact once its finish is observed.
    private func evaluatePracticeSwingIfNeeded(frame: SwingObservationV3) {
        guard configuration.allowsPracticeSwings else { return }

        let samples = featuresInWindow(
            start: max(0, frame.realTime - 10.0),
            end: frame.realTime
        )
        for dip in FullSwingPatternV3.confirmedDips(in: samples) {
            guard dip - lastPracticeSwingRealTime >= max(3.0, configuration.minImpactGap) else { continue }

            let coveredByContactSwing = detections.contains { detection in
                guard let impactTime = detection.impactTime else { return false }
                return abs(configuration.realTime(fromSource: impactTime) - dip) <= 3.0
            }
            if coveredByContactSwing {
                lastPracticeSwingRealTime = dip
                continue
            }

            guard FullSwingPatternV3.swungClubVisible(around: dip, in: samples) else { continue }

            let impactSource = configuration.sourceTime(fromReal: dip)
            let startSource = max(0, impactSource - configuration.sourceTime(fromReal: configuration.impactPreRoll))
            let endSource = impactSource + configuration.sourceTime(fromReal: configuration.impactPostRoll)
            detections.append(
                DetectedSwing(
                    startTime: CMTime(seconds: startSource, preferredTimescale: 600),
                    endTime: CMTime(seconds: endSource, preferredTimescale: 600),
                    confidence: 0.9,
                    impactTime: impactSource,
                    declaredAt: frame.sourceTime
                )
            )
            lastPracticeSwingRealTime = dip
        }
    }

    private func evaluate(resolved: ResolvedSwingCandidateV3, club: ClubEvidenceV3) {
        let candidateWindow = featuresInWindow(
            start: max(0, resolved.impactRealTime - 1.45),
            end: resolved.impactRealTime + 0.55
        )
        let candidateClub = clubTracker.evidence(in: candidateWindow[...], lock: resolved.lock)
        let presence = candidatePresence(in: candidateWindow)
        let departure = departureEvidence(
            impactRealTime: resolved.impactRealTime,
            lock: resolved.lock
        )
        let useAccumulatedSwingEvidence = resolved.swingDuration > configuration.swingTimeout
            && configuration.sourceTimeScale > 1.0
            && resolved.bestArc >= 0.75
            && resolved.bestSequence < 0.20
        let evidence = EvidenceVector(
            anchorStability: resolved.lock?.stabilityScore ?? 0,
            disappearancePersistence: departure.targetSlotDeparture,
            clubSweptThrough: max(club.sweepScore, candidateClub.sweepScore, useAccumulatedSwingEvidence ? resolved.bestSweep : 0),
            swingArc: max(club.arcScore, candidateClub.arcScore, useAccumulatedSwingEvidence ? resolved.bestArc : 0),
            swingSequence: max(club.swingSequenceScore, candidateClub.swingSequenceScore, useAccumulatedSwingEvidence ? resolved.bestSequence : 0),
            // Scene-wide ball counts are unrelated when spare and downrange
            // balls remain visible. V3 decides contact at the frozen target.
            ballInventoryDrop: nil,
            audioTransient: nil,
            poseConsistency: presence.humanConfidence
        )
        let score = scorer.score(evidence)
        let poseStrokeMotion = poseStrokeMotionScore(in: candidateWindow)
        let strongPhysicalContact = evidence.disappearancePersistence >= 0.80
            && evidence.clubSweptThrough >= 0.75
            && evidence.swingArc >= 0.70
            && (resolved.lock?.clubAssociationScore ?? 0) >= 0.35
        let hasGolfStrokeMotion = (poseStrokeMotion ?? 1) >= 0.50
        let accepted = hasGolfStrokeMotion
            && (score >= scorer.threshold || strongPhysicalContact)
            && evidence.disappearancePersistence >= 0.35
            && (evidence.swingSequence ?? 1) > 0
            && presence.hasHuman
            && presence.hasClub
        let outcome: ContactOutcomeV3 = accepted
            ? .strikeSupported
            : (poseStrokeMotion != nil && !hasGolfStrokeMotion ? .nonContactSupported : .unresolved)
        decisionTraces.append(
            SwingDecisionTraceV3(
                candidateID: nextCandidateId,
                targetID: resolved.lock?.targetID,
                impactSourceTime: configuration.sourceTime(fromReal: resolved.impactRealTime),
                declaredSourceTime: features.last?.sourceTime,
                outcome: outcome,
                poseStrokeMotionScore: poseStrokeMotion,
                score: score
            )
        )
        let failure = primaryFailure(evidence: evidence, accepted: accepted)

        let lockTrace = resolved.lock.map { lock in
            SwingAddressLockTrace(
                lockedAtReal: lock.lockedAtReal,
                lockedAtSource: configuration.sourceTime(fromReal: lock.lockedAtReal),
                centerX: Double(lock.ballCenter.x),
                centerY: Double(lock.ballCenter.y),
                stabilityScore: lock.stabilityScore,
                clubAssociationScore: lock.clubAssociationScore,
                revision: lock.revision,
                selectionReason: lock.selectionReason,
                currentClubheadAssociationScore: lock.currentClubheadAssociationScore,
                endpointCouplingScore: lock.endpointCouplingScore,
                ballConfidence: lock.ballConfidence,
                addressBallCount: lock.addressBallCount
            )
        }

        traces.append(
            SwingCandidateTrace(
                candidateId: nextCandidateId,
                stateReached: "impactCandidate",
                impactRealTime: resolved.impactRealTime,
                impactSourceTime: configuration.sourceTime(fromReal: resolved.impactRealTime),
                addressLock: lockTrace,
                departure: departure.trace,
                evidence: evidence,
                score: score,
                accepted: accepted,
                primaryFailure: failure
            )
        )
        nextCandidateId += 1

        guard accepted else {
            targetSelector.suppressLocks(until: resolved.impactRealTime + configuration.minImpactGap)
            return
        }

        let impactSource = configuration.sourceTime(fromReal: resolved.impactRealTime)
        let startSource = max(0, impactSource - configuration.sourceTime(fromReal: configuration.impactPreRoll))
        let endSource = impactSource + configuration.sourceTime(fromReal: configuration.impactPostRoll)

        detections.append(
            DetectedSwing(
                startTime: CMTime(seconds: startSource, preferredTimescale: 600),
                endTime: CMTime(seconds: endSource, preferredTimescale: 600),
                confidence: score,
                impactTime: impactSource,
                declaredAt: features.last?.sourceTime
            )
        )
        decisionEngine.didConfirm(impactRealTime: resolved.impactRealTime)
        targetSelector.suppressLocks(until: resolved.impactRealTime + configuration.minImpactGap)
    }

    private func evaluateStartupInFlightIfNeeded(frame: SwingObservationV3, lock: TargetLockV3?) {
        guard !startupInFlightResolved,
              detections.isEmpty,
              lock == nil,
              frame.realTime <= startupInFlightResolveEndRealTime
        else {
            return
        }

        guard let candidate = startupInFlightCandidate(atRealTime: frame.realTime) else {
            return
        }
        guard !startupEvaluatedImpactTimes.contains(where: { abs($0 - candidate.impactRealTime) < 0.18 }) else {
            return
        }
        startupEvaluatedImpactTimes.append(candidate.impactRealTime)

        let candidateWindow = featuresInWindow(
            start: max(0, candidate.impactRealTime - 1.35),
            end: candidate.impactRealTime + 0.55
        )
        let club = clubTracker.evidence(in: candidateWindow[...], lock: candidate.lock)
        let presence = candidatePresence(in: candidateWindow)
        let departure = departureEvidence(
            impactRealTime: candidate.impactRealTime,
            lock: candidate.lock
        )
        let evidence = EvidenceVector(
            anchorStability: candidate.lock.stabilityScore,
            disappearancePersistence: departure.targetSlotDeparture,
            clubSweptThrough: club.sweepScore,
            swingArc: club.arcScore,
            swingSequence: club.swingSequenceScore,
            ballInventoryDrop: nil,
            audioTransient: nil,
            poseConsistency: presence.humanConfidence
        )
        let score = scorer.score(evidence)
        let strongStartupSwing = evidence.clubSweptThrough >= 0.62
            && evidence.swingArc >= 0.52
        let startupThreshold = strongStartupSwing ? scorer.threshold - 0.05 : scorer.threshold
        let accepted = score >= startupThreshold
            && evidence.disappearancePersistence >= 0.35
            && ((evidence.swingSequence ?? 0) > 0 || strongStartupSwing)
            && presence.hasHuman
            && presence.hasClub
        let failure = primaryFailure(evidence: evidence, accepted: accepted)

        traces.append(
            SwingCandidateTrace(
                candidateId: nextCandidateId,
                stateReached: "startupInFlight",
                impactRealTime: candidate.impactRealTime,
                impactSourceTime: configuration.sourceTime(fromReal: candidate.impactRealTime),
                addressLock: trace(for: candidate.lock),
                departure: departure.trace,
                evidence: evidence,
                score: score,
                accepted: accepted,
                primaryFailure: failure
            )
        )
        nextCandidateId += 1

        guard accepted else { return }

        startupInFlightResolved = true
        let impactSource = configuration.sourceTime(fromReal: candidate.impactRealTime)
        let startSource = max(0, impactSource - configuration.sourceTime(fromReal: configuration.impactPreRoll))
        let endSource = impactSource + configuration.sourceTime(fromReal: configuration.impactPostRoll)
        detections.append(
            DetectedSwing(
                startTime: CMTime(seconds: startSource, preferredTimescale: 600),
                endTime: CMTime(seconds: endSource, preferredTimescale: 600),
                confidence: score,
                impactTime: impactSource,
                declaredAt: features.last?.sourceTime
            )
        )
        targetSelector.suppressLocks(until: candidate.impactRealTime + configuration.minImpactGap)
        decisionEngine.didConfirm(impactRealTime: candidate.impactRealTime)
    }

    private func startupInFlightCandidate(atRealTime now: Double) -> StartupInFlightCandidate? {
        let startupFrames = features.filter { $0.realTime <= min(now, startupInFlightResolveEndRealTime) }
        guard startupFrames.count >= 4 else { return nil }

        let clusters = startupBallClusters(in: startupFrames)
        let scored = clusters.compactMap { cluster -> StartupInFlightCandidate? in
            let lock = startupLock(from: cluster)
            let observations = startupFrames.map { frame in
                (frame: frame, observation: TargetRegionObserverV3.observe(frame: frame, lock: lock))
            }

            for index in observations.indices {
                let frame = observations[index].frame
                guard frame.realTime <= startupInFlightEndRealTime else { continue }
                guard !observations[index].observation.isPresent else { continue }

                let pre = observations[..<index]
                let post = observations[index...]
                let prePresent = pre.filter { $0.observation.isPresent }.count
                guard prePresent >= 2 else { continue }
                guard frame.realTime - cluster.firstRealTime >= 0.18 else { continue }

                let postFrames = post.filter { $0.observation.isReadable }
                guard !postFrames.isEmpty else { continue }
                guard postFrames.count >= 2 || now - frame.realTime >= 0.28 else { continue }
                let postAbsent = postFrames.filter { $0.observation == .clearAbsent }.count
                let postAbsentRatio = Double(postAbsent) / Double(max(1, postFrames.count))
                guard postAbsentRatio >= 0.50 else { continue }

                let window = featuresInWindow(
                    start: max(0, frame.realTime - 1.15),
                    end: frame.realTime + 0.35
                )
                let club = clubTracker.evidence(in: window[...], lock: lock)
                guard club.sweepScore >= 0.30, club.arcScore >= 0.24 else { continue }

                let score = club.sweepScore * 0.34
                    + club.arcScore * 0.26
                    + club.swingSequenceScore * 0.16
                    + cluster.stabilityScore * 0.12
                    + postAbsentRatio * 0.12
                return StartupInFlightCandidate(
                    impactRealTime: frame.realTime,
                    lock: lock,
                    score: score
                )
            }
            return nil
        }

        return scored.max(by: { $0.score < $1.score })
    }

    private func startupBallClusters(in frames: [SwingObservationV3]) -> [StartupBallClusterV3] {
        var clusters: [StartupBallClusterV3] = []
        for frame in frames where frame.realTime <= startupInFlightEndRealTime {
            for ball in frame.balls where ball.confidence >= 0.30 && ball.center.y >= startupInFlightMinBallY {
                if let index = clusters.firstIndex(where: { GeometryV3.distance($0.center, ball.center) <= 0.050 }) {
                    clusters[index].append(ball: ball, frame: frame)
                } else {
                    clusters.append(StartupBallClusterV3(ball: ball, frame: frame))
                }
            }
        }
        return clusters.filter { $0.frameCount >= 2 }
    }

    private func startupLock(from cluster: StartupBallClusterV3) -> TargetLockV3 {
        TargetLockV3(
            patchRect: Self.patchRect(center: cluster.center, meanRect: cluster.meanRect),
            ballCenter: cluster.center,
            lockedAtReal: cluster.firstRealTime,
            stabilityScore: cluster.stabilityScore,
            clubAssociationScore: 0.50,
            revision: 0,
            selectionReason: "startup_inflight_anchor",
            currentClubheadAssociationScore: 0,
            endpointCouplingScore: 0,
            ballConfidence: cluster.meanConfidence,
            addressBallCount: cluster.addressBallCount
        )
    }

    private func trace(for lock: TargetLockV3) -> SwingAddressLockTrace {
        SwingAddressLockTrace(
            lockedAtReal: lock.lockedAtReal,
            lockedAtSource: configuration.sourceTime(fromReal: lock.lockedAtReal),
            centerX: Double(lock.ballCenter.x),
            centerY: Double(lock.ballCenter.y),
            stabilityScore: lock.stabilityScore,
            clubAssociationScore: lock.clubAssociationScore,
            revision: lock.revision,
            selectionReason: lock.selectionReason,
            currentClubheadAssociationScore: lock.currentClubheadAssociationScore,
            endpointCouplingScore: lock.endpointCouplingScore,
            ballConfidence: lock.ballConfidence,
            addressBallCount: lock.addressBallCount
        )
    }

    // MARK: - Snapshot

    private func makeSnapshot(frame: SwingObservationV3, lock: TargetLockV3?, targetFPS: Double) -> LiveSwingDetectionSnapshot {
        let status: LiveSwingDetectionStatus
        let primary: String
        switch decisionEngine.state {
        case .idle:
            status = lock == nil ? .searchingBall : .ballLocked
            primary = lock == nil ? "v3 scanning" : "Address locked"
        case .addressed:
            status = .ballLocked
            primary = "Address locked"
        case .swinging, .impactCandidate:
            status = .swingInProgress
            primary = "Swing in progress"
        case .cooldown:
            status = .swingDetected
            primary = "\(detections.count) swing\(detections.count == 1 ? "" : "s") detected"
        }

        return LiveSwingDetectionSnapshot(
            status: status,
            primaryMessage: primary,
            detailMessage: "v3",
            detectedSwingCount: detections.count,
            hasBallLock: lock != nil,
            processedFrameCount: processedFrameCount,
            skippedFrameCount: skippedFrameCount,
            targetSampleFPS: targetFPS,
            averageProcessingTimeMS: averageProcessingMS,
            lastProcessingTimeMS: lastProcessingMS,
            detectorConfigurationName: configuration.name
        )
    }

    private func candidatePresence(
        in window: [SwingObservationV3]
    ) -> (hasHuman: Bool, hasClub: Bool, humanConfidence: Double) {
        guard !window.isEmpty else { return (false, false, 0) }

        let humanFrames = window.filter { $0.humanPoseConfidence >= 0.45 }.count
        let requiredHumanFrames = max(2, Int((Double(window.count) * 0.18).rounded(.up)))
        let humanConfidence = window.map(\.humanPoseConfidence).max() ?? 0

        let clubFrames = window.filter { $0.bestClubScore >= 0.32 }.count
        let requiredClubFrames = max(3, Int((Double(window.count) * 0.12).rounded(.up)))

        return (
            humanFrames >= requiredHumanFrames,
            clubFrames >= requiredClubFrames,
            humanConfidence
        )
    }

    private struct PoseSampleV3 {
        var coreJointConfidence: Double = 0
        var handHeight: Double?
        var wristPoint: CGPoint?
        var torsoHeight: Double?
    }

    private func detectPoseSample(
        in sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) -> PoseSampleV3 {
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([bodyPoseRequest])
            guard let observation = bodyPoseRequest.results?.first else { return PoseSampleV3() }
            let points = try observation.recognizedPoints(.all)
            let coreJoints: [VNHumanBodyPoseObservation.JointName] = [
                .neck,
                .leftShoulder,
                .rightShoulder,
                .root,
                .leftHip,
                .rightHip,
                .leftKnee,
                .rightKnee
            ]
            let visible = coreJoints.filter { joint in
                (points[joint]?.confidence ?? 0) >= 0.25
            }.count
            var pose = PoseSampleV3(coreJointConfidence: Double(visible) / Double(coreJoints.count))

            // detectSwings hand-height signal: mean wrist height above the
            // hips, in torso units. Requires the shoulder/hip core and at
            // least one wrist to be confidently tracked.
            guard let leftShoulder = points[.leftShoulder],
                  let rightShoulder = points[.rightShoulder],
                  let leftHip = points[.leftHip],
                  let rightHip = points[.rightHip],
                  min(leftShoulder.confidence, rightShoulder.confidence,
                      leftHip.confidence, rightHip.confidence) >= 0.3
            else {
                return pose
            }
            let wrists = [points[.leftWrist], points[.rightWrist]]
                .compactMap { $0 }
                .filter { $0.confidence >= 0.3 }
            guard !wrists.isEmpty else { return pose }

            // Vision points are normalized with a bottom-left origin, so
            // shoulders sit at a larger y than hips.
            let hipY = (leftHip.location.y + rightHip.location.y) / 2
            let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
            let torso = shoulderY - hipY
            guard torso > 0.02 else { return pose }

            let wristY = wrists.map(\.location.y).reduce(0, +) / Double(wrists.count)
            let wristX = wrists.map(\.location.x).reduce(0, +) / Double(wrists.count)
            pose.handHeight = (wristY - hipY) / torso
            // Flip into the top-left-origin space YOLO detection rects use.
            pose.wristPoint = CGPoint(x: wristX, y: 1 - wristY)
            pose.torsoHeight = torso
            return pose
        } catch {
            return PoseSampleV3()
        }
    }

    private func recordProcessing(startedAt: Date) {
        lastProcessingMS = Date().timeIntervalSince(startedAt) * 1_000
        totalProcessingMS += lastProcessingMS
        processedFrameCount += 1
    }

    private func appendProgressTraceIfNeeded() {
        guard traces.isEmpty, !features.isEmpty else { return }

        let lock = targetSelector.currentLock
        let recent = featuresInWindow(
            start: max(0, (features.last?.realTime ?? 0) - configuration.clubEvidenceWindowDuration),
            end: features.last?.realTime ?? 0
        )
        let club = clubTracker.evidence(in: recent[...], lock: lock)
        let evidence = EvidenceVector(
            anchorStability: lock?.stabilityScore ?? 0,
            disappearancePersistence: 0,
            clubSweptThrough: club.sweepScore,
            swingArc: club.arcScore,
            swingSequence: club.swingSequenceScore,
            ballInventoryDrop: nil,
            audioTransient: nil,
            poseConsistency: nil
        )
        let score = scorer.score(evidence)
        let lockTrace = lock.map { lock in
            SwingAddressLockTrace(
                lockedAtReal: lock.lockedAtReal,
                lockedAtSource: configuration.sourceTime(fromReal: lock.lockedAtReal),
                centerX: Double(lock.ballCenter.x),
                centerY: Double(lock.ballCenter.y),
                stabilityScore: lock.stabilityScore,
                clubAssociationScore: lock.clubAssociationScore,
                revision: lock.revision,
                selectionReason: lock.selectionReason,
                currentClubheadAssociationScore: lock.currentClubheadAssociationScore,
                endpointCouplingScore: lock.endpointCouplingScore,
                ballConfidence: lock.ballConfidence,
                addressBallCount: lock.addressBallCount
            )
        }
        traces.append(
            SwingCandidateTrace(
                candidateId: nextCandidateId,
                stateReached: decisionEngine.bestStateReached.rawValue,
                impactRealTime: nil,
                impactSourceTime: nil,
                addressLock: lockTrace,
                departure: nil,
                evidence: evidence,
                score: score,
                accepted: false,
                primaryFailure: progressFailure(lock: lock)
            )
        )
        nextCandidateId += 1
    }

    private func progressFailure(lock: TargetLockV3?) -> SwingPrimaryFailure {
        guard lock != nil else { return .noAddressLock }
        switch decisionEngine.bestStateReached {
        case .idle:
            return .noAddressLock
        case .addressed:
            return .noClubSweep
        case .swinging:
            return .timedOut
        case .impactCandidate:
            return .temporaryOcclusion
        case .cooldown:
            return .belowThreshold
        }
    }

    private func primaryFailure(evidence: EvidenceVector, accepted: Bool) -> SwingPrimaryFailure {
        if accepted { return .none }
        if (evidence.poseConsistency ?? 0) < 0.35 { return .noHuman }
        if evidence.anchorStability < 0.25 { return .noAddressLock }
        if evidence.disappearancePersistence < 0.35 { return .ballReappeared }
        if evidence.clubSweptThrough < 0.45 { return .noClubSweep }
        if (evidence.swingSequence ?? 0) < 0.35 { return .noSwingSequence }
        if evidence.swingArc < 0.35 { return .lowSwingArc }
        return .belowThreshold
    }

    private func featuresInWindow(start: Double, end: Double) -> [SwingObservationV3] {
        features.filter { $0.realTime >= start && $0.realTime <= end }
    }

    /// Full swings move the wrists through a large path relative to the
    /// golfer's torso. This rejects ball nudges and setup motions that can still
    /// make a target disappear. Nil means pose was too sparse to judge.
    private func poseStrokeMotionScore(in window: [SwingObservationV3]) -> Double? {
        let samples = window.compactMap { frame -> (CGPoint, Double)? in
            guard let wrist = frame.wristPoint, let torso = frame.torsoHeight, torso >= 0.035 else { return nil }
            return (wrist, torso)
        }
        guard samples.count >= 4 else { return nil }
        let sortedTorsos = samples.map(\.1).sorted()
        let torso = sortedTorsos[sortedTorsos.count / 2]
        let xs = samples.map { $0.0.x }
        let ys = samples.map { $0.0.y }
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        let pathSpanInTorsoUnits = hypot(width, height) / torso
        return GeometryV3.ramp(pathSpanInTorsoUnits, low: 0.75, high: 1.65)
    }

    private func departureEvidence(impactRealTime: Double, lock: TargetLockV3?) -> DepartureEvidence {
        guard let lock else { return .zero }

        let preStart = max(0, impactRealTime - 0.85)
        let preEnd = max(preStart, impactRealTime - 0.04)
        let postStart = impactRealTime + 0.04
        let postEnd = impactRealTime + 0.52

        let pre = featuresInWindow(start: preStart, end: preEnd)
        let post = featuresInWindow(start: postStart, end: postEnd)
        guard !pre.isEmpty, !post.isEmpty else { return .zero }

        let prePresent = pre.reduce(0) { count, frame in
            count + (TargetRegionObserverV3.observe(frame: frame, lock: lock).isPresent ? 1 : 0)
        }
        let postFrames = post.filter { TargetRegionObserverV3.observe(frame: $0, lock: lock).isReadable }
        guard !postFrames.isEmpty else { return .zero }
        let postAbsent = postFrames.reduce(0) { count, frame in
            count + (TargetRegionObserverV3.observe(frame: frame, lock: lock) == .clearAbsent ? 1 : 0)
        }

        let preRatio = Double(prePresent) / Double(pre.count)
        let postRatio = Double(postAbsent) / Double(postFrames.count)
        let preScore = GeometryV3.ramp(preRatio, low: 0.45, high: 0.84)
        let postScore = GeometryV3.ramp(postRatio, low: 0.58, high: 0.94)
        let targetSlotDeparture = min(1, max(0, preScore * postScore))

        return DepartureEvidence(
            targetSlotDeparture: targetSlotDeparture,
            trace: SwingDepartureTrace(
                preTargetPresenceRatio: preRatio,
                postTargetAbsenceRatio: postRatio,
                // These V2 compatibility fields remain in the trace schema,
                // but V3 never computes or uses scene-wide ball inventory.
                preBallInventory: 0,
                postBallInventory: 0,
                ballInventoryDropScore: 0,
                ballInventoryDropFrameRatio: 0,
                longestBallInventoryDropRun: 0
            )
        )
    }

    private static func patchRect(center: CGPoint, meanRect: CGRect) -> CGRect {
        let baseWidth = max(0.030, meanRect.width * 3.6)
        let baseHeight = max(0.030, meanRect.height * 3.6)
        let width = min(0.18, baseWidth)
        let height = min(0.18, baseHeight)
        let x = min(max(0, center.x - width / 2), 1 - width)
        let y = min(max(0, center.y - height / 2), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Cheap luma motion

    private static func downsampledLuma(from sampleBuffer: CMSampleBuffer) -> [UInt8]? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }

        let sourceWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let sourceHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let width = 80
        let height = 120

        return (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            let sourceX = min(sourceWidth - 1, x * sourceWidth / width)
            let sourceY = min(sourceHeight - 1, y * sourceHeight / height)
            return pixels[sourceY * bytesPerRow + sourceX]
        }
    }

    private static func visualMotion(current: [UInt8]?, previous: [UInt8]?) -> Double {
        guard let current, let previous, current.count == previous.count else { return 0 }
        let total = zip(current, previous).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(current.count) / 255.0
    }
}

nonisolated private struct DepartureEvidence: Equatable {
    let targetSlotDeparture: Double
    let trace: SwingDepartureTrace?

    static let zero = DepartureEvidence(
        targetSlotDeparture: 0,
        trace: nil
    )
}

nonisolated private struct StartupInFlightCandidate: Equatable {
    let impactRealTime: Double
    let lock: TargetLockV3
    let score: Double
}

nonisolated private struct StartupBallClusterV3: Equatable {
    private(set) var weightedX: CGFloat
    private(set) var weightedY: CGFloat
    private(set) var totalWeight: CGFloat
    private(set) var rects: [CGRect]
    private(set) var confidences: [Double]
    private(set) var centers: [CGPoint]
    private(set) var frameTimes: [Double]
    private(set) var addressBallCounts: [Int]

    init(ball: GolfObjectDetection, frame: SwingObservationV3) {
        let weight = CGFloat(max(0.001, ball.confidence))
        weightedX = ball.center.x * weight
        weightedY = ball.center.y * weight
        totalWeight = weight
        rects = [ball.rect]
        confidences = [ball.confidence]
        centers = [ball.center]
        frameTimes = [frame.realTime]
        addressBallCounts = [Self.lowBallCount(in: frame)]
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

    var frameCount: Int { frameTimes.count }
    var firstRealTime: Double { frameTimes.min() ?? 0 }
    var addressBallCount: Int { addressBallCounts.max() ?? 1 }

    var stabilityScore: Double {
        let span = Self.pathSpan(centers)
        let stillness = GeometryV3.inverseRamp(span, low: 0.012, high: 0.075)
        let persistence = GeometryV3.ramp(Double(frameCount), low: 2, high: 5)
        let confidence = GeometryV3.ramp(meanConfidence, low: 0.30, high: 0.86)
        return min(1, stillness * 0.42 + persistence * 0.34 + confidence * 0.24)
    }

    mutating func append(ball: GolfObjectDetection, frame: SwingObservationV3) {
        let weight = CGFloat(max(0.001, ball.confidence))
        weightedX += ball.center.x * weight
        weightedY += ball.center.y * weight
        totalWeight += weight
        rects.append(ball.rect)
        confidences.append(ball.confidence)
        centers.append(ball.center)
        frameTimes.append(frame.realTime)
        addressBallCounts.append(Self.lowBallCount(in: frame))
    }

    private static func lowBallCount(in frame: SwingObservationV3) -> Int {
        frame.balls.filter { $0.confidence >= 0.30 }.count
    }

    private static func pathSpan(_ points: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 1 }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width * width + height * height).squareRoot()
    }
}
