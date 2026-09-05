// Shared output and status types for live capture, trim, and detector evaluators.

import AVFoundation

nonisolated struct DetectedSwing: Identifiable {
    let id = UUID()
    let startTime: CMTime
    let endTime: CMTime
    let confidence: Double
    let impactTime: Double?
    let declaredAt: Double?

    init(
        startTime: CMTime,
        endTime: CMTime,
        confidence: Double,
        impactTime: Double? = nil,
        declaredAt: Double? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.impactTime = impactTime
        self.declaredAt = declaredAt
    }
}

nonisolated enum LiveSwingDetectionStatus: Equatable {
    case idle
    case disabled
    case searchingBall
    case ballLocked
    case swingInProgress
    case hitDetected
    case swingDetected
    case unavailable
}

nonisolated struct LiveSwingDetectionSnapshot: Equatable {
    var status: LiveSwingDetectionStatus = .idle
    var primaryMessage: String = "Auto detect ready"
    var detailMessage: String = "Looking for setup once recording starts."
    var detectedSwingCount: Int = 0
    var hasBallLock = false
    var hasBallMovement = false
    var poseObservationCount = 0
    var handSpeed = 0.0
    var peakHandSpeed = 0.0
    var handTravel = 0.0
    var setupDuration = 0.0
    var ballCandidateScore: Double?
    var ballLumaDelta: Double?
    var lastRejectionReason: String?
    var processedFrameCount = 0
    var skippedFrameCount = 0
    var targetSampleFPS = 0.0
    var effectiveSampleFPS = 0.0
    var analysisLagMS = 0.0
    var averageProcessingTimeMS = 0.0
    var lastProcessingTimeMS = 0.0
    var averagePoseProcessingTimeMS = 0.0
    var lastPoseProcessingTimeMS = 0.0
    var detectorConfigurationName: String?

    static let idle = LiveSwingDetectionSnapshot()
}
