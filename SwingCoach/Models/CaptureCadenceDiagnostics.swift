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

/// Wall time spent in the live detector per report window. Owned by the analysis queue.
nonisolated struct DetectorTimingWindow {
    private var calls = 0
    private var inferences = 0
    private var totalInferenceSeconds = 0.0
    private var maxSeconds = 0.0

    mutating func record(seconds: Double, inferred: Bool) {
        guard seconds.isFinite, seconds >= 0 else { return }
        calls += 1
        maxSeconds = max(maxSeconds, seconds)
        if inferred {
            inferences += 1
            totalInferenceSeconds += seconds
        }
    }

    mutating func takeValues() -> [String: Double] {
        let values = [
            "calls": Double(calls),
            "inferences": Double(inferences),
            "meanInferenceMS": inferences > 0 ? totalInferenceSeconds / Double(inferences) * 1_000 : 0,
            "maxMS": maxSeconds * 1_000
        ]
        self = DetectorTimingWindow()
        return values
    }
}

/// One serial writer, at most two 24 MiB files. Used only on the diagnostics queue.
nonisolated struct CaptureDiagnosticFile: Sendable {
    let directory: URL
    var maxBytes = 25_165_824

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

/// How one saved Auto swing was recorded, read back from the diagnostics log.
nonisolated struct CaptureRecord: Codable, Sendable {
    let runID: String
    let build: String?
    let recordingPolicy: String?
    let sourceFPS: Double?
    let width: Int?
    let height: Int?
    let bitRate: Int?
    /// Seconds since the Auto session started, the timeline of every log event.
    let sourceStart: Double?
    let sourceEnd: Double?
}

nonisolated extension CaptureCadenceDiagnostics {
    static let exportFilename = "capture-diagnostics.jsonl"

    /// Writes the log lines of every process run that saved one of `swingIDs`
    /// to `folder`, and returns how each of those swings was recorded. Other
    /// runs stay on the phone. Diagnostics are optional: on any failure the
    /// export goes ahead without the log file.
    func exportLog(for swingIDs: Set<String>, to folder: URL) async -> (file: URL?, records: [String: CaptureRecord]) {
        let snapshot = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-\(UUID().uuidString)")
        let destination = folder.appendingPathComponent(Self.exportFilename)
        return await withCheckedContinuation { continuation in
            queue.async {
                // Copy under the queue so no event is half written, then filter off it.
                let sources: [URL]
                do {
                    sources = try self.snapshotLog(to: snapshot)
                } catch {
                    Self.logger.error("Could not copy capture diagnostics: \(error.localizedDescription, privacy: .public)")
                    try? FileManager.default.removeItem(at: snapshot)
                    continuation.resume(returning: (nil, [:]))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { try? FileManager.default.removeItem(at: snapshot) }
                    let records = Self.captureRecords(in: sources, swingIDs: swingIDs)
                    let runIDs = Set(records.values.map(\.runID))
                    guard !runIDs.isEmpty else {
                        continuation.resume(returning: (nil, records))
                        return
                    }
                    do {
                        try Self.runLines(in: sources, runIDs: runIDs).write(to: destination, options: .atomic)
                        continuation.resume(returning: (destination, records))
                    } catch {
                        Self.logger.error("Could not export capture diagnostics: \(error.localizedDescription, privacy: .public)")
                        try? FileManager.default.removeItem(at: destination)
                        continuation.resume(returning: (nil, records))
                    }
                }
            }
        }
    }

    /// Oldest file first. Call on `queue`.
    private func snapshotLog(to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied: [URL] = []
        for name in ["capture.previous.jsonl", "capture.jsonl"] {
            let source = file.directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let copy = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: copy)
            copied.append(copy)
        }
        return copied
    }

    static func runLines(in logs: [URL], runIDs: Set<String>) throws -> Data {
        let markers = runIDs.map { "\"runID\":\"\($0)\"" }
        var output = Data()
        for url in logs {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") where markers.contains(where: { line.contains($0) }) {
                output.append(contentsOf: line.utf8)
                output.append(0x0A)
            }
        }
        return output
    }

    /// Joins each `swing-saved` event to the `writer-start` of its first chunk.
    static func captureRecords(in logs: [URL], swingIDs: Set<String>) -> [String: CaptureRecord] {
        var builds: [String: String] = [:]
        var writers: [String: [String: Any]] = [:]
        var saved: [(swingID: String, event: [String: Any])] = []
        for url in logs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                // Most lines are per-second summaries; skip them before parsing.
                guard line.contains("\"boundary\":\"run\"") || line.contains("\"boundary\":\"writer-start\"")
                        || line.contains("\"boundary\":\"swing-saved\""),
                      let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let boundary = event["boundary"] as? String else { continue }
                let state = event["state"] as? [String: String] ?? [:]
                switch boundary {
                case "run":
                    if let runID = event["runID"] as? String { builds[runID] = state["build"] }
                case "writer-start":
                    if let id = event["id"] as? String { writers[id] = event }
                default:
                    if let swingID = state["swingID"], swingIDs.contains(swingID) { saved.append((swingID, event)) }
                }
            }
        }
        var records: [String: CaptureRecord] = [:]
        for (swingID, event) in saved {
            let values = event["values"] as? [String: Double] ?? [:]
            let runID = event["runID"] as? String ?? ""
            let writer = (event["id"] as? String).flatMap { writers[$0] }
            let writerValues = writer?["values"] as? [String: Double] ?? [:]
            let writerState = writer?["state"] as? [String: String] ?? [:]
            let chunkStart = values["chunkStart"]
            records[swingID] = CaptureRecord(
                runID: runID,
                build: builds[runID],
                recordingPolicy: writerState["recordingPolicy"],
                sourceFPS: writerValues["sourceFPS"],
                width: writerValues["width"].map { Int($0) },
                height: writerValues["height"].map { Int($0) },
                bitRate: writerValues["bitRate"].map { Int($0) },
                sourceStart: chunkStart,
                sourceEnd: chunkStart.flatMap { start in values["end"].map { start + $0 } }
            )
        }
        return records
    }
}
