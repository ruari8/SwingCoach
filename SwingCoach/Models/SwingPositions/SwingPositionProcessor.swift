//
//  SwingPositionProcessor.swift
//  SwingCoach
//
//  Runs SwingPositionAnalyzer in the background, one clip at a time, and
//  stores the result on the library swing. Called after an Auto swing is
//  saved, and when a swing is opened without current positions (e.g. the app
//  was closed before the first run finished).
//

import Combine
import Foundation

@MainActor
final class SwingPositionProcessor: ObservableObject {
    static let shared = SwingPositionProcessor()

    /// Swings queued or running.
    @Published private(set) var pending: Set<UUID> = []
    /// Swings whose last run failed this session; not retried until relaunch.
    @Published private(set) var failed: Set<UUID> = []

    private var queue: [UUID] = []
    private var isRunning = false
    private var analyzer: SwingPositionAnalyzer?

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
        Task.detached(priority: .utility) {
            let outcome: Result<(SwingPositionAnalyzer, SwingPositions), Error>
            do {
                let worker = try analyzer ?? SwingPositionAnalyzer()
                let (positions, timing) = try await worker.analyze(videoURL: url, timeScale: timeScale)
                CaptureCadenceDiagnostics.shared.emit("swing-positions", id: id.uuidString, values: [
                    "decodedFrames": Double(timing.decodedFrames),
                    "poseCalls": Double(timing.poseCalls),
                    "bodySlots": Double(timing.bodySlots),
                    "readAndPoseSeconds": timing.readAndPoseSeconds,
                    "modelSeconds": timing.modelSeconds,
                ], state: ["model": positions.model])
                outcome = .success((worker, positions))
            } catch {
                CaptureCadenceDiagnostics.shared.emit("swing-positions-failed", id: id.uuidString,
                                                      state: ["error": error.localizedDescription])
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
