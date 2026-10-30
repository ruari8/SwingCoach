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

    private struct Request {
        let token: UUID
        let window: ClosedRange<Double>
        let diagnosticID: String
        let registeredAt: Double
        let completion: (SwingPositions?) -> Void
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

    // Live queue.
    private var entries: [Entry] = []
    private var requests: [Request] = []
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
        queue.async { self.analyzer.warmUp() }
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

    /// Any queue: positions for `window` (recording seconds), delivered on
    /// the live queue once its last slot is posed; nil if they can't be found.
    func positions(token: UUID, window: ClosedRange<Double>, diagnosticID: String,
                   completion: @escaping (SwingPositions?) -> Void) {
        let registeredAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            if let first = self.entries.first, first.time > window.lowerBound + Self.slot {
                completion(nil)
                return
            }
            self.requests.append(Request(token: token, window: window, diagnosticID: diagnosticID,
                                         registeredAt: registeredAt, completion: completion))
            self.queue.asyncAfter(deadline: .now() + Self.requestTimeout) { self.expire(token) }
            if self.mode == .copy {
                // Pose the backlog one frame per block so new frames interleave.
                for entry in self.entries where window.contains(entry.time) && !entry.posed {
                    let time = entry.time
                    self.queue.async { self.poseEntry(at: time) }
                }
            }
            self.fulfil()
        }
    }

    /// Fails every open request, e.g. when Auto stops.
    func reset() {
        queue.async {
            for request in self.requests { request.completion(nil) }
            self.requests.removeAll()
            self.entries.removeAll()
        }
    }

    /// Fails a request whose window never filled, e.g. Auto paused for review.
    private func expire(_ token: UUID) {
        guard let index = requests.firstIndex(where: { $0.token == token }) else { return }
        let request = requests.remove(at: index)
        CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", id: request.diagnosticID,
                                              state: ["error": "live window timed out", "path": "live-\(mode.rawValue)"])
        request.completion(nil)
    }

    private func append(_ entry: Entry) {
        var entry = entry
        // Copies from before a restart of the recording timeline.
        if let last = entries.last, entry.time < last.time { entries.removeAll() }
        let wanted = mode == .pose || requests.contains { $0.window.contains(entry.time) }
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

    private func poseEntry(at time: Double) {
        guard let index = entries.firstIndex(where: { $0.time == time }), !entries[index].posed,
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
        // The model expects one pose per slot; a skipped copy leaves a gap.
        guard let first = slots.first, let last = slots.last,
              slots.count == Int(((last.time - first.time) / Self.slot).rounded()) + 1 else {
            CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", id: request.diagnosticID,
                                                  state: ["error": "live window has gaps", "path": "live-\(mode.rawValue)"])
            request.completion(nil)
            return
        }
        var timing = SwingPositionAnalyzer.Timing()
        timing.poseCalls = poseCalls
        timing.poseSeconds = poseSeconds
        let positions = try? analyzer.positions(grid: slots.map(\.pose), playable: first.time...last.time,
                                                timeScale: 1, timing: &timing)
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
            "model": SwingPositions.currentModel, "path": "live-\(mode.rawValue)",
            "slots": timing.slots.map(String.init).joined(separator: ","),
            "clipTimes": positions?.positions.map { String(format: "%.3f", $0.clipTime) }.joined(separator: ",") ?? "",
            "error": positions == nil ? "failed" : "none",
        ])
        request.completion(positions)
    }

    // MARK: - Copy

    private func scaledCopy(of source: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let targetWidth = width > 0 ? min(width, sourceWidth) : sourceWidth
        let targetHeight = (sourceHeight * targetWidth / sourceWidth) & ~1
        if pool == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(source),
                kCVPixelBufferWidthKey: targetWidth,
                kCVPixelBufferHeightKey: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
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
