import Foundation
import Combine

/// Keeps each submitted video's request alive independently of the visible page.
@MainActor
final class SwingReviewAnalysis: ObservableObject {
    struct Request {
        let id = UUID()
        var status: SwingAnalysis.AnalysisStatus = .analyzing
        var progressText: String? = "Preparing video..."
        var progress: Float?
    }

    typealias Analyze = @MainActor (SavedSwing, @escaping (String, Float?) -> Void) async throws -> SwingCoachAPI.AnalysisResponse
    typealias Save = @MainActor (SwingCoachAPI.AnalysisResponse, SavedSwing) -> Void

    @Published private(set) var requests: [UUID: Request] = [:]
    private let analyze: Analyze
    private let save: Save

    init(
        analyze: @escaping Analyze = { swing, progress in
            try await SwingCoachAPI.shared.analyzeSwing(swing, onProgress: progress)
        },
        save: @escaping Save = { response, swing in
            // A request finishing after the user removed its swing must not
            // recreate an orphaned analysis.
            guard SwingLibrary.shared.swings.contains(where: { $0.id == swing.id }) else { return }
            _ = AnalysisLibrary.shared.save(response, for: swing)
            SwingLibrary.shared.markAnalyzed(swing)
        }
    ) {
        self.analyze = analyze
        self.save = save
    }

    func run(for swing: SavedSwing) async {
        guard requests[swing.id]?.status != .analyzing else { return }
        let request = Request()
        requests[swing.id] = request

        do {
            let response = try await analyze(swing) { [weak self] stage, progress in
                Task { @MainActor in
                    guard let self,
                          self.requests[swing.id]?.id == request.id,
                          self.requests[swing.id]?.status == .analyzing else { return }
                    self.requests[swing.id]?.progressText = stage
                    self.requests[swing.id]?.progress = progress
                }
            }
            save(response, swing)
            requests[swing.id]?.status = .complete
        } catch {
            requests[swing.id]?.status = .failed(SwingCoachAPI.displayMessage(for: error))
        }
        requests[swing.id]?.progressText = nil
        requests[swing.id]?.progress = nil
    }
}
