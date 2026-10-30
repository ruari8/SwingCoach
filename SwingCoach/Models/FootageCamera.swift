//
//  FootageCamera.swift
//  SwingCoach
//
//  DEBUG-only stand-in for the back camera. Decodes video files at the real
//  clock and hands each frame to CameraSession where camera frames enter, so
//  detection, the rolling recorder, export, swing positions and diagnostics
//  all run as in a live Auto session. Launch with:
//
//    -footage-camera <file, directory, or comma-separated files>
//    -footage-camera-time-scale <n>   source seconds per real second (default 1;
//                                     8 for 240 fps footage slowed to 30 fps)
//    -footage-camera-buffers <n>      frame pool size (default 15)
//    -footage-camera-every-frame YES|NO  deliver every frame, waiting for the
//                                     app instead of dropping (default YES on
//                                     the Simulator, NO on a phone)
//    -footage-camera-impacts <t,t,...> labelled impacts, in real seconds on the
//                                     footage timeline. Auto saves these instead
//                                     of the detector's swings; the detector still
//                                     runs and its decisions are logged.
//
//  Relative paths resolve against the app's Documents folder. A directory
//  plays its .mov/.mp4 files in name order, e.g. a KeptRecordings session.
//
//  Real time (the phone default): like AVCaptureVideoDataOutput, each frame is
//  copied into a small fixed pool. If the app still holds every buffer, the
//  frame is dropped as `outOfBuffers`, so camera-starvation bugs still show.
//  If decoding falls behind the clock, late frames are skipped as
//  `footageLate` to catch up, but at least 30 frames a second are still
//  delivered, late, so a feeder that never catches up degrades the frame rate
//  rather than stopping it.
//
//  Every frame (the Simulator default): nothing is dropped. The feed waits for
//  a free buffer and for the detector to finish the previous frame, and
//  frames are stamped on the footage's own clock, so the app sees a perfect
//  stream that plays slower than real time when the machine can't keep up.
//

#if DEBUG
import AVFoundation
import UIKit

