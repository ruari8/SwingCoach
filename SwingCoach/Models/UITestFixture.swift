#if DEBUG
import AVFoundation
import Foundation

/// DEBUG-only launch fixtures for `SwingCoachUITests`. Tests pass these launch
/// arguments; Release builds compile none of this.
///
/// - `-ui-testing-seed <Seed>` erases app data and settings, then installs a
///   synthetic Library. Pass it on a test's first launch only; relaunching
///   without it keeps the state the test built.
/// - `-ui-testing-camera synthetic` replaces the camera: no capture session,
///   recordings are synthetic files, detector status is deterministic, and Auto
///   shows the Library's reference swings as its session (see `CameraSession`).
/// - `-ui-testing-camera audio` keeps the real preview setup with camera access
///   granted and shows the shared audio policy as `capture-audio-verification`.
/// - `-ui-testing-detections 2,150,300` makes each Manual recording report a
///   1-second swing at each start time, in seconds.
/// - `-ui-testing-recording-seconds N` sets the synthetic recording length.
/// - `-ui-testing-frame-rate 30|240` sets the recorded frame rate; otherwise
///   recordings use the selected capture mode.
/// - `-ui-testing-auto-export` makes Auto export one clip through the real
///   exporter instead of showing reference swings.
/// - `-ui-testing-detector waiting|unavailable` and `-ui-testing-auto-error`
///   set detector and Auto error states.
/// - `-ui-testing-record-analysis` stores analysis requests in
///   `ui-testing-analysis-ids` instead of uploading.
/// - `-ui-testing-save-failure` fails the second Photos save.
///
/// Any `-ui-testing` argument also keeps private bundled reference videos out
/// of the Library, so results never depend on them.
nonisolated enum UITestFixture {
    enum Camera: String {
        case synthetic, audio
    }

    enum Seed: String {
        case empty
        /// One personal clip.
        case smoke
        /// Personal clips B (Face-On), A and C (both starred DTL), newest first, and three references.
        case review
        /// Three 12-second references.
        case references
        /// Sixteen references, for fast-swipe paging.
        case swipes
        /// 171 references, for the on-request fast-swipe stress test.
        case stress
        /// Six clips today and three yesterday.
        case sessions
    }

    private static let arguments = ProcessInfo.processInfo.arguments

    static let isActive = arguments.contains { $0.hasPrefix("-ui-testing") }
    static let seed = value(after: "-ui-testing-seed").map { name in
        guard let seed = Seed(rawValue: name) else { fatalError("Unknown -ui-testing-seed \(name)") }
        return seed
    }
    static let camera = value(after: "-ui-testing-camera").map { name in
        guard let camera = Camera(rawValue: name) else { fatalError("Unknown -ui-testing-camera \(name)") }
        return camera
    }
    static let detectionStarts = value(after: "-ui-testing-detections")?
        .split(separator: ",").compactMap { Double($0) } ?? []
    static let recordedFrameRate = value(after: "-ui-testing-frame-rate").flatMap(Int.init)
    static let exportsAutoClip = arguments.contains("-ui-testing-auto-export")
    static let detectorState = value(after: "-ui-testing-detector")
    static let showsAutoError = arguments.contains("-ui-testing-auto-error")
    static let recordsAnalysisRequests = arguments.contains("-ui-testing-record-analysis")
    private static let failsSecondPhotosSave = arguments.contains("-ui-testing-save-failure")

    /// Long recordings use a small frame so the file stays quick to write.
    static let recordingVideo: SyntheticVideo.Spec = {
        let seconds = value(after: "-ui-testing-recording-seconds").flatMap(Int.init) ?? 2
        return seconds > 12 ? SyntheticVideo.Spec(width: 160, height: 280, fps: 10, seconds: seconds)
            : SyntheticVideo.Spec(seconds: seconds)
    }()

    /// Audio policy before any capture code ran, for the audio fixture.
    static let launchAudioPolicy = currentAudioPolicy()

    static func currentAudioPolicy() -> String {
        let audio = AVAudioSession.sharedInstance()
        return "\(audio.category.rawValue) \(audio.mode.rawValue) \(audio.categoryOptions.rawValue)"
    }

    static func recordAnalysisRequest(ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: "ui-testing-analysis-ids")
    }

    static func shouldFailPhotosSave() -> Bool {
        guard failsSecondPhotosSave else { return false }
        let attempt = UserDefaults.standard.integer(forKey: "ui-testing-photos-save-attempt") + 1
        UserDefaults.standard.set(attempt, forKey: "ui-testing-photos-save-attempt")
        return attempt == 2
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

extension UITestFixture {
    /// Runs in `SwingCoachApp.init`, before any view or the Library loads.
    @MainActor static func prepareLaunch() {
        guard isActive else { return }
        _ = launchAudioPolicy
        if let seed {
            eraseAppData()
            install(seed)
        }
        if camera == .synthetic {
            // Write the recording now so stopping a recording does not wait for it.
            DispatchQueue.global(qos: .userInitiated).async { _ = try? SyntheticVideo.url(for: recordingVideo) }
        }
    }

    /// Keeps tmp, so scripts/verify.sh can check that a run's recordings were cleaned up.
    @MainActor private static func eraseAppData() {
        let files = FileManager.default
        let directories = [
            files.urls(for: .documentDirectory, in: .userDomainMask)[0],
            files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        ]
        for directory in directories {
            for item in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? files.removeItem(at: item)
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }

    @MainActor private static func install(_ seed: Seed) {
        var swings: [SavedSwing] = []
        var seconds = 3
        func personal(_ number: Int, title: String?, vantage: Vantage = .dtl, starred: Bool = false, createdAt: Date) {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
            swings.append(SavedSwing(id: id, photoAssetID: "", vantage: vantage, duration: Double(seconds),
                                     createdAt: createdAt, notes: nil, analyzed: false, isFavorite: starred,
                                     title: title, localVideoFilename: "\(id.uuidString).mp4"))
        }
        func references(_ count: Int) {
            for number in 1...count {
                let id = UUID(uuidString: String(format: "93F08C01-6795-46B0-B092-%012X", number))!
                swings.append(SavedSwing(id: id, photoAssetID: "", vantage: .dtl, duration: Double(seconds),
                                         createdAt: Date(timeIntervalSinceReferenceDate: Double(count + 1 - number)),
                                         notes: nil, analyzed: false, isFavorite: true, isReference: true,
                                         title: "Reference swing \(number)", localVideoFilename: "\(id.uuidString).mp4"))
            }
        }

        switch seed {
        case .empty:
            return
        case .smoke:
            personal(1, title: "Smoke clip", createdAt: Date())
        case .review:
            personal(2, title: "Review B Face-On", vantage: .faceOn, createdAt: Date(timeIntervalSinceReferenceDate: 300))
            personal(1, title: "Review A starred DTL", starred: true, createdAt: Date(timeIntervalSinceReferenceDate: 200))
            personal(3, title: "Review C DTL", starred: true, createdAt: Date(timeIntervalSinceReferenceDate: 100))
            references(3)
        case .references:
            seconds = 12
            references(3)
        case .swipes:
            references(16)
        case .stress:
            references(171)
        case .sessions:
            seconds = 1
            let calendar = Calendar.current
            let today = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            for index in 0..<6 { personal(index + 1, title: nil, createdAt: today.addingTimeInterval(Double(120 * index))) }
            for index in 0..<3 { personal(index + 7, title: nil, createdAt: yesterday.addingTimeInterval(Double(120 * index))) }
        }

        let files = FileManager.default
        let video = try! SyntheticVideo.url(for: SyntheticVideo.Spec(seconds: seconds))
        let videos = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwingVideos", isDirectory: true)
        let documents = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try! files.createDirectory(at: videos, withIntermediateDirectories: true)
        try! files.createDirectory(at: documents, withIntermediateDirectories: true)
        for swing in swings {
            try! files.copyItem(at: video, to: videos.appendingPathComponent(swing.localVideoFilename!))
        }
        try! JSONEncoder().encode(swings).write(to: documents.appendingPathComponent("swing_library.json"))
    }
}

/// Deterministic test videos: a bar moving over a changing background, with a
/// silent audio track (the Simulator plays clip audio through the Mac's
/// speakers). Files are cached by spec in Caches, which seeding keeps.
nonisolated enum SyntheticVideo {
    struct Spec: Hashable, Sendable {
        var width = 360
        var height = 640
        var fps = 30
        var seconds: Int
    }

    private static let lock = NSLock()
    private static let sampleRate = 44_100

    static func url(for spec: Spec) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let files = FileManager.default
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // Clips cached before the audio went silent beep through the Mac's speakers.
        try? files.removeItem(at: caches.appendingPathComponent("ui-test-videos", isDirectory: true))
        let directory = caches.appendingPathComponent("ui-test-videos-silent", isDirectory: true)
        let url = directory.appendingPathComponent("\(spec.width)x\(spec.height)-\(spec.fps)fps-\(spec.seconds)s.mp4")
        if files.fileExists(atPath: url.path) { return url }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent("partial-\(UUID().uuidString).mp4")
        defer { try? files.removeItem(at: partial) }
        try write(spec, to: partial)
        try files.moveItem(at: partial, to: url)
        return url
    }

    private static func write(_ spec: Spec, to url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // Each input and the adaptor are used only on their own feed queue.
        nonisolated(unsafe) let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: spec.width, AVVideoHeightKey: spec.height,
        ])
        video.expectsMediaDataInRealTime = false
        nonisolated(unsafe) let frames = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: spec.width, kCVPixelBufferHeightKey as String: spec.height,
        ])
        nonisolated(unsafe) let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
        audio.expectsMediaDataInRealTime = false
        writer.add(video)
        writer.add(audio)
        var pcm = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var audioFormat: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &pcm, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &audioFormat)
        guard let audioFormat, writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        // Feed each input whenever the writer asks; it interleaves them itself.
        let frameCount = spec.seconds * spec.fps
        let sampleCount = spec.seconds * sampleRate
        let chunk = 4_096
        let done = DispatchGroup()
        let videoFeed = Feed(), audioFeed = Feed()
        done.enter()
        video.requestMediaDataWhenReady(on: DispatchQueue(label: "synthetic-video.frames")) {
            while video.isReadyForMoreMediaData, !videoFeed.finished {
                var buffer: CVPixelBuffer?
                if videoFeed.next < frameCount, let pool = frames.pixelBufferPool {
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                }
                if let buffer { draw(frame: videoFeed.next, spec: spec, into: buffer) }
                guard let buffer, frames.append(buffer, withPresentationTime: CMTime(
                    value: CMTimeValue(videoFeed.next), timescale: CMTimeScale(spec.fps))) else {
                    videoFeed.finish(video, done)
                    return
                }
                videoFeed.next += 1
            }
        }
        done.enter()
        audio.requestMediaDataWhenReady(on: DispatchQueue(label: "synthetic-video.audio")) {
            while audio.isReadyForMoreMediaData, !audioFeed.finished {
                let end = min(audioFeed.next + chunk, sampleCount)
                guard audioFeed.next < end, let sample = try? silence(samples: audioFeed.next..<end, format: audioFormat),
                      audio.append(sample) else {
                    audioFeed.finish(audio, done)
                    return
                }
                audioFeed.next = end
            }
        }
        done.wait()
        guard videoFeed.next == frameCount, audioFeed.next == sampleCount else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(spec.seconds), timescale: 1))
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// One input's progress; touched only on that input's queue.
    private final class Feed: @unchecked Sendable {
        var next = 0
        var finished = false

        func finish(_ input: AVAssetWriterInput, _ done: DispatchGroup) {
            finished = true
            input.markAsFinished()
            done.leave()
        }
    }

    private static func draw(frame index: Int, spec: Spec, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let shade = UInt32(index * 3 % 200 + 40)
        let background: UInt32 = 0xFF00_0000 | (255 - shade) << 16 | 0x50 << 8 | shade
        let barStart = index * 4 % spec.width
        var row = [UInt32](repeating: background, count: spec.width)
        for x in barStart..<min(barStart + spec.width / 8, spec.width) { row[x] = 0xFFFF_FFFF }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        row.withUnsafeBytes { pixels in
            for y in 0..<spec.height {
                (base + y * bytesPerRow).copyMemory(from: pixels.baseAddress!, byteCount: pixels.count)
            }
        }
    }

    private static func silence(samples range: Range<Int>, format: CMAudioFormatDescription) throws -> CMSampleBuffer {
        let values = [Int16](repeating: 0, count: range.count)
        let byteCount = values.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                           blockBufferOut: &block)
        guard let block else { throw CocoaError(.fileWriteUnknown) }
        values.withUnsafeBytes { bytes in
            _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: byteCount)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: values.count,
            presentationTimeStamp: CMTime(value: CMTimeValue(range.lowerBound), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }
}
#endif
