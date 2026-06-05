//
//  SwingDetectorV2.swift
//  SwingCoach
//
//  The v2 swing detector core. Reuses GolfObjectDetector for per-frame objects,
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

nonisolated final class SwingDetectorV2: LiveSwingDetecting {
    enum DetectorError: Error {
        case modelUnavailable
    }

    private let configuration: SwingDetectorV2Configuration
    private let modelURL: URL?
    private let computeUnits: MLComputeUnits

    private var detector: GolfObjectDetector?
    private let addressMonitor: AddressMonitor
    private let clubTracker: ClubTracker
    private let stateMachine: SwingStateMachine
    private let scorer: SwingScorer

    private var features: [FrameSampleV2] = []
    private var detections: [DetectedSwing] = []
    private var traces: [SwingCandidateTrace] = []
    private var samplingTraces: [SwingSamplingTrace] = []
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

    private let featureRetentionLimit = 4_000
    private let startupInFlightEndRealTime = 2.25
    private let startupInFlightResolveEndRealTime = 2.90
    private let startupInFlightMinBallY: CGFloat = 0.58

    init(
        configuration: SwingDetectorV2Configuration = .live(),
        modelURL: URL? = nil,
        computeUnits: MLComputeUnits = .all
    ) {
        self.configuration = configuration
        self.modelURL = modelURL
        self.computeUnits = computeUnits
        self.addressMonitor = AddressMonitor()
        self.clubTracker = ClubTracker()
        self.stateMachine = SwingStateMachine(configuration: configuration)
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
        wantsStartupBurst(atRealTime: realTime) || stateMachine.wantsBurst(atRealTime: realTime)
    }

    // MARK: - LiveSwingDetecting

    func reset(enabled: Bool) {
        self.enabled = enabled
        features.removeAll(keepingCapacity: true)
        detections.removeAll(keepingCapacity: true)
        traces.removeAll(keepingCapacity: true)
        samplingTraces.removeAll(keepingCapacity: true)
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
        addressMonitor.reset()
        clubTracker.reset()
        stateMachine.reset()

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
                primaryMessage: "v2 detector ready",
                detailMessage: "Scanning sampled frames while recording.",
                targetSampleFPS: configuration.lowSampleFPS,
                detectorConfigurationName: configuration.name
            )
        } catch {
            detector = nil
            modelLoadError = error
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "v2 detector unavailable",
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
                primaryMessage: "v2 detector unavailable",
                detailMessage: modelLoadError == nil ? "Detector not started." : "Model failed to load.",
                detectorConfigurationName: configuration.name
            )
            return lastSnapshot
        }

        let startedAt = Date()
        let realTime = configuration.realTime(fromSource: recordingTime)
        let startupBurstActiveForFrame = wantsStartupBurst(atRealTime: realTime)
        let stateBurstActiveForFrame = stateMachine.wantsBurst(atRealTime: realTime)
        let burstActiveForFrame = startupBurstActiveForFrame || stateBurstActiveForFrame
        let targetFPSForFrame = burstActiveForFrame ? configuration.burstSampleFPS : configuration.lowSampleFPS
        let stateBeforeFrame = stateMachine.state.rawValue

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
                primaryMessage: "v2 detector unavailable",
                detailMessage: "The YOLO model failed on a frame.",
                detectorConfigurationName: configuration.name
            )
            return lastSnapshot
        }

        let frame = FrameSampleV2(
            realTime: realTime,
            sourceTime: recordingTime,
            detections: objects,
            lumaMotion: lumaMotion
        )
        features.append(frame)
        if features.count > featureRetentionLimit {
            features.removeFirst(features.count - featureRetentionLimit)
        }

        let lock = addressMonitor.update(
            frame: frame,
            recent: features,
            allowsRetargeting: stateMachine.state == .addressed || stateMachine.state == .swinging,
            monitorsAddressHold: stateMachine.state == .addressed
        )
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
        let patch = lock.map { PatchWatcher.observe(frame: frame, lock: $0) }
        let clubWindowSamples = featuresInWindow(
            start: max(0, realTime - configuration.clubEvidenceWindowDuration),
            end: realTime
        )
        let clubWindow = clubTracker.evidence(in: clubWindowSamples[...], lock: lock)

        if let resolved = stateMachine.update(frame: frame, lock: lock, patch: patch, club: clubWindow) {
            evaluate(resolved: resolved, club: clubWindow)
        }
        evaluateStartupInFlightIfNeeded(frame: frame, lock: lock)

        recordProcessing(startedAt: startedAt)
        lastSnapshot = makeSnapshot(frame: frame, lock: lock)
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
    var configurationName: String { configuration.name }
    var averageProcessingMS: Double { processedFrameCount > 0 ? totalProcessingMS / Double(processedFrameCount) : 0 }
    var processedFrames: Int { processedFrameCount }

    // MARK: - Candidate evaluation

    private func evaluate(resolved: ResolvedSwingCandidate, club: ClubEvidence) {
        let candidateWindow = featuresInWindow(
            start: max(0, resolved.impactRealTime - 1.45),
            end: resolved.impactRealTime + 0.55
        )
        let candidateClub = clubTracker.evidence(in: candidateWindow[...], lock: resolved.lock)
        let departure = departureEvidence(
            impactRealTime: resolved.impactRealTime,
            lock: resolved.lock
        )
        let evidence = EvidenceVector(
            anchorStability: resolved.lock?.stabilityScore ?? 0,
            disappearancePersistence: departure.targetSlotDeparture,
            clubSweptThrough: max(club.sweepScore, candidateClub.sweepScore),
            swingArc: max(club.arcScore, candidateClub.arcScore),
            swingSequence: max(club.swingSequenceScore, candidateClub.swingSequenceScore),
            ballInventoryDrop: departure.ballInventoryDrop,
            audioTransient: nil,
            poseConsistency: nil
        )
        let score = scorer.score(evidence)
        let accepted = score >= scorer.threshold
            && evidence.disappearancePersistence >= 0.35
            && (evidence.swingSequence ?? 1) > 0
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
            addressMonitor.suppressLocks(until: resolved.impactRealTime + configuration.minImpactGap)
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
        stateMachine.didConfirm(impactRealTime: resolved.impactRealTime)
        addressMonitor.suppressLocks(until: resolved.impactRealTime + configuration.minImpactGap)
    }

    private func evaluateStartupInFlightIfNeeded(frame: FrameSampleV2, lock: AddressLock?) {
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
            ballInventoryDrop: departure.ballInventoryDrop,
            audioTransient: nil,
            poseConsistency: nil
        )
        let score = scorer.score(evidence)
        let strongStartupSwing = evidence.clubSweptThrough >= 0.62
            && evidence.swingArc >= 0.52
        let startupThreshold = strongStartupSwing ? scorer.threshold - 0.05 : scorer.threshold
        let accepted = score >= startupThreshold
            && evidence.disappearancePersistence >= 0.35
            && ((evidence.swingSequence ?? 0) > 0 || strongStartupSwing)
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
        addressMonitor.suppressLocks(until: candidate.impactRealTime + configuration.minImpactGap)
        stateMachine.didConfirm(impactRealTime: candidate.impactRealTime)
    }

    private func startupInFlightCandidate(atRealTime now: Double) -> StartupInFlightCandidate? {
        let startupFrames = features.filter { $0.realTime <= min(now, startupInFlightResolveEndRealTime) }
        guard startupFrames.count >= 4 else { return nil }

        let clusters = startupBallClusters(in: startupFrames)
        let scored = clusters.compactMap { cluster -> StartupInFlightCandidate? in
            let lock = startupLock(from: cluster)
            let observations = startupFrames.map { frame in
                (frame: frame, observation: PatchWatcher.observe(frame: frame, lock: lock))
            }

            for index in observations.indices {
                let frame = observations[index].frame
                guard frame.realTime <= startupInFlightEndRealTime else { continue }
                guard !observations[index].observation.ballPresent else { continue }

                let pre = observations[..<index]
                let post = observations[index...]
                let prePresent = pre.filter { $0.observation.ballPresent }.count
                guard prePresent >= 2 else { continue }
                guard frame.realTime - cluster.firstRealTime >= 0.18 else { continue }

                let usablePost = post.filter { !$0.observation.clubOverlapsPatch }
                let postFrames = usablePost.isEmpty ? Array(post) : usablePost
                guard postFrames.count >= 2 || now - frame.realTime >= 0.28 else { continue }
                let postAbsent = postFrames.filter { !$0.observation.ballPresent }.count
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

    private func startupBallClusters(in frames: [FrameSampleV2]) -> [StartupBallCluster] {
        var clusters: [StartupBallCluster] = []
        for frame in frames where frame.realTime <= startupInFlightEndRealTime {
            for ball in frame.balls where ball.confidence >= 0.30 && ball.center.y >= startupInFlightMinBallY {
                if let index = clusters.firstIndex(where: { GeometryV2.distance($0.center, ball.center) <= 0.050 }) {
                    clusters[index].append(ball: ball, frame: frame)
                } else {
                    clusters.append(StartupBallCluster(ball: ball, frame: frame))
                }
            }
        }
        return clusters.filter { $0.frameCount >= 2 }
    }

    private func startupLock(from cluster: StartupBallCluster) -> AddressLock {
        AddressLock(
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

    private func trace(for lock: AddressLock) -> SwingAddressLockTrace {
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

    private func makeSnapshot(frame: FrameSampleV2, lock: AddressLock?) -> LiveSwingDetectionSnapshot {
        let status: LiveSwingDetectionStatus
        let primary: String
        switch stateMachine.state {
        case .idle:
            status = lock == nil ? .searchingBall : .ballLocked
            primary = lock == nil ? "v2 scanning" : "Address locked"
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
            detailMessage: "v2",
            detectedSwingCount: detections.count,
            hasBallLock: lock != nil,
            processedFrameCount: processedFrameCount,
            skippedFrameCount: skippedFrameCount,
            targetSampleFPS: configuration.lowSampleFPS,
            averageProcessingTimeMS: averageProcessingMS,
            lastProcessingTimeMS: lastProcessingMS,
            detectorConfigurationName: configuration.name
        )
    }

    private func recordProcessing(startedAt: Date) {
        lastProcessingMS = Date().timeIntervalSince(startedAt) * 1_000
        totalProcessingMS += lastProcessingMS
        processedFrameCount += 1
    }

    private func appendProgressTraceIfNeeded() {
        guard traces.isEmpty, !features.isEmpty else { return }

        let lock = addressMonitor.currentLock
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
                stateReached: stateMachine.bestStateReached.rawValue,
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

    private func progressFailure(lock: AddressLock?) -> SwingPrimaryFailure {
        guard lock != nil else { return .noAddressLock }
        switch stateMachine.bestStateReached {
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
        if evidence.anchorStability < 0.25 { return .noAddressLock }
        if evidence.disappearancePersistence < 0.35 { return .ballReappeared }
        if (evidence.ballInventoryDrop ?? 0) < 0.25 { return .noBallDeparture }
        if evidence.clubSweptThrough < 0.45 { return .noClubSweep }
        if (evidence.swingSequence ?? 0) < 0.35 { return .noSwingSequence }
        if evidence.swingArc < 0.35 { return .lowSwingArc }
        return .belowThreshold
    }

    private func featuresInWindow(start: Double, end: Double) -> [FrameSampleV2] {
        features.filter { $0.realTime >= start && $0.realTime <= end }
    }

    private func departureEvidence(impactRealTime: Double, lock: AddressLock?) -> DepartureEvidence {
        guard let lock else { return .zero }

        let preStart = max(0, impactRealTime - 0.85)
        let preEnd = max(preStart, impactRealTime - 0.04)
        let postStart = impactRealTime + 0.04
        let postEnd = impactRealTime + 0.52

        let pre = featuresInWindow(start: preStart, end: preEnd)
        let post = featuresInWindow(start: postStart, end: postEnd)
        guard !pre.isEmpty, !post.isEmpty else { return .zero }

        let prePresent = pre.reduce(0) { count, frame in
            count + (PatchWatcher.observe(frame: frame, lock: lock).ballPresent ? 1 : 0)
        }
        let usablePost = post.filter { !PatchWatcher.observe(frame: $0, lock: lock).clubOverlapsPatch }
        let postFrames = usablePost.isEmpty ? post : usablePost
        let postAbsent = postFrames.reduce(0) { count, frame in
            count + (PatchWatcher.observe(frame: frame, lock: lock).ballPresent ? 0 : 1)
        }

        let preRatio = Double(prePresent) / Double(pre.count)
        let postRatio = Double(postAbsent) / Double(postFrames.count)
        let preScore = GeometryV2.ramp(preRatio, low: 0.45, high: 0.84)
        let postScore = GeometryV2.ramp(postRatio, low: 0.58, high: 0.94)
        let targetSlotDeparture = min(1, max(0, preScore * postScore))

        let preCounts = pre.map(Self.lowStrikeBallCount)
        let postCounts = postFrames.map(Self.lowStrikeBallCount)
        let preInventory = Self.quantile(preCounts, fraction: 0.60)
        let postInventory = Self.quantile(postCounts, fraction: 0.40)
        let reducedFrameFlags = postCounts.map { count in
            preInventory >= 1 && Double(count) <= preInventory - 1
        }
        let reducedRatio = Double(reducedFrameFlags.filter { $0 }.count) / Double(max(1, reducedFrameFlags.count))
        let longestRun = Self.longestTrueRun(reducedFrameFlags)
        let runScore = GeometryV2.ramp(Double(longestRun), low: 1.0, high: 3.0)
        let ratioScore = GeometryV2.ramp(reducedRatio, low: 0.18, high: 0.48)
        let inventoryDrop = max(runScore * 0.72, ratioScore)

        return DepartureEvidence(
            targetSlotDeparture: targetSlotDeparture,
            ballInventoryDrop: inventoryDrop,
            trace: SwingDepartureTrace(
                preTargetPresenceRatio: preRatio,
                postTargetAbsenceRatio: postRatio,
                preBallInventory: preInventory,
                postBallInventory: postInventory,
                ballInventoryDropScore: inventoryDrop,
                ballInventoryDropFrameRatio: reducedRatio,
                longestBallInventoryDropRun: longestRun
            )
        )
    }

    private static func lowStrikeBallCount(in frame: FrameSampleV2) -> Int {
        frame.balls.filter {
            $0.confidence >= 0.30 && $0.center.y >= 0.68
        }.count
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

    private static func quantile(_ values: [Int], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let clamped = min(1, max(0, fraction))
        let rawIndex = clamped * Double(sorted.count - 1)
        let index = Int(rawIndex.rounded())
        return Double(sorted[index])
    }

    private static func longestTrueRun(_ flags: [Bool]) -> Int {
        var best = 0
        var current = 0
        for flag in flags {
            if flag {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
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
    let ballInventoryDrop: Double
    let trace: SwingDepartureTrace?

    static let zero = DepartureEvidence(
        targetSlotDeparture: 0,
        ballInventoryDrop: 0,
        trace: nil
    )
}

nonisolated private struct StartupInFlightCandidate: Equatable {
    let impactRealTime: Double
    let lock: AddressLock
    let score: Double
}

nonisolated private struct StartupBallCluster: Equatable {
    private(set) var weightedX: CGFloat
    private(set) var weightedY: CGFloat
    private(set) var totalWeight: CGFloat
    private(set) var rects: [CGRect]
    private(set) var confidences: [Double]
    private(set) var centers: [CGPoint]
    private(set) var frameTimes: [Double]
    private(set) var addressBallCounts: [Int]

    init(ball: GolfObjectDetection, frame: FrameSampleV2) {
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
        let stillness = GeometryV2.inverseRamp(span, low: 0.012, high: 0.075)
        let persistence = GeometryV2.ramp(Double(frameCount), low: 2, high: 5)
        let confidence = GeometryV2.ramp(meanConfidence, low: 0.30, high: 0.86)
        return min(1, stillness * 0.42 + persistence * 0.34 + confidence * 0.24)
    }

    mutating func append(ball: GolfObjectDetection, frame: FrameSampleV2) {
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

    private static func lowBallCount(in frame: FrameSampleV2) -> Int {
        frame.balls.filter { $0.confidence >= 0.30 && $0.center.y >= 0.68 }.count
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