nonisolated final class FootageCamera: @unchecked Sendable {
    struct Configuration {
        let urls: [URL]
        let timeScale: Double
        let bufferCount: Int
        let impacts: [Double]
        let everyFrame: Bool

        static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Configuration? {
            guard let raw = defaults.string(forKey: "footage-camera"), !raw.isEmpty else { return nil }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var urls: [URL] = []
            for part in raw.split(separator: ",") {
                let path = String(part)
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                    urls += files.filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
                } else {
                    urls.append(url)
                }
            }
            let timeScale = defaults.double(forKey: "footage-camera-time-scale")
            let bufferCount = defaults.integer(forKey: "footage-camera-buffers")
            let impacts = (defaults.string(forKey: "footage-camera-impacts") ?? "")
                .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.sorted()
            #if targetEnvironment(simulator)
            let everyFrameByDefault = true
            #else
            let everyFrameByDefault = false
            #endif
            let everyFrame = defaults.object(forKey: "footage-camera-every-frame") == nil
                ? everyFrameByDefault : defaults.bool(forKey: "footage-camera-every-frame")
            return Configuration(urls: urls, timeScale: timeScale > 0 ? timeScale : 1,
                                 bufferCount: bufferCount > 0 ? bufferCount : 15, impacts: impacts,
                                 everyFrame: everyFrame)
        }
    }

    struct Status: Equatable {
        var file = ""
        var seconds = 0.0
        var totalSeconds = 0.0
        var delivered = 0
        var droppedOutOfBuffers = 0
        var droppedLate = 0
        var isFinished = false
        var error: String?
        /// Every-frame mode: footage seconds played per real second.
        var speed: Double?

        var summary: String {
            if let error { return "Footage camera: \(error)" }
            let state = isFinished ? "finished" : file
            let head = String(format: "Footage %@ · %.0f/%.0f s · %d frames", state, seconds, totalSeconds, delivered)
            if let speed {
                return head + String(format: " · every frame, %.2g× speed", speed)
            }
            return head + String(format: " · dropped %d pool, %d late", droppedOutOfBuffers, droppedLate)
        }
    }

    /// Each delivered sample buffer carries its time on the footage timeline
    /// (real seconds from the start of the first file) under this key.
    static let footageTimeKey = "SwingCoachFootageTime" as CFString
    /// Each delivered sample buffer carries its file's display rotation in
    /// degrees under this key: kept recordings change files when the phone
    /// rotated, so one rotation for the whole feed would be wrong.
    static let rotationKey = "SwingCoachFootageRotation" as CFString

    let configuration: Configuration
    /// Real-time frame rate of the footage, e.g. 240 for 30 fps slowed 8×.
    let sourceFPS: Double
    /// Display rotation of the first file, until frames arrive.
    let rotationAngle: CGFloat

    /// Called on the delivery queue for each frame, like captureOutput(didOutput:).
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// Called on the delivery queue for each dropped frame with its reason.
    var onDrop: ((String) -> Void)?
    /// Called on the main queue about twice a second and at the end.
    var onStatus: ((Status) -> Void)?
    /// Called on the feed thread with the full decoded frame, up to 60 times a
    /// real second, and its display rotation in degrees. The frame is the
    /// decoder's own buffer, so the preview never holds the app's pool.
    var onPreviewFrame: ((CMSampleBuffer, CGFloat) -> Void)?
    /// Called on the delivery queue after the last frame of the last file.
    var onFinish: (() -> Void)?
    /// Every-frame mode: polled on the feed thread before each frame; the
    /// frame waits until it returns true.
    var isReadyForFrame: (() -> Bool)?

    private let deliveryQueue: DispatchQueue
    private let lock = NSLock()
    private var thread: Thread?
    private var isStopping = false
    /// Where playback resumes after stop(): file index and the source time of
    /// the last frame played, or nil to start that file from its first frame.
    private var resumeFile = 0
    private var resumeSourceTime: Double?
    /// Real seconds of footage already played, carried across stop/start.
    private var playedSeconds = 0.0
    private var status = Status()

    init?(configuration: Configuration, deliveryQueue: DispatchQueue) {
        guard !configuration.urls.isEmpty else { return nil }
        self.configuration = configuration
        self.deliveryQueue = deliveryQueue
        // Blocking loads are acceptable here: DEBUG-only, once at launch.
        let files = configuration.urls.map(Self.loadFile)
        guard let firstFile = files.first ?? nil else { return nil }
        sourceFPS = firstFile.nominalFPS * configuration.timeScale
        let transform = firstFile.transform
        rotationAngle = Self.rotation(of: transform)
        status.totalSeconds = files.reduce(0) { $0 + ($1?.duration ?? 0) / configuration.timeScale }
    }

    private struct FileInfo {
        /// Held strongly: a track only weakly references its asset.
        let asset: AVURLAsset
        let track: AVAssetTrack
        let start: Double
        let duration: Double
        let nominalFPS: Double
        let transform: CGAffineTransform
    }

    private static func rotation(of transform: CGAffineTransform) -> CGFloat {
        CGFloat((Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()) + 360) % 360)
    }

    private final class Box<T>: @unchecked Sendable { var value: T? }

    /// Loads track properties synchronously; called at launch and on the feed thread.
    private static func loadFile(_ url: URL) -> FileInfo? {
        let box = Box<FileInfo>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let asset = AVURLAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let (timeRange, fps, transform) = try? await track.load(.timeRange, .nominalFrameRate, .preferredTransform) {
                box.value = FileInfo(asset: asset, track: track, start: timeRange.start.seconds, duration: timeRange.duration.seconds,
                                     nominalFPS: Double(fps), transform: transform)
            }
            done.signal()
        }
        done.wait()
        return box.value
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        isStopping = false
        // A stopping feed thread sees isStopping cleared and restarts itself.
        guard thread == nil, !status.isFinished else { return }
        launchThreadLocked()
    }

    private func launchThreadLocked() {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "footage-camera"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    /// Plays the footage again from the start after it finished.
    func replay() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil, status.isFinished, status.error == nil else { return }
        resumeFile = 0
        resumeSourceTime = nil
        playedSeconds = 0
        status = Status(totalSeconds: status.totalSeconds)
        isStopping = false
        launchThreadLocked()
    }

    func stop() {
        lock.lock()
        isStopping = true
        lock.unlock()
    }

    private var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopping
    }

    // MARK: - Feed loop

    private func run() {
        let hostClock = CMClockGetHostTimeClock()
        // Real-time anchor: footage second `playedSeconds` plays now.
        let anchorHost = CMClockGetTime(hostClock).seconds
        let anchorPlayed = playedSeconds
        var pool: CVPixelBufferPool?
        var poolSize = (width: 0, height: 0)
        var lastStatus = 0.0
        var lastPreview = 0.0
        var lastDelivered = -Double.infinity
        let everyFrame = configuration.everyFrame

        fileLoop: while resumeFile < configuration.urls.count {
            let url = configuration.urls[resumeFile]
            guard let file = Self.loadFile(url),
                  let reader = try? AVAssetReader(asset: file.asset) else {
                fail("cannot read \(url.lastPathComponent)")
                break
            }
            let track = file.track
            if let resumeSourceTime {
                reader.timeRange = CMTimeRange(start: CMTime(seconds: resumeSourceTime, preferredTimescale: 600),
                                               end: CMTime(seconds: file.start + file.duration, preferredTimescale: 600))
            }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else {
                fail("cannot decode \(url.lastPathComponent)")
                break
            }
            let fileStart = file.start
            let rotation = Self.rotation(of: file.transform)
            // Footage seconds at the file's first frame. A track can start
            // after zero (edit-list pre-roll), so measure from its own start.
            let fileOffset = playedSeconds - ((resumeSourceTime ?? fileStart) - fileStart) / configuration.timeScale
            var fileEnd = playedSeconds
            updateStatus { $0.file = url.lastPathComponent }

            while let sample = output.copyNextSampleBuffer() {
                if shouldStop {
                    reader.cancelReading()
                    break fileLoop
                }
                guard let decoded = CMSampleBufferGetImageBuffer(sample) else { continue }
                let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard sourceTime.isFinite else { continue }
                let footageTime = fileOffset + (sourceTime - fileStart) / configuration.timeScale
                let frameDuration = 1 / max(sourceFPS, 1)
                fileEnd = footageTime + frameDuration
                resumeSourceTime = sourceTime
                playedSeconds = footageTime

                // Wait for this frame's moment on the real clock. Every-frame
                // mode never runs ahead of it either, but when behind it
                // delivers each frame, still stamped with its own moment.
                let due = anchorHost + footageTime - anchorPlayed
                var now = CMClockGetTime(hostClock).seconds
                if due > now {
                    Thread.sleep(forTimeInterval: due - now)
                } else if !everyFrame, now - due > max(2 * frameDuration, 0.02), now - lastDelivered < 1.0 / 30 {
                    updateStatus { $0.droppedLate += 1; $0.seconds = footageTime }
                    deliveryQueue.async { [weak self] in self?.onDrop?("footageLate") }
                    continue
                }

                let width = CVPixelBufferGetWidth(decoded), height = CVPixelBufferGetHeight(decoded)
                if pool == nil || poolSize != (width, height) {
                    pool = Self.makePool(width: width, height: height)
                    poolSize = (width, height)
                }
                guard let pool else { continue }
                var copied = Self.copy(decoded, from: pool, limit: configuration.bufferCount)
                while everyFrame, copied == nil, !shouldStop {
                    Thread.sleep(forTimeInterval: 0.002)
                    copied = Self.copy(decoded, from: pool, limit: configuration.bufferCount)
                }
                guard let frame = copied, let buffer = Self.sampleBuffer(frame, time: due, duration: frameDuration) else {
                    if everyFrame { continue }
                    updateStatus { $0.droppedOutOfBuffers += 1; $0.seconds = footageTime }
                    deliveryQueue.async { [weak self] in self?.onDrop?("outOfBuffers") }
                    continue
                }
                CMSetAttachment(buffer, key: Self.footageTimeKey, value: NSNumber(value: footageTime),
                                attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                CMSetAttachment(buffer, key: Self.rotationKey, value: NSNumber(value: Double(rotation)),
                                attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                if everyFrame {
                    while !(isReadyForFrame?() ?? true), !shouldStop {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                    if shouldStop { continue }
                    // Synchronous, so the app has taken this frame before the
                    // next readiness check.
                    deliveryQueue.sync { onFrame?(buffer) }
                    now = CMClockGetTime(hostClock).seconds
                } else {
                    deliveryQueue.async { [weak self] in self?.onFrame?(buffer) }
                }
                lastDelivered = now

                let speed = everyFrame ? (footageTime - anchorPlayed) / max(now - anchorHost, 0.001) : nil
                let delivered = updateStatus {
                    $0.delivered += 1
                    $0.seconds = footageTime
                    $0.speed = speed.map { min($0, 1) }
                }
                if now - lastStatus >= 0.5 {
                    lastStatus = now
                    publish(delivered)
                }
                if let onPreviewFrame, now - lastPreview >= 1.0 / 60,
                   let preview = Self.sampleBuffer(decoded, time: due, duration: frameDuration) {
                    lastPreview = now
                    onPreviewFrame(preview, rotation)
                }
            }
            if reader.status == .failed {
                fail("decoding failed in \(url.lastPathComponent)")
                break
            }
            playedSeconds = fileEnd
            resumeFile += 1
            resumeSourceTime = nil
        }

        lock.lock()
        let finished = resumeFile >= configuration.urls.count
        if !isStopping, !finished, status.error == nil {
            // start() cleared a stop while this thread was winding down.
            // Relaunch under the lock so a later stop() still applies.
            launchThreadLocked()
            lock.unlock()
            return
        }
        thread = nil
        lock.unlock()
        if finished {
            // Queued after every delivered frame on the same serial queue.
            deliveryQueue.async { [weak self] in self?.onFinish?() }
        }
        let final = updateStatus { $0.isFinished = finished || $0.error != nil }
        publish(final)
        CaptureCadenceDiagnostics.shared.emit(finished ? "footage-end" : "footage-stop", values: [
            "delivered": Double(final.delivered),
            "droppedOutOfBuffers": Double(final.droppedOutOfBuffers),
            "droppedLate": Double(final.droppedLate),
            "footageSeconds": final.seconds,
        ], state: ["file": final.file, "error": final.error ?? "none"])
    }

    @discardableResult
    private func updateStatus(_ change: (inout Status) -> Void) -> Status {
        lock.lock()
        defer { lock.unlock() }
        change(&status)
        return status
    }

    private func publish(_ status: Status) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }

    private func fail(_ message: String) {
        updateStatus { $0.error = message }
    }

    /// Emitted when Auto starts on footage, so diagnostics show which footage
    /// fed the run and where its timeline began.
    func emitStart() {
        CaptureCadenceDiagnostics.shared.emit("footage-start", values: [
            "timeScale": configuration.timeScale,
            "sourceFPS": sourceFPS,
            "bufferCount": Double(configuration.bufferCount),
            "footageSeconds": playedSeconds,
            "totalSeconds": status.totalSeconds,
            "labelledImpacts": Double(configuration.impacts.count),
        ], state: ["files": configuration.urls.map(\.lastPathComponent).joined(separator: ",")])
    }

    // MARK: - Buffers

    private static func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }

    /// Copies a decoded frame into the pool, or returns nil when `limit`
    /// buffers are still held elsewhere in the app.
    private static func copy(_ source: CVPixelBuffer, from pool: CVPixelBufferPool, limit: Int) -> CVPixelBuffer? {
        var destination: CVPixelBuffer?
        let auxiliary = [kCVPixelBufferPoolAllocationThresholdKey as String: limit] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxiliary,
                                                                  &destination) == kCVReturnSuccess,
              let destination else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                  let to = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { return nil }
            let fromStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let toStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
            let rows = CVPixelBufferGetHeightOfPlane(source, plane)
            if fromStride == toStride {
                memcpy(to, from, fromStride * rows)
            } else {
                let rowBytes = min(fromStride, toStride)
                for row in 0..<rows {
                    memcpy(to + row * toStride, from + row * fromStride, rowBytes)
                }
            }
        }
        return destination
    }

    /// A sample buffer stamped on the host clock, as camera frames are.
    private static func sampleBuffer(_ pixelBuffer: CVPixelBuffer, time: Double, duration: Double) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000),
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
#endif
