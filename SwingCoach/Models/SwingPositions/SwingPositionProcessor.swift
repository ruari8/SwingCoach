//
//  SwingPositionProcessor.swift
//  SwingCoach
//
//  Stores P1-P10 on library swings. Auto swings normally get them from
//  LiveSwingPoses, found on live frames before the clip is saved; `attach`
//  and `deliverLive` join the two in either order. Otherwise, and whenever
//  the live run fails, SwingPositionAnalyzer reads the saved clip in the
//  background, one clip at a time: after an Auto save, and when a swing is
//  opened without current positions (e.g. the app was closed before the
//  first run finished).
//

import Combine
import Foundation

@MainActor
final class SwingPositionProcessor: ObservableObject {
    static let shared = SwingPositionProcessor()

    /// Swings queued or running, live or from the saved clip.
    @Published private(set) var pending: Set<UUID> = []
    /// Swings whose last run failed this session; not retried until relaunch.
    @Published private(set) var failed: Set<UUID> = []

    private var queue: [UUID] = []
    private var isRunning = false
    private var analyzer: SwingPositionAnalyzer?
    /// Saved swing for each live request, and the mapping onto its clip:
    /// (time - offset) * scale.
    private var liveOwners: [UUID: (swing: UUID, offset: Double, scale: Double)] = [:]
    /// Live results that arrived before their swing was saved.
    private var liveResults: [UUID: SwingPositions?] = [:]

    private init() {}

    static func canFindPositions(for swing: SavedSwing) -> Bool {
        swing.vantage == .dtl && swing.sourceTimeScale != nil && !swing.isReference
    }

    func findPositionsIfNeeded(for swing: SavedSwing) {
        guard Self.canFindPositions(for: swing),
              swing.swingPositions?.model != SwingPositions.currentModel,
              !pending.contains(swing.id),
              !failed.contains(swing.id)
        else {
            return
        }
        pending.insert(swing.id)
        queue.append(swing.id)
        runNext()
    }

    /// Joins live request `token` to its saved swing, mapping its recording
    /// times onto the clip with (time - offset) * scale.
    func attach(_ token: UUID, to swing: SavedSwing, offset: Double, scale: Double) {
        guard Self.canFindPositions(for: swing) else {
            liveResults[token] = nil
            return
        }
        liveOwners[token] = (swing.id, offset, scale)
        pending.insert(swing.id)
        if let result = liveResults.removeValue(forKey: token) {
            deliverLive(token, result)
        }
    }

    /// Result of live request `token`, nil if it failed. Every request delivers
    /// once; a failure falls back to reading the saved clip.
    func deliverLive(_ token: UUID, _ positions: SwingPositions?) {
        guard let owner = liveOwners.removeValue(forKey: token) else {
            liveResults[token] = .some(positions)
            return
        }
        pending.remove(owner.swing)
        if let positions {
            let mapped = SwingPositions(model: positions.model, positions: positions.positions.map {
                SwingPosition(number: $0.number, clipTime: ($0.clipTime - owner.offset) * owner.scale,
                              confidence: $0.confidence)
            })
            SwingLibrary.shared.setSwingPositions(mapped, for: owner.swing)
        } else if let swing = SwingLibrary.shared.swings.first(where: { $0.id == owner.swing }) {
            findPositionsIfNeeded(for: swing)
        }
    }

    private func runNext() {
        guard !isRunning, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        let library = SwingLibrary.shared
        guard let swing = library.swings.first(where: { $0.id == id }),
              let url = library.localVideoURL(for: swing),
              let timeScale = swing.sourceTimeScale
        else {
            // Deleted swing, or no app-owned copy of the clip to read.
            pending.remove(id)
            failed.insert(id)
            runNext()
            return
        }

        isRunning = true
        let analyzer = self.analyzer
        let window = swing.swingWindow
        let queuedAt = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .utility) {
            let outcome: Result<(SwingPositionAnalyzer, SwingPositions), Error>
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                let worker = try analyzer ?? SwingPositionAnalyzer()
                let (positions, timing) = try await worker.analyze(videoURL: url, timeScale: timeScale, window: window)
                CaptureCadenceDiagnostics.shared.emit("swing-positions", id: id.uuidString, values: [
                    "decodedFrames": Double(timing.decodedFrames),
                    "poseCalls": Double(timing.poseCalls),
                    "bodySlots": Double(timing.bodySlots),
                    "readAndPoseSeconds": timing.readAndPoseSeconds,
                    "decodeSeconds": timing.decodeSeconds,
                    "poseSeconds": timing.poseSeconds,
                    "modelSeconds": timing.modelSeconds,
                    "queuedSeconds": startedAt - queuedAt,
                ], state: [
                    "model": positions.model, "path": "library",
                    "slots": timing.slots.map(String.init).joined(separator: ","),
                    "clipTimes": positions.positions.map { String(format: "%.3f", $0.clipTime) }.joined(separator: ","),
                ])
                outcome = .success((worker, positions))
            } catch {
                CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", id: id.uuidString,
                                                      state: ["error": error.localizedDescription, "path": "library"])
                outcome = .failure(error)
            }
            await self.finish(id, outcome)
        }
    }

    private func finish(_ id: UUID, _ outcome: Result<(SwingPositionAnalyzer, SwingPositions), Error>) {
        switch outcome {
        case .success(let (worker, positions)):
            analyzer = worker
            SwingLibrary.shared.setSwingPositions(positions, for: id)
        case .failure:
            failed.insert(id)
        }
        pending.remove(id)
        isRunning = false
        runNext()
    }
}
