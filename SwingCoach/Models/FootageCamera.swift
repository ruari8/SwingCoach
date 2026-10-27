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
//    -footage-camera-impacts <t,t,...> labelled impacts, in real seconds on the
//                                     footage timeline. Auto saves these instead
//                                     of the detector's swings; the detector still
//                                     runs and its decisions are logged. For the
//                                     Simulator, where Vision pose cannot run and
//                                     the detector rejects every swing.
//
//  Relative paths resolve against the app's Documents folder. A directory
//  plays its .mov/.mp4 files in name order, e.g. a KeptRecordings session.
//
//  Like AVCaptureVideoDataOutput, each frame is copied into a small fixed pool.
//  If the app still holds every buffer, the frame is dropped as
//  `outOfBuffers`, so camera-starvation bugs still show. If decoding falls
//  behind the clock, late frames are skipped as `footageLate` to catch up,
//  but at least 30 frames a second are still delivered, late, so a feeder
//  that never catches up degrades the frame rate rather than stopping it.
//

#if DEBUG
import AVFoundation
import CoreImage
import UIKit

nonisolated final class FootageCamera: @unchecked Sendable {
    struct Configuration {
        let urls: [URL]
        let timeScale: Double
        let bufferCount: Int
        let impacts: [Double]

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
            return Configuration(urls: urls, timeScale: timeScale > 0 ? timeScale : 1,
                                 bufferCount: bufferCount > 0 ? bufferCount : 15, impacts: impacts)
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

        var summary: String {
            if let error { return "Footage camera: \(error)" }
            let state = isFinished ? "finished" : file
            return String(format: "Footage %@ · %.0f/%.0f s · %d frames · dropped %d pool, %d late",
                          state, seconds, totalSeconds, delivered, droppedOutOfBuffers, droppedLate)
        }
    }

    /// Each delivered sample buffer carries its time on the footage timeline
    /// (real seconds from the start of the first file) under this key.
    static let footageTimeKey = "SwingCoachFootageTime" as CFString

    let configuration: Configuration
    /// Real-time frame rate of the footage, e.g. 240 for 30 fps slowed 8×.
    let sourceFPS: Double
    /// Display rotation of the first file, as the camera's capture rotation.
    let rotationAngle: CGFloat

    /// Called on the delivery queue for each frame, like captureOutput(didOutput:).
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// Called on the delivery queue for each dropped frame with its reason.
    var onDrop: ((String) -> Void)?
    /// Called on the main queue about twice a second and at the end.
    var onStatus: ((Status) -> Void)?
    /// Called on the main queue with a downscaled frame about four times a second.
    var onPreview: ((UIImage) -> Void)?

    private let deliveryQueue: DispatchQueue
    private let previewQueue = DispatchQueue(label: "footage-camera.preview", qos: .utility)
    private let lock = NSLock()
    private var thread: Thread?
    private var isStopping = false
    /// Where playback resumes after stop(): file index and source time.
    private var resumeFile = 0
    private var resumeSourceTime = 0.0
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
        let degrees = (Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()) + 360) % 360
        rotationAngle = CGFloat(degrees)
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
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "footage-camera"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
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
        let ciContext = CIContext()

        fileLoop: while resumeFile < configuration.urls.count {
            let url = configuration.urls[resumeFile]
            guard let file = Self.loadFile(url),
                  let reader = try? AVAssetReader(asset: file.asset) else {
                fail("cannot read \(url.lastPathComponent)")
                break
            }
            let track = file.track
            if resumeSourceTime > 0 {
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
            // Footage seconds before this file started.
            let fileOffset = playedSeconds - (resumeSourceTime - fileStart) / configuration.timeScale
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

                // Wait for this frame's moment on the real clock.
                let due = anchorHost + footageTime - anchorPlayed
                let now = CMClockGetTime(hostClock).seconds
                if due > now {
                    Thread.sleep(forTimeInterval: due - now)
                } else if now - due > max(2 * frameDuration, 0.02), now - lastDelivered < 1.0 / 30 {
                    updateStatus { $0.droppedLate += 1; $0.seconds = footageTime }
                    deliveryQueue.async { [weak self] in self?.onDrop?("footageLate") }
                    continue
                }

                let width = CVPixelBufferGetWidth(decoded), height = CVPixelBufferGetHeight(decoded)
                if pool == nil || poolSize != (width, height) {
                    pool = Self.makePool(width: width, height: height)
                    poolSize = (width, height)
                }
                guard let pool, let frame = Self.copy(decoded, from: pool, limit: configuration.bufferCount),
                      let buffer = Self.sampleBuffer(frame, time: due, duration: frameDuration) else {
                    updateStatus { $0.droppedOutOfBuffers += 1; $0.seconds = footageTime }
                    deliveryQueue.async { [weak self] in self?.onDrop?("outOfBuffers") }
                    continue
                }
                CMSetAttachment(buffer, key: Self.footageTimeKey, value: NSNumber(value: footageTime),
                                attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                deliveryQueue.async { [weak self] in self?.onFrame?(buffer) }
                lastDelivered = now

                let delivered = updateStatus { $0.delivered += 1; $0.seconds = footageTime }
                if now - lastStatus >= 0.5 {
                    lastStatus = now
                    publish(delivered)
                }
                if onPreview != nil, now - lastPreview >= 0.25 {
                    lastPreview = now
                    let rotation = rotationAngle
                    previewQueue.async { [weak self] in
                        guard let image = Self.previewImage(frame, rotation: rotation, context: ciContext) else { return }
                        DispatchQueue.main.async { self?.onPreview?(image) }
                    }
                }
            }
            if reader.status == .failed {
                fail("decoding failed in \(url.lastPathComponent)")
                break
            }
            playedSeconds = fileEnd
            resumeFile += 1
            resumeSourceTime = 0
        }

        lock.lock()
        thread = nil
        let finished = resumeFile >= configuration.urls.count
        let restart = !isStopping && !finished && status.error == nil
        lock.unlock()
        if restart {
            start()
            return
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

    private static func previewImage(_ pixelBuffer: CVPixelBuffer, rotation: CGFloat, context: CIContext) -> UIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = 480 / max(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let orientation: UIImage.Orientation
        switch Int(rotation) {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
#endif
