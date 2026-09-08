import AVFoundation
import Foundation

/// All mutable state belongs to writerQueue, checked at each public entry point.
/// Sendability permits queue hops; it does not permit accessing state off that queue.
nonisolated final class AutoRollingVideoBuffer: @unchecked Sendable {
    private struct BufferedSample {
        let sampleBuffer: CMSampleBuffer
        let relativeTime: Double
    }

    struct PreparedClip {
        struct Segment {
            let chunkID: UUID
            let url: URL
            let range: CMTimeRange
            let timelineStart: CMTime
        }
        let segments: [Segment]
        let sourceStartTime: Double
        let duration: CMTime
        var startTime: CMTime { .zero }
        var endTime: CMTime { duration }
        var chunkID: UUID { segments[0].chunkID }

        /// Concatenate ranges without decoding or re-encoding the rolling buffer.
        /// The existing export performs the single final encode/slow-motion pass.
        func makeAsset() async throws -> AVAsset {
            let composition = AVMutableComposition()
            guard let destination = composition.addMutableTrack(withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw BufferError.clipUnavailable
            }
            var position = CMTime.zero
            var transform: CGAffineTransform?
            for segment in segments {
                let asset = AVURLAsset(url: segment.url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw BufferError.clipUnavailable
                }
                let nextTransform = try await track.load(.preferredTransform)
                // A camera rotation cannot be represented by one track transform.
                guard transform == nil || transform == nextTransform else {
                    throw BufferError.rotationChanged
                }
                transform = nextTransform
                if segment.timelineStart > position {
                    destination.insertEmptyTimeRange(CMTimeRange(start: position, end: segment.timelineStart))
                }
                try destination.insertTimeRange(segment.range, of: track, at: segment.timelineStart)
                position = CMTimeAdd(segment.timelineStart, segment.range.duration)
            }
            destination.preferredTransform = transform ?? .identity
            return composition
        }
    }

    private struct PendingClip {
        let range: CMTimeRange
        let completion: (Result<PreparedClip, Error>) -> Void
    }

    enum BufferError: LocalizedError {
        case missingFormatDescription
        case writerCreationFailed(String)
        case clipUnavailable
        case invalidClipRange
        case rotationChanged

        var errorDescription: String? {
            switch self {
            case .missingFormatDescription:
                return "Auto capture could not read the camera frame format."
            case .writerCreationFailed(let reason):
                return "Auto capture buffer failed: \(reason)"
            case .clipUnavailable:
                return "Auto capture buffer did not contain the full swing window."
            case .rotationChanged:
                return "The phone rotated during this swing clip. Keep the camera orientation steady while collecting extra footage."
            case .invalidClipRange:
                return "Auto capture received an invalid swing window."
            }
        }
    }

    private final class Chunk: @unchecked Sendable {
        let id = UUID()
        let generation: UUID
        let url: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let startRelativeTime: Double
        let startSampleTime: CMTime
        let videoRotationAngle: CGFloat
        var endRelativeTime: Double
        var isFinishing = false
        var isFinished = false
        var didMarkInputFinished = false
        var pendingExports = 0
        var pendingSamples: [BufferedSample] = []
        var pendingReadIndex = 0
        var completionHandlers: [() -> Void] = []
        var cadence = CaptureCadenceWindow()
        var nextCadenceReport = 0.0
        let sourceFPS: Double

        init(
            url: URL,
            generation: UUID,
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            startRelativeTime: Double,
            startSampleTime: CMTime,
            videoRotationAngle: CGFloat,
            sourceFPS: Double
        ) {
            self.generation = generation
            self.sourceFPS = sourceFPS
            self.url = url
            self.writer = writer
            self.input = input
            self.startRelativeTime = startRelativeTime
            self.startSampleTime = startSampleTime
            self.videoRotationAngle = videoRotationAngle
            self.endRelativeTime = startRelativeTime
        }
    }

    private var chunks: [Chunk] = []
    private var pendingClips: [PendingClip] = []
    private var generation = UUID()
    private var latestRelativeTime = -Double.greatestFiniteMagnitude
    private let writerQueue: DispatchQueue
    private let chunkDuration = 20.0
    private let chunkStartInterval = 17.4
    private let retentionDuration = 45.0
    private var nextChunkStartTime: Double?
    private var inputCadence = CaptureCadenceWindow()
    private var nextInputCadenceReport = 0.0

    init(writerQueue: DispatchQueue) {
        self.writerQueue = writerQueue
    }

    func reset(preservingPendingExports: Bool = false) {
        dispatchPrecondition(condition: .onQueue(writerQueue))
        if preservingPendingExports {
            resolvePendingClips(stopping: true)
        } else {
            let cancelled = pendingClips
            pendingClips.removeAll()
            for request in cancelled { request.completion(.failure(BufferError.clipUnavailable)) }
        }
        generation = UUID()
        CaptureCadenceDiagnostics.shared.emit("buffer-reset", cadence: inputCadence.takeSummary())
        inputCadence = CaptureCadenceWindow()
        nextInputCadenceReport = 0
        var preservedChunks: [Chunk] = []
        for chunk in chunks {
            if preservingPendingExports, chunk.pendingExports > 0 {
                finish(chunk)
                preservedChunks.append(chunk)
                continue
            }

            if !chunk.isFinishing && !chunk.isFinished {
                chunk.pendingSamples.removeAll(keepingCapacity: false)
                chunk.writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: chunk.url)
        }
        chunks = preservedChunks
        nextChunkStartTime = nil
        latestRelativeTime = -Double.greatestFiniteMagnitude
    }

    func append(
        sampleBuffer: CMSampleBuffer,
        relativeTime: Double,
        videoRotationAngle: CGFloat,
        sourceFPS: Double,
        queueDelay: Double
    ) {
        dispatchPrecondition(condition: .onQueue(writerQueue))
        guard relativeTime.isFinite else { return }
        latestRelativeTime = relativeTime
        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard sampleTime.isValid else { return }
        inputCadence.record(pts: sampleTime.seconds, expectedFPS: sourceFPS, queueDelay: queueDelay)
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextInputCadenceReport {
            nextInputCadenceReport = now + 1
            CaptureCadenceDiagnostics.shared.emit("buffer-input", cadence: inputCadence.takeSummary(), values: [
                "relativeTime": relativeTime, "sourceFPS": sourceFPS,
                "activeChunks": Double(chunks.filter { !$0.isFinished }.count)
            ])
        }

        let activeChunks = chunks.filter { !$0.isFinishing && !$0.isFinished }
        if activeChunks.contains(where: { $0.videoRotationAngle != videoRotationAngle }) {
            for chunk in activeChunks {
                finish(chunk)
            }
            nextChunkStartTime = nil
        }

        if !chunks.contains(where: { !$0.isFinishing && !$0.isFinished }) {
            startChunk(
                sampleBuffer: sampleBuffer,
                relativeTime: relativeTime,
                sampleTime: sampleTime,
                videoRotationAngle: videoRotationAngle,
                sourceFPS: sourceFPS
            )
        }

        while let nextChunkStartTime, relativeTime >= nextChunkStartTime {
            startChunk(
                sampleBuffer: sampleBuffer,
                relativeTime: relativeTime,
                sampleTime: sampleTime,
                videoRotationAngle: videoRotationAngle,
                sourceFPS: sourceFPS
            )
        }

        for chunk in chunks where !chunk.isFinishing && !chunk.isFinished {
            guard relativeTime >= chunk.startRelativeTime else { continue }
            append(sampleBuffer, to: chunk, relativeTime: relativeTime)
            if relativeTime - chunk.startRelativeTime >= chunkDuration {
                finish(chunk)
            }
        }

        resolvePendingClips()
        cleanupOldChunks(currentTime: relativeTime)
    }

    func prepareClip(in range: CMTimeRange,
                     completion: @escaping (Result<PreparedClip, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(writerQueue))
        guard range.isValid, range.start.seconds.isFinite, range.end.seconds.isFinite,
              range.duration > .zero else {
            completion(.failure(BufferError.invalidClipRange))
            return
        }
        pendingClips.append(PendingClip(range: range, completion: completion))
        resolvePendingClips()
    }

    private func resolvePendingClips(stopping: Bool = false) {
        let ready = pendingClips.filter { stopping || $0.range.end.seconds <= latestRelativeTime }
        pendingClips.removeAll { stopping || $0.range.end.seconds <= latestRelativeTime }
        let recordedEnd = chunks.filter { $0.generation == generation }.map(\.endRelativeTime).max() ?? latestRelativeTime
        for request in ready {
            let end = stopping ? min(request.range.end.seconds, recordedEnd) : request.range.end.seconds
            prepareRecordedClip(start: request.range.start.seconds, end: end, completion: request.completion)
        }
    }

    private func prepareRecordedClip(start: Double, end: Double,
                                     completion: @escaping (Result<PreparedClip, Error>) -> Void) {
        let available = chunks.filter { $0.generation == generation }
        guard let earliest = available.map(\.startRelativeTime).min() else {
            completion(.failure(BufferError.clipUnavailable))
            return
        }
        let start = max(start, earliest)
        guard end > start else {
            completion(.failure(BufferError.clipUnavailable))
            return
        }
        var cursor = start
        var selected: [Chunk] = []
        var segments: [PreparedClip.Segment] = []
        // Greedy coverage uses each source range once, dropping overlap between chunks.
        while cursor < end - 0.000001 {
            let coveringChunk = available.filter({ $0.startRelativeTime <= cursor + 0.000001 &&
                                                 $0.endRelativeTime > cursor + 0.000001 })
                .max(by: { $0.endRelativeTime < $1.endRelativeTime })
            // Finishing an export closes the current writer. If the camera drops
            // its next frame, the new chunk starts later than the old chunk ends.
            // Retain that hole on the source timeline instead of losing the clip
            // or moving every subsequent frame and detection timestamp earlier.
            let nextChunk = coveringChunk ?? available.filter {
                $0.startRelativeTime > cursor && $0.startRelativeTime < end &&
                $0.endRelativeTime > $0.startRelativeTime
            }.min(by: { $0.startRelativeTime < $1.startRelativeTime })
            guard let chunk = nextChunk else {
                if !segments.isEmpty { break }
                completion(.failure(BufferError.clipUnavailable))
                return
            }
            cursor = max(cursor, chunk.startRelativeTime)
            let segmentEnd = min(end, chunk.endRelativeTime)
            let range = CMTimeRange(
                start: Self.sourceTime(cursor - chunk.startRelativeTime),
                end: Self.sourceTime(segmentEnd - chunk.startRelativeTime)
            )
            segments.append(.init(chunkID: chunk.id, url: chunk.url, range: range,
                                  timelineStart: Self.sourceTime(cursor - start)))
            selected.append(chunk)
            cursor = segmentEnd
        }
        let prepared = PreparedClip(segments: segments, sourceStartTime: start,
                                   duration: Self.sourceTime(cursor - start))
        let finalization = DispatchGroup()
        for chunk in selected {
            chunk.pendingExports += 1
            if !chunk.isFinished {
                finalization.enter()
                chunk.completionHandlers.append { finalization.leave() }
                finish(chunk)
            }
        }
        finalization.notify(queue: writerQueue) {
            if let failed = selected.first(where: { $0.writer.status != .completed }) {
                self.release(prepared)
                completion(.failure(BufferError.writerCreationFailed(failed.writer.error?.localizedDescription ?? "Writer did not finish")))
            } else {
                completion(.success(prepared))
            }
        }
    }

    func release(_ preparedClip: PreparedClip) {
        dispatchPrecondition(condition: .onQueue(writerQueue))
        for segment in preparedClip.segments {
            if let chunk = chunks.first(where: { $0.id == segment.chunkID }) {
                chunk.pendingExports = max(0, chunk.pendingExports - 1)
            }
        }
        cleanupOldChunks(currentTime: latestRelativeTime)
    }

    private func startChunk(
        sampleBuffer: CMSampleBuffer,
        relativeTime: Double,
        sampleTime: CMTime,
        videoRotationAngle: CGFloat,
        sourceFPS: Double
    ) {
        do {
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw BufferError.missingFormatDescription
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let expectedFPS = max(30, Int(sourceFPS.rounded()))
            let averageBitRate: Int
            switch expectedFPS {
            case 180...:
                averageBitRate = 50_000_000
            case 90...:
                averageBitRate = 32_000_000
            case 45...:
                averageBitRate = 20_000_000
            default:
                averageBitRate = 14_000_000
            }
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoExpectedSourceFrameRateKey: expectedFPS,
                    AVVideoAverageBitRateKey: averageBitRate,
                    AVVideoMaxKeyFrameIntervalKey: expectedFPS * 2
                ]
            ]
            let url = Self.tempURL()
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: outputSettings,
                sourceFormatHint: formatDescription
            )
            input.expectsMediaDataInRealTime = true
            // Keep raw pixel buffers untouched for detector performance, and
            // record the device-aware orientation as the movie track transform.
            input.transform = Self.videoTransform(
                rotationAngle: videoRotationAngle,
                dimensions: dimensions
            )

            guard writer.canAdd(input) else {
                throw BufferError.writerCreationFailed("Video input could not be added.")
            }

            writer.add(input)
            guard writer.startWriting() else {
                throw BufferError.writerCreationFailed(writer.error?.localizedDescription ?? "Writer did not start.")
            }
            writer.startSession(atSourceTime: .zero)

            let chunk = Chunk(
                url: url,
                generation: generation,
                writer: writer,
                input: input,
                startRelativeTime: relativeTime,
                startSampleTime: sampleTime,
                videoRotationAngle: videoRotationAngle,
                sourceFPS: sourceFPS
            )
            CaptureCadenceDiagnostics.shared.emit("writer-start", id: chunk.id.uuidString, values: [
                "sourcePTS": sampleTime.seconds, "relativeTime": relativeTime,
                "sourceFPS": sourceFPS, "bitRate": Double(averageBitRate),
                "width": Double(dimensions.width), "height": Double(dimensions.height),
                "rotation": Double(videoRotationAngle)
            ], state: ["codec": "h264"])
            chunks.append(chunk)
            nextChunkStartTime = relativeTime + chunkStartInterval
        } catch {
            CaptureCadenceDiagnostics.shared.emit("writer-start-failed", state: ["error": error.localizedDescription])
            print("❌ Auto rolling buffer failed to start: \(error.localizedDescription)")
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to chunk: Chunk, relativeTime: Double) {
        guard let retimedBuffer = Self.copy(sampleBuffer, relativeTo: chunk.startSampleTime) else {
            CaptureCadenceDiagnostics.shared.emit("writer-retime-failed", id: chunk.id.uuidString)
            return
        }
        let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
        let frameDuration = sampleDuration.isNumeric && sampleDuration > .zero ? sampleDuration.seconds : 1 / chunk.sourceFPS
        chunk.endRelativeTime = max(chunk.endRelativeTime, relativeTime + frameDuration)
        chunk.pendingSamples.append(
            BufferedSample(sampleBuffer: retimedBuffer, relativeTime: relativeTime)
        )
        drainPendingSamples(for: chunk)
    }

    private func finish(_ chunk: Chunk) {
        guard !chunk.isFinishing, !chunk.isFinished else { return }
        chunk.isFinishing = true
        drainPendingSamples(for: chunk)
    }

    private func drainPendingSamples(for chunk: Chunk) {
        guard !chunk.isFinished, !chunk.didMarkInputFinished else { return }

        while chunk.input.isReadyForMoreMediaData,
              chunk.pendingReadIndex < chunk.pendingSamples.count {
            let sample = chunk.pendingSamples[chunk.pendingReadIndex]
            if chunk.input.append(sample.sampleBuffer) {
                chunk.cadence.record(pts: CMSampleBufferGetPresentationTimeStamp(sample.sampleBuffer).seconds,
                                     expectedFPS: chunk.sourceFPS,
                                     pendingFrames: chunk.pendingSamples.count - chunk.pendingReadIndex)
                chunk.pendingReadIndex += 1
            } else {
                let message = chunk.writer.error?.localizedDescription ?? "unknown writer error"
                CaptureCadenceDiagnostics.shared.emit("writer-append-failed", id: chunk.id.uuidString,
                    values: ["pendingFrames": Double(chunk.pendingSamples.count - chunk.pendingReadIndex)],
                    state: ["error": message])
                print("❌ Auto rolling buffer append failed: \(message)")
                chunk.pendingSamples.removeAll(keepingCapacity: false)
                chunk.pendingReadIndex = 0
                chunk.isFinishing = true
                break
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now >= chunk.nextCadenceReport {
            chunk.nextCadenceReport = now + 1
            CaptureCadenceDiagnostics.shared.emit("writer", id: chunk.id.uuidString,
                cadence: chunk.cadence.takeSummary(), values: [
                    "pendingFrames": Double(chunk.pendingSamples.count - chunk.pendingReadIndex),
                    "ready": chunk.input.isReadyForMoreMediaData ? 1 : 0,
                    "status": Double(chunk.writer.status.rawValue)
                ])
        }

        // Every buffered sample pins one pixel buffer from the camera's small
        // fixed pool; holding consumed samples starves the capture pipeline and
        // the camera stops delivering frames. Release them as soon as the
        // encoder has accepted them.
        if chunk.pendingReadIndex > 0 {
            chunk.pendingSamples.removeFirst(chunk.pendingReadIndex)
            chunk.pendingReadIndex = 0
        }

        guard chunk.isFinishing else { return }
        guard chunk.pendingReadIndex >= chunk.pendingSamples.count else {
            writerQueue.asyncAfter(deadline: .now() + 0.005) { [weak self, weak chunk] in
                guard let self, let chunk else { return }
                self.drainPendingSamples(for: chunk)
            }
            return
        }

        chunk.pendingSamples.removeAll(keepingCapacity: false)
        chunk.pendingReadIndex = 0
        chunk.didMarkInputFinished = true
        chunk.writer.endSession(atSourceTime: Self.sourceTime(chunk.endRelativeTime - chunk.startRelativeTime))
        chunk.input.markAsFinished()
        // finishWriting calls back on AVFoundation's own queue; all chunk state
        // is owned by writerQueue, so hop back before touching it.
        chunk.writer.finishWriting { [weak self, weak chunk] in
            guard let self, let chunk else { return }
            self.writerQueue.async {
                CaptureCadenceDiagnostics.shared.emit("writer-end", id: chunk.id.uuidString,
                    cadence: chunk.cadence.takeSummary(), values: ["status": Double(chunk.writer.status.rawValue)],
                    state: ["error": chunk.writer.error?.localizedDescription ?? "none"])
                chunk.isFinished = true
                chunk.isFinishing = false
                let handlers = chunk.completionHandlers
                chunk.completionHandlers = []
                for handler in handlers {
                    handler()
                }
            }
        }
    }

    private func cleanupOldChunks(currentTime: Double) {
        chunks.removeAll { chunk in
            guard chunk.isFinished,
                  chunk.pendingExports == 0,
                  (chunk.generation != generation || currentTime - chunk.endRelativeTime > retentionDuration)
            else {
                return false
            }
            // A requested trailing extension can outlive normal retention.
            // Keep only the older chunks that a pending clip still needs.
            guard !pendingClips.contains(where: {
                $0.range.start.seconds < chunk.endRelativeTime && $0.range.end.seconds > chunk.startRelativeTime
            }) else { return false }
            try? FileManager.default.removeItem(at: chunk.url)
            return true
        }
    }

    /// Round each boundary to the nearest tick. Truncating a floating-point
    /// difference can put a join one tick inside the preceding frame.
    private static func sourceTime(_ seconds: Double) -> CMTime {
        CMTime(value: Int64((seconds * 60000).rounded()), timescale: 60000)
    }

    private static func copy(_ sampleBuffer: CMSampleBuffer, relativeTo startTime: CMTime) -> CMSampleBuffer? {
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return nil }

        var timingInfo = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: sampleCount
        )
        var timingCount = 0
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: sampleCount,
            arrayToFill: &timingInfo,
            entriesNeededOut: &timingCount
        )
        guard timingStatus == noErr else { return nil }

        for index in timingInfo.indices {
            if timingInfo[index].presentationTimeStamp.isValid {
                timingInfo[index].presentationTimeStamp = CMTimeSubtract(
                    timingInfo[index].presentationTimeStamp,
                    startTime
                )
            }
            if timingInfo[index].decodeTimeStamp.isValid {
                timingInfo[index].decodeTimeStamp = CMTimeSubtract(
                    timingInfo[index].decodeTimeStamp,
                    startTime
                )
            }
        }

        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &copiedBuffer
        )
        guard copyStatus == noErr else { return nil }
        return copiedBuffer
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("auto_buffer_\(UUID().uuidString).mov")
    }

    private static func videoTransform(
        rotationAngle: CGFloat,
        dimensions: CMVideoDimensions
    ) -> CGAffineTransform {
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)

        switch Int(rotationAngle.rounded()) % 360 {
        case 90:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        case 180:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 270:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        default:
            return .identity
        }
    }
}
