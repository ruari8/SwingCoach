import Foundation
import os

/// Owned by the queue receiving frames. No sample or pixel buffers are retained.
nonisolated struct CaptureCadenceWindow {
    nonisolated struct Summary: Codable, Sendable {
        let firstPTS: Double
        let lastPTS: Double
        let frames: Int
        let gaps: Int
        let nonIncreasing: Int
        let maxGapSeconds: Double
        let maxQueueDelaySeconds: Double
        let maxPendingFrames: Int
    }

    private var firstPTS: Double?
    private var previousPTS: Double?
    private var frames = 0
    private var gaps = 0
    private var nonIncreasing = 0
    private var maxGap = 0.0
    private var maxQueueDelay = 0.0
    private var maxPending = 0

    mutating func record(pts: Double, expectedFPS: Double, queueDelay: Double = 0, pendingFrames: Int = 0) {
        guard pts.isFinite, expectedFPS.isFinite, expectedFPS > 0 else { return }
        if firstPTS == nil { firstPTS = pts }
        if let previousPTS {
            let delta = pts - previousPTS
            if delta <= 0 { nonIncreasing += 1 }
            // Allow timestamp rounding, but count one missing source frame.
            if delta > 1.5 / expectedFPS { gaps += 1 }
            maxGap = max(maxGap, delta)
        }
        previousPTS = pts
        frames += 1
        maxQueueDelay = max(maxQueueDelay, queueDelay)
        maxPending = max(maxPending, pendingFrames)
    }

    mutating func takeSummary() -> Summary? {
        guard let firstPTS, let previousPTS, frames > 0 else { return nil }
        let summary = Summary(firstPTS: firstPTS, lastPTS: previousPTS, frames: frames,
                              gaps: gaps, nonIncreasing: nonIncreasing, maxGapSeconds: maxGap,
                              maxQueueDelaySeconds: maxQueueDelay, maxPendingFrames: maxPending)
        // Keep the previous timestamp so a gap across report boundaries is counted.
        self.firstPTS = nil
        frames = 0
        gaps = 0
        nonIncreasing = 0
        maxGap = 0
        maxQueueDelay = 0
        maxPending = 0
        return summary
    }
}

/// One serial writer, at most two 8 MiB files. Used only on the diagnostics queue.
nonisolated struct CaptureDiagnosticFile: Sendable {
    let directory: URL
    var maxBytes = 8_388_608

    func append(_ line: Data) throws {
        guard line.count <= maxBytes else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = directory.appendingPathComponent("capture.jsonl")
        let previous = directory.appendingPathComponent("capture.previous.jsonl")
        let size = (try? manager.attributesOfItem(atPath: current.path)[.size] as? Int) ?? 0
        if size + line.count > maxBytes {
            if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
            try manager.moveItem(at: current, to: previous)
        }
        if !manager.fileExists(atPath: current.path) {
            guard manager.createFile(atPath: current.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}

/// Payloads contain counts, timing, format/state and generated IDs, never media.
/// Call at most once per second per frame boundary; lifecycle events are separate.
nonisolated final class CaptureCadenceDiagnostics: Sendable {
    static let shared = CaptureCadenceDiagnostics()
    private static let logger = Logger(subsystem: "Pear.ai.SwingCoach", category: "CaptureCadence")
    private let queue = DispatchQueue(label: "camera.cadence-diagnostics", qos: .utility)
    private let slots = DispatchSemaphore(value: 32)
    private let runID = UUID().uuidString
    private let file: CaptureDiagnosticFile

    private nonisolated struct Event: Encodable, Sendable {
        let schema = 1
        let runID: String
        let date: Date
        let uptime: Double
        let boundary: String
        let id: String
        let cadence: CaptureCadenceWindow.Summary?
        let values: [String: Double]
        let state: [String: String]
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = CaptureDiagnosticFile(directory: support.appendingPathComponent("CaptureDiagnostics"))
        emit("run", state: [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        ])
    }

    func emit(_ boundary: String, id: String = "", cadence: CaptureCadenceWindow.Summary? = nil,
              values: [String: Double] = [:], state: [String: String] = [:]) {
        // A blocked disk must not grow an unbounded backlog or block capture.
        guard slots.wait(timeout: .now()) == .success else { return }
        let event = Event(runID: runID, date: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                          boundary: boundary, id: id, cadence: cadence,
                          values: values.filter { $0.value.isFinite }, state: state)
        queue.async {
            defer { self.slots.signal() }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var data = try encoder.encode(event)
                data.append(0x0A)
                try self.file.append(data)
            } catch {
                Self.logger.error("Could not save capture diagnostics: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
