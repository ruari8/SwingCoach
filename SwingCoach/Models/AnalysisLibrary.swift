//
//  AnalysisLibrary.swift
//  SwingCoach
//
//  Stores completed swing analyses locally so Coach results survive app restarts.
//

import Foundation

struct SavedAnalysisMetric: Codable, Equatable {
    let key: String
    let name: String
    let value: String
}

struct SavedAnalysisDrill: Codable, Equatable {
    let title: String
    let summary: String
}

struct SavedAnalysisVideo: Codable, Equatable {
    let key: String
    var url: String
    var refreshedAt: Date
}

struct SavedAnalysis: Identifiable, Codable, Equatable {
    let id: UUID
    let swingID: UUID
    let analysisID: String
    let createdAt: Date
    let summary: String
    let metrics: [SavedAnalysisMetric]
    var annotatedVideo: SavedAnalysisVideo?
    let drills: [SavedAnalysisDrill]
}

@MainActor
final class AnalysisLibrary: ObservableObject {
    @Published private(set) var analyses: [SavedAnalysis] = []

    static let shared = AnalysisLibrary()

    private let storageURL: URL
    private let signedURLRefreshInterval: TimeInterval = 45 * 60

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("analysis_library.json")
        loadFromDisk()
    }

    func analysis(for swing: SavedSwing) -> SavedAnalysis? {
        analyses.first { $0.swingID == swing.id }
    }

    func save(_ response: SwingCoachAPI.AnalysisResponse, for swing: SavedSwing) -> SavedAnalysis {
        let saved = SavedAnalysis(
            id: UUID(),
            swingID: swing.id,
            analysisID: response.analysisID,
            createdAt: Date(),
            summary: response.summary,
            metrics: response.metrics.map {
                SavedAnalysisMetric(key: $0.key, name: $0.name, value: $0.value)
            },
            annotatedVideo: response.annotatedVideo.map {
                SavedAnalysisVideo(key: $0.key, url: $0.url, refreshedAt: Date())
            },
            drills: response.drills.map {
                SavedAnalysisDrill(title: $0.title, summary: $0.summary)
            }
        )

        analyses.removeAll { $0.swingID == swing.id }
        analyses.insert(saved, at: 0)
        saveToDisk()
        return saved
    }

    func updateAnnotatedVideoURL(for analysisID: String, url: String) {
        guard let index = analyses.firstIndex(where: { $0.analysisID == analysisID }),
              var video = analyses[index].annotatedVideo else {
            return
        }

        video.url = url
        video.refreshedAt = Date()
        analyses[index].annotatedVideo = video
        saveToDisk()
    }

    func needsArtifactRefresh(_ analysis: SavedAnalysis) -> Bool {
        guard let video = analysis.annotatedVideo else { return false }
        return Date().timeIntervalSince(video.refreshedAt) > signedURLRefreshInterval
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(analyses)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save analyses: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            analyses = try JSONDecoder().decode([SavedAnalysis].self, from: data)
            print("Loaded \(analyses.count) analyses from library")
        } catch {
            print("Failed to load analyses: \(error)")
            analyses = []
        }
    }
}
