//
//  ManualAnnotationStore.swift
//  SwingCoach
//
//  Local-only user drawings for swing self-analysis.
//

import Foundation
import Combine

struct ManualAnnotationPoint: Codable, Equatable {
    let x: Double
    let y: Double
}

enum ManualAnnotationTool: String, Codable, CaseIterable, Equatable {
    case line
    case arrow
    case freehand
    case rectangle
    case circle
    case label
    case eraser
}

struct ManualAnnotation: Identifiable, Codable, Equatable {
    let id: UUID
    let analysisID: String
    let tool: ManualAnnotationTool
    let points: [ManualAnnotationPoint]
    let text: String?
    let colorHex: String
    let strokeWidth: Double
    let timestamp: Double
    let appliesToFullSwing: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        analysisID: String,
        tool: ManualAnnotationTool,
        points: [ManualAnnotationPoint],
        text: String? = nil,
        colorHex: String,
        strokeWidth: Double,
        timestamp: Double,
        appliesToFullSwing: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.analysisID = analysisID
        self.tool = tool
        self.points = points
        self.text = text
        self.colorHex = colorHex
        self.strokeWidth = strokeWidth
        self.timestamp = timestamp
        self.appliesToFullSwing = appliesToFullSwing
        self.createdAt = createdAt
    }

    func isVisible(at currentTime: Double) -> Bool {
        appliesToFullSwing || abs(currentTime - timestamp) <= 0.75
    }
}

@MainActor
final class ManualAnnotationStore: ObservableObject {
    static let shared = ManualAnnotationStore()

    @Published private(set) var annotations: [ManualAnnotation] = []

    private let storageURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("manual_annotations.json")
        loadFromDisk()
    }

    func annotations(for analysisID: String) -> [ManualAnnotation] {
        annotations
            .filter { $0.analysisID == analysisID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func add(_ annotation: ManualAnnotation) {
        annotations.append(annotation)
        saveToDisk()
    }

    func undoLast(for analysisID: String) {
        guard let index = annotations.lastIndex(where: { $0.analysisID == analysisID }) else { return }
        annotations.remove(at: index)
        saveToDisk()
    }

    func remove(_ annotationID: UUID) {
        annotations.removeAll { $0.id == annotationID }
        saveToDisk()
    }

    func clear(for analysisID: String) {
        annotations.removeAll { $0.analysisID == analysisID }
        saveToDisk()
    }

    func removeNearest(
        analysisID: String,
        to point: ManualAnnotationPoint,
        at currentTime: Double,
        threshold: Double = 0.045
    ) {
        let candidates = annotations(for: analysisID)
            .filter { $0.isVisible(at: currentTime) }
            .compactMap { annotation -> (UUID, Double)? in
                guard let distance = annotation.points.map({ $0.distance(to: point) }).min() else { return nil }
                return (annotation.id, distance)
            }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= threshold else { return }
        remove(nearest.0)
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(annotations)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save manual annotations: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            annotations = try JSONDecoder().decode([ManualAnnotation].self, from: data)
        } catch {
            print("Failed to load manual annotations: \(error)")
            annotations = []
        }
    }
}

private extension ManualAnnotationPoint {
    func distance(to other: ManualAnnotationPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
