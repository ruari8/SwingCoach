//
//  LiveSwingPoses.swift
//  SwingCoach
//
//  Body pose on live Auto frames, 30 per second of real time, so P
//  positions are ready as soon as the swing's last frame arrives instead of
//  after the clip is saved and read back. Every 8th 240 fps frame is copied,
//  scaled down, out of the camera's buffer pool, which gets its frame back at
//  once. `copy` (the default) keeps about 3 s of copies and runs pose only
//  once a swing is declared. `pose` (debug only) runs pose on every copy
//  straight away; it is as fast but doubles the app's CPU energy.
//

import AVFoundation
import VideoToolbox

nonisolated final class LiveSwingPoses: @unchecked Sendable {
    enum Mode: String {
        case pose, copy
    }

    private struct Entry {
        let time: Double
        var buffer: CVPixelBuffer?
        var pose: SwingPositionPose?
        var posed = false
        let orientation: CGImagePropertyOrientation
    }

    /// Hands a request its result exactly once, from whichever comes first:
    /// the live queue or the timeout, which doesn't wait behind pose calls.
    private final class Delivery: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((SwingPositions?) -> Void)?

        init(_ completion: @escaping (SwingPositions?) -> Void) { self.completion = completion }

        var isDone: Bool { lock.withLock { completion == nil } }

        /// False if the request already had its result.
        @discardableResult
        func callAsFunction(_ positions: SwingPositions?) -> Bool {
            let completion = lock.withLock {
                defer { self.completion = nil }
                return self.completion
            }
            completion?(positions)
            return completion != nil
        }
    }

    private struct Request {
        let token: UUID
        let window: ClosedRange<Double>
        let diagnosticID: String
        let registeredAt: Double
        let deliver: Delivery
    }

    let mode: Mode
    private let width: Int
    private let analyzer: SwingPositionAnalyzer
    private let queue = DispatchQueue(label: "swing-positions.live", qos: .userInitiated)
    private let lock = NSLock()
    private var inFlight = 0
    private var skippedCopies = 0

    // Video queue.
    private var nextSlot = -Double.infinity
    private var transfer: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolFormat: (width: Int, height: Int, pixelFormat: OSType)?

    // Live queue.
    private var entries: [Entry] = []
    private var requests: [Request] = []
    /// Bumped whenever entries are cleared, so queued pose work for old
    /// entries is dropped.
    private var generation = 0
    private var poseSeconds = 0.0
    private var poseCalls = 0

    private static let slot = 1.0 / SwingPositionFeatures.gridFPS
    private static let keepSeconds = 3.0
    private static let maxInFlight = 45
    /// A request still open this long after the swing was declared fails,
    /// and the saved clip is read instead. The window ends ~0.5 s after.
    private static let requestTimeout = 3.0

    /// Copy mode at 480 wide. Debug builds can override with
    /// `-positions-live off|copy|pose` and `-positions-live-width <px>`.
    static func fromSettings() -> LiveSwingPoses? {
        var mode = Mode.copy
        var width = 480
        #if DEBUG
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "positions-live") {
            guard let chosen = Mode(rawValue: name) else { return nil }
            mode = chosen
        }
        width = defaults.string(forKey: "positions-live-width").flatMap(Int.init) ?? width
        #endif
        return try? LiveSwingPoses(mode: mode, width: width)
    }

    init(mode: Mode, width: Int) throws {
        self.mode = mode
        self.width = width
        analyzer = try SwingPositionAnalyzer()
        queue.async {
            // Landscape 1080p scaled to the copy width.
            let warmWidth = width > 0 ? width : 1920
            self.analyzer.warmUp(width: warmWidth, height: (warmWidth * 9 / 16) & ~1)
        }
    }

    /// Video queue: takes one frame per 30 fps slot.
    func offer(_ sampleBuffer: CMSampleBuffer, relativeTime: Double, orientation: CGImagePropertyOrientation) {
        // A new Auto session restarts the recording timeline.
        if relativeTime < nextSlot - Self.slot { nextSlot = relativeTime }
        // Half a 240 fps frame of slack keeps the pick on every 8th frame.
        guard relativeTime >= nextSlot - 1.0 / 480 else { return }
        nextSlot = relativeTime - nextSlot > Self.slot ? relativeTime + Self.slot : nextSlot + Self.slot
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let busy = inFlight >= Self.maxInFlight
        if busy { skippedCopies += 1 } else { inFlight += 1 }
        lock.unlock()
        guard !busy else { return }
        guard let copy = scaledCopy(of: source) else {
            lock.lock(); inFlight -= 1; lock.unlock()
            return
        }
        queue.async {
            self.append(Entry(time: relativeTime, buffer: copy, orientation: orientation))
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
        }
    }

    /// Any queue: positions for `window` (recording seconds), delivered once
    /// its last slot is posed; nil if they can't be found. Every request
    /// delivers exactly once, at the latest after `requestTimeout`.
    func positions(token: UUID, window: ClosedRange<Double>, diagnosticID: String,
                   completion: @escaping (SwingPositions?) -> Void) {
        let registeredAt = ProcessInfo.processInfo.systemUptime
        let deliver = Delivery(completion)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.requestTimeout) {
            if deliver(nil) { self.logFailure("live window timed out", id: diagnosticID) }
        }
        queue.async {
            if let first = self.entries.first, first.time > window.lowerBound + Self.slot {
                self.fail(deliver, "swing starts before the oldest live copy", id: diagnosticID)
                return
            }
            self.requests.append(Request(token: token, window: window, diagnosticID: diagnosticID,
                                         registeredAt: registeredAt, deliver: deliver))
            if self.mode == .copy {
                // Pose the backlog one frame per block so new frames interleave.
                let generation = self.generation
                for entry in self.entries where window.contains(entry.time) && !entry.posed {
                    let time = entry.time
                    self.queue.async { self.poseEntry(at: time, generation: generation) }
                }
            }
            self.fulfil()
        }
    }

    /// Fails every open request and drops the copies, e.g. when Auto stops or
    /// the recording timeline restarts.
    func reset() {
        queue.async { self.clear(reason: "Auto stopped or restarted") }
    }

    private func clear(reason: String) {
        for request in requests { fail(request.deliver, reason, id: request.diagnosticID) }
        requests.removeAll()
        entries.removeAll()
        generation += 1
    }

    private func fail(_ deliver: Delivery, _ reason: String, id: String) {
        if deliver(nil) { logFailure(reason, id: id) }
    }

    private func logFailure(_ reason: String, id: String) {
        CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", id: id,
                                              state: ["error": reason, "path": "live-\(mode.rawValue)"])
    }

    private func append(_ entry: Entry) {
        var entry = entry
        // The recording timeline restarted without a reset: the open requests
        // and copies belong to the old one.
        if let last = entries.last, entry.time < last.time { clear(reason: "recording timeline restarted") }
        let wanted = mode == .pose || requests.contains { $0.window.contains(entry.time) && !$0.deliver.isDone }
        if wanted, let buffer = entry.buffer {
            entry.pose = timedPose(buffer, orientation: entry.orientation)
            entry.posed = true
            if mode == .pose { entry.buffer = nil }
        }
        entries.append(entry)
        let oldestNeeded = requests.map(\.window.lowerBound).min() ?? .infinity
        let cutoff = min(entry.time - Self.keepSeconds, oldestNeeded - Self.slot)
        if let drop = entries.firstIndex(where: { $0.time >= cutoff }), drop > 0 {
            entries.removeFirst(drop)
        }
        fulfil()
    }

    private func poseEntry(at time: Double, generation: Int) {
        guard generation == self.generation,
              let index = entries.firstIndex(where: { $0.time == time }), !entries[index].posed,
              let buffer = entries[index].buffer else { return }
        entries[index].pose = timedPose(buffer, orientation: entries[index].orientation)
        entries[index].posed = true
        fulfil()
    }

    private func timedPose(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> SwingPositionPose? {
        let started = ProcessInfo.processInfo.systemUptime
        let pose = analyzer.pose(in: buffer, orientation: orientation)
        poseSeconds += ProcessInfo.processInfo.systemUptime - started
        poseCalls += 1
        return pose
    }

    private func fulfil() {
        // Timed out: nothing left to deliver.
        requests.removeAll { $0.deliver.isDone }
        guard let latest = entries.last?.time else { return }
        requests.removeAll { request in
            // The last slot inside the window has arrived.
            guard latest >= request.window.upperBound - Self.slot else { return false }
            let slots = entries.filter { $0.time >= request.window.lowerBound && $0.time < request.window.upperBound }
            guard slots.allSatisfy(\.posed) else { return false }
            complete(request, slots: slots)
            return true
        }
    }

    private func complete(_ request: Request, slots: [Entry]) {
        // The model expects one pose per slot across the whole window: no
        // missing copy at either edge or in between.
        let window = request.window
        guard let first = slots.first, let last = slots.last,
              first.time < window.lowerBound + 1.5 * Self.slot,
              last.time > window.upperBound - 1.5 * Self.slot,
              slots.count == Int(((last.time - first.time) / Self.slot).rounded()) + 1 else {
            fail(request.deliver, "live window has gaps", id: request.diagnosticID)
            return
        }
        var timing = SwingPositionAnalyzer.Timing()
        timing.poseCalls = poseCalls
        timing.poseSeconds = poseSeconds
        let positions: SwingPositions
        do {
            positions = try analyzer.positions(grid: slots.map(\.pose), playable: first.time...last.time,
                                               timeScale: 1, timing: &timing)
        } catch {
            fail(request.deliver, error.localizedDescription, id: request.diagnosticID)
            return
        }
        guard request.deliver(positions) else { return }
        lock.lock()
        let skipped = skippedCopies
        lock.unlock()
        CaptureCadenceDiagnostics.shared.emit("swing-positions", id: request.diagnosticID, values: [
            "poseCalls": Double(poseCalls),
            "poseSeconds": poseSeconds,
            "readAndPoseSeconds": 0,
            "decodedFrames": Double(slots.count),
            "bodySlots": Double(timing.bodySlots),
            "modelSeconds": timing.modelSeconds,
            "queuedSeconds": ProcessInfo.processInfo.systemUptime - request.registeredAt,
            "skippedCopies": Double(skipped),
            "width": Double(width),
        ], state: [
            "model": positions.model, "path": "live-\(mode.rawValue)",
            "slots": timing.slots.map(String.init).joined(separator: ","),
            "clipTimes": positions.positions.map { String(format: "%.3f", $0.clipTime) }.joined(separator: ","),
        ])
    }

    // MARK: - Copy

    private func scaledCopy(of source: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        let targetWidth = width > 0 ? min(width, sourceWidth) : sourceWidth
        let targetHeight = (sourceHeight * targetWidth / sourceWidth) & ~1
        // Rebuilt when the camera format or footage file changes size.
        if poolFormat.map({ $0 != (targetWidth, targetHeight, pixelFormat) }) ?? true {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                kCVPixelBufferWidthKey: targetWidth,
                kCVPixelBufferHeightKey: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            poolFormat = (targetWidth, targetHeight, pixelFormat)
        }
        if transfer == nil {
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
        }
        guard let pool, let transfer else { return nil }
        var copy: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &copy)
        guard let copy, VTPixelTransferSessionTransferImage(transfer, from: source, to: copy) == noErr else {
            return nil
        }
        return copy
    }
}
