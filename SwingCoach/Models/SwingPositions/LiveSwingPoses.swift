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

    /// A copy's place on the 30 fps schedule: slot `index` of the grid
    /// anchored at `anchor` (recording seconds). A gap long enough to skip a
    /// slot starts a new grid. Copies the queue couldn't take still use up
    /// their index, so a missing copy shows as a missing index.
    struct Slot: Equatable {
        let grid: Int
        let index: Int
        let anchor: Double

        var target: Double { anchor + Double(index) * LiveSwingPoses.slot }
    }

    private struct Entry {
        let time: Double
        let slot: Slot
        /// Host-clock start of the recording this copy belongs to.
        let epoch: Double
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
        let epoch: Double
        let window: ClosedRange<Double>
        let diagnosticID: String
        let registeredAt: Double
        /// `skippedCopies` when the request registered.
        let skippedBefore: Int
        let deliver: Delivery
    }

    let mode: Mode
    private let width: Int
    private let queue = DispatchQueue(label: "swing-positions.live", qos: .userInitiated)
    private let lock = NSLock()
    private var inFlight = 0
    private var skippedCopies = 0
    /// Set if the pose model failed to load; then nothing is copied.
    private var modelUnavailable = false

    // Video queue.
    private var nextSlot = -Double.infinity
    private var grid = 0
    private var gridAnchor = 0.0
    private var slotIndex = 0
    private var transfer: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolFormat: (width: Int, height: Int, pixelFormat: OSType)?

    // Live queue.
    /// Loaded on the live queue, so the Capture tab doesn't wait for it.
    private var analyzer: SwingPositionAnalyzer?
    /// Recording the current copies belong to; nil after a reset.
    private var epoch: Double?
    private var entries: [Entry] = []
    private var requests: [Request] = []
    /// Bumped whenever entries are cleared, so queued pose work for old
    /// entries is dropped.
    private var generation = 0
    private var poseSeconds = 0.0
    private var poseCalls = 0

    static let slot = 1.0 / SwingPositionFeatures.gridFPS
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
        return LiveSwingPoses(mode: mode, width: width)
    }

    init(mode: Mode, width: Int) {
        self.mode = mode
        self.width = width
        queue.async {
            do {
                self.analyzer = try SwingPositionAnalyzer()
            } catch {
                self.lock.withLock { self.modelUnavailable = true }
                CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", state: [
                    "error": "pose model failed to load: \(error.localizedDescription)", "path": "live-\(mode.rawValue)",
                ])
                return
            }
            // Landscape 1080p scaled to the copy width.
            let warmWidth = width > 0 ? width : 1920
            self.analyzer?.warmUp(width: warmWidth, height: (warmWidth * 9 / 16) & ~1)
        }
    }

    /// Host-clock start of the recording a frame at `relativeTime` belongs
    /// to. Identifies the recording timeline across queues.
    static func epoch(of sampleBuffer: CMSampleBuffer, relativeTime: Double) -> Double {
        CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds - relativeTime
    }

    private static func sameRecording(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    /// Video queue: takes one frame per 30 fps slot.
    func offer(_ sampleBuffer: CMSampleBuffer, relativeTime: Double, orientation: CGImagePropertyOrientation) {
        let epoch = Self.epoch(of: sampleBuffer, relativeTime: relativeTime)
        // A new Auto session restarts the recording timeline.
        if relativeTime < nextSlot - Self.slot { nextSlot = -.infinity }
        // Half a 240 fps frame of slack keeps the pick on every 8th frame.
        guard relativeTime >= nextSlot - 1.0 / 480 else { return }
        if relativeTime - nextSlot > Self.slot {
            // First frame, a restart, or a gap: anchor a new grid here.
            grid += 1
            gridAnchor = relativeTime
            slotIndex = 0
        } else {
            slotIndex += 1
        }
        let slot = Slot(grid: grid, index: slotIndex, anchor: gridAnchor)
        nextSlot = slot.target + Self.slot
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let unavailable = modelUnavailable
        let busy = !unavailable && inFlight >= Self.maxInFlight
        if busy { skippedCopies += 1 } else if !unavailable { inFlight += 1 }
        lock.unlock()
        guard !busy, !unavailable else { return }
        guard let copy = scaledCopy(of: source) else {
            lock.lock(); inFlight -= 1; lock.unlock()
            return
        }
        queue.async {
            self.append(Entry(time: relativeTime, slot: slot, epoch: epoch, buffer: copy, orientation: orientation))
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
        }
    }

    /// Any queue: positions for `window` (seconds on the recording that
    /// started at `epoch`), delivered once its last slot is posed; nil if they
    /// can't be found. Every request delivers exactly once, at the latest
    /// after `requestTimeout`.
    func positions(token: UUID, epoch: Double, window: ClosedRange<Double>, diagnosticID: String,
                   completion: @escaping (SwingPositions?) -> Void) {
        let registeredAt = ProcessInfo.processInfo.systemUptime
        let deliver = Delivery(completion)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.requestTimeout) {
            if deliver(nil) { self.logFailure("live window timed out", id: diagnosticID) }
        }
        let skippedBefore = lock.withLock { skippedCopies }
        queue.async {
            guard self.analyzer != nil else {
                self.fail(deliver, "pose model failed to load", id: diagnosticID)
                return
            }
            // Declared on a recording that has since restarted.
            if let current = self.epoch, !Self.sameRecording(current, epoch) {
                self.fail(deliver, "recording timeline restarted", id: diagnosticID)
                return
            }
            if let first = self.entries.first, first.slot.target >= window.lowerBound + Self.slot {
                self.fail(deliver, "swing starts before the oldest live copy", id: diagnosticID)
                return
            }
            self.requests.append(Request(token: token, epoch: epoch, window: window, diagnosticID: diagnosticID,
                                         registeredAt: registeredAt, skippedBefore: skippedBefore, deliver: deliver))
            if self.mode == .copy {
                // Pose the backlog one frame per block so new frames interleave.
                let generation = self.generation
                for entry in self.entries where Self.inWindow(entry.slot, window) && !entry.posed {
                    let slot = entry.slot
                    self.queue.async { self.poseEntry(at: slot, generation: generation) }
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
        epoch = nil
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
        // A new recording: the copies, and requests declared on the old one,
        // can't be used. Requests that registered after a reset but came from
        // the old recording are failed here too.
        if let current = epoch, !Self.sameRecording(current, entry.epoch) {
            clear(reason: "recording timeline restarted")
        }
        epoch = entry.epoch
        requests.removeAll { request in
            guard !Self.sameRecording(request.epoch, entry.epoch) else { return false }
            fail(request.deliver, "recording timeline restarted", id: request.diagnosticID)
            return true
        }
        let wanted = mode == .pose || requests.contains { Self.inWindow(entry.slot, $0.window) && !$0.deliver.isDone }
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

    private func poseEntry(at slot: Slot, generation: Int) {
        // Skipped once no open request needs it, e.g. after a timeout.
        guard generation == self.generation,
              requests.contains(where: { !$0.deliver.isDone && Self.inWindow(slot, $0.window) }),
              let index = entries.firstIndex(where: { $0.slot == slot }), !entries[index].posed,
              let buffer = entries[index].buffer else { return }
        entries[index].pose = timedPose(buffer, orientation: entries[index].orientation)
        entries[index].posed = true
        fulfil()
    }

    private func timedPose(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> SwingPositionPose? {
        guard let analyzer else { return nil }
        let started = ProcessInfo.processInfo.systemUptime
        let pose = analyzer.pose(in: buffer, orientation: orientation)
        poseSeconds += ProcessInfo.processInfo.systemUptime - started
        poseCalls += 1
        return pose
    }

    private func fulfil() {
        // Timed out: nothing left to deliver.
        requests.removeAll { $0.deliver.isDone }
        guard let latest = entries.last?.slot.target else { return }
        requests.removeAll { request in
            // The last slot inside the window is due, taken or not.
            guard latest >= request.window.upperBound - Self.slot else { return false }
            let slots = entries.filter { Self.inWindow($0.slot, request.window) }
            guard slots.allSatisfy(\.posed) else { return false }
            complete(request, slots: slots)
            return true
        }
    }

    /// A slot belongs to a window when its scheduled time is in
    /// [lower, upper); the copy's own timestamp may be off by half a frame.
    static func inWindow(_ slot: Slot, _ window: ClosedRange<Double>) -> Bool {
        slot.target >= window.lowerBound && slot.target < window.upperBound
    }

    /// True if `slots` (the copies inside `window`, in order) are every slot
    /// the window needs: one grid, and consecutive indices from the first slot
    /// at or after the window's start to the last before its end.
    static func coversWindow(_ slots: [Slot], window: ClosedRange<Double>) -> Bool {
        guard let first = slots.first, slots.allSatisfy({ $0.grid == first.grid }) else { return false }
        func target(_ index: Int) -> Double { first.anchor + Double(index) * slot }
        var expected = Int(((window.lowerBound - first.anchor) / slot).rounded(.up))
        while target(expected) < window.lowerBound { expected += 1 }
        while target(expected - 1) >= window.lowerBound { expected -= 1 }
        // The window starts before this grid: its first slots were never taken.
        guard expected >= 0 else { return false }
        for slot in slots {
            guard slot.index == expected else { return false }
            expected += 1
        }
        return target(expected) >= window.upperBound
    }

    private func complete(_ request: Request, slots: [Entry]) {
        // The model expects one pose per slot across the whole window.
        guard let first = slots.first, let last = slots.last,
              Self.coversWindow(slots.map(\.slot), window: request.window) else {
            fail(request.deliver, "live window has gaps", id: request.diagnosticID)
            return
        }
        guard let analyzer else {
            fail(request.deliver, "pose model failed to load", id: request.diagnosticID)
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
        let skipped = skippedCopies - request.skippedBefore
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
            // Left unset on failure, so the next frame tries again.
            poolFormat = pool == nil ? nil : (targetWidth, targetHeight, pixelFormat)
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
