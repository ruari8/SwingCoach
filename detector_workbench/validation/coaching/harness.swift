// Runs the app's swing-position and coaching-evidence code on saved clips on
// a Mac. For each clip it writes <out>/<clip>/evidence.json (positions and
// evidence), the frame at each position as p01.jpg ... p10.jpg, and
// report.json (the metrics). Evidence is reused when present; the report is
// always recomputed.
// See docs/COACHING.md for the build command.
//
// Usage: harness <SwingPositionTCN.mlmodelc> <SwingObjectsYOLO11n.mlmodelc> <timeScale> <out-dir> <clip.mp4>...
import AVFoundation
import CoreML
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipRecord: Codable {
    /// How the evidence was read: "clip" or "live". Cached evidence is
    /// reused only for the same mode and time scale.
    var mode: String?
    var clip: String
    var positions: SwingPositions
    var evidence: SwingCoachingEvidence
    /// Camera lens data joined from the export folder's `metadata.json`, if present.
    var lens: CameraLensData?
}

struct ExportManifest: Decodable {
    struct Item: Decodable {
        let filename: String
        let lens: CameraLensData?
    }
    let swings: [Item]
}

private func loadLensByClip(from folder: URL) -> [String: CameraLensData] {
    let manifestURL = folder.appendingPathComponent("metadata.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(ExportManifest.self, from: data)
    else { return [:] }
    var result: [String: CameraLensData] = [:]
    for item in manifest.swings {
        guard let lens = item.lens else { continue }
        result[item.filename] = lens
        result[item.filename.lowercased()] = lens
        let stem = URL(fileURLWithPath: item.filename).deletingPathExtension().lastPathComponent
        result[stem.lowercased()] = lens
    }
    return result
}

@main
struct Harness {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 6 else {
            print("usage: harness <positions.mlmodelc> <objects.mlmodelc> <timeScale> <out-dir> <clip>...")
            exit(2)
        }
        let analyzer = try SwingPositionAnalyzer(modelURL: URL(fileURLWithPath: args[1]))
        let detector = try GolfObjectDetector(modelURL: URL(fileURLWithPath: args[2]), computeUnits: .cpuAndNeuralEngine)
        let extractor = CoachingEvidenceExtractor(objectDetector: detector)
        let timeScale = Double(args[3])!
        let outRoot = URL(fileURLWithPath: args[4])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let decoder = JSONDecoder()

        // The metric table, so review.py doesn't keep its own copy.
        try FileManager.default.createDirectory(at: outRoot, withIntermediateDirectories: true)
        let definitions: [[String: Any]] = CoachingMetricDefinition.all.map {
            ["id": $0.id.rawValue, "title": $0.title, "position": $0.position, "unit": $0.unit.rawValue,
             "zoneLow": $0.zone.lowerBound, "zoneHigh": $0.zone.upperBound, "step": $0.step,
             "below": $0.below, "above": $0.above, "measures": $0.measures, "scored": $0.scored,
             "dependsOnCamera": $0.dependsOnCamera]
        }
        try JSONSerialization.data(withJSONObject: definitions, options: [.prettyPrinted])
            .write(to: outRoot.appendingPathComponent("definitions.json"))

        // COACH_MODE=live coaches from what Auto holds in memory at impact
        // (copies 270 across, 30 a second) instead of the saved clip.
        let live = ProcessInfo.processInfo.environment["COACH_MODE"] == "live"
        var manifestCache: [URL: [String: CameraLensData]] = [:]
        var session: [(name: String, report: SwingCoachingReport, lens: CameraLensData?)] = []
        for path in args.dropFirst(5) {
            let url = URL(fileURLWithPath: path)
            let folder = url.deletingLastPathComponent()
            if manifestCache[folder] == nil {
                manifestCache[folder] = loadLensByClip(from: folder)
            }
            let manifestLens = manifestCache[folder]?[url.lastPathComponent]
                ?? manifestCache[folder]?[url.lastPathComponent.lowercased()]
                ?? manifestCache[folder]?[url.deletingPathExtension().lastPathComponent.lowercased()]
            let name = url.deletingPathExtension().lastPathComponent
            let outDir = outRoot.appendingPathComponent(name)
            let evidenceFile = outDir.appendingPathComponent("evidence.json")
            do {
                var record: ClipRecord
                if let cached = try? decoder.decode(ClipRecord.self, from: Data(contentsOf: evidenceFile)),
                   cached.evidence.version == SwingCoachingEvidence.currentVersion,
                   (cached.mode ?? "clip") == (live ? "live" : "clip"), cached.evidence.timeScale == timeScale {
                    record = cached
                    if let manifestLens, record.lens != manifestLens {
                        record.lens = manifestLens
                        try encoder.encode(record).write(to: evidenceFile)
                    }
                } else {
                    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                    let (positions, _) = try await analyzer.analyze(videoURL: url, timeScale: timeScale)
                    let (evidence, timing) = try await extractor.extract(asset: AVURLAsset(url: url), positions: positions, timeScale: timeScale,
                                                                               configuration: live ? .liveCopies : .clip) { position, image in
                        let file = outDir.appendingPathComponent(String(format: "p%02d.jpg", position))
                        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                            CGImageDestinationFinalize(destination)
                        }
                    }
                    record = ClipRecord(mode: live ? "live" : "clip", clip: url.lastPathComponent, positions: positions,
                                        evidence: evidence, lens: manifestLens)
                    try encoder.encode(record).write(to: evidenceFile)
                    let moved = [2, 6, 7].map { number -> String in
                        let model = positions.positions.first { $0.number == number }?.clipTime ?? 0
                        let used = evidence.frame(number)?.clipTime ?? model
                        return String(format: "P%d %+.0f", number, (used - model) / timeScale * 240)
                    }.joined(separator: " ")
                    let lensText = manifestLens?.summaryText ?? "unknown"
                    print(name, String(format: "frames %.2fs pose %.2fs outline %.2fs detector %.2fs track %.2fs (%d)",
                                       timing.frameSeconds, timing.poseSeconds, timing.outlineSeconds, timing.detectorSeconds,
                                       timing.trackSeconds, timing.trackSamples), "| moved (240 fps frames):", moved, "| lens:", lensText)
                }
                // Records cached before evidence said where it came from.
                if live { record.evidence.fromLiveCopies = true }
                // Metrics are cheap and change often: always recomputed.
                let reportFile = outDir.appendingPathComponent("report.json")
                if let report = CoachingAnalyzer.analyze(record.evidence, positions: record.positions) {
                    try encoder.encode(report).write(to: reportFile)
                    session.append((name, report, record.lens))
                } else {
                    try? FileManager.default.removeItem(at: reportFile)
                    print(name, "no report: address frame lacks the golfer")
                }
            } catch {
                print(name, "FAILED:", error.localizedDescription)
            }
        }

        // The session as the app would see it: swings in the order they were
        // hit (clip names end in their capture time), each judged against
        // the ones before it.
        session.sort { $0.name.suffix(15) < $1.name.suffix(15) }
        var verdicts: [[String: Any]] = []
        for (index, swing) in session.enumerated() {
            let verdict = CoachingFeedback.verdict(for: swing.report, earlier: session[..<index].map(\.report))
            var entry: [String: Any] = ["clip": swing.name, "headline": verdict.headline]
            if let lens = swing.lens {
                entry["lens"] = [
                    "focalLengthPixels": lens.focalLengthPixels,
                    "focalLengthSource": lens.focalLengthSource.rawValue,
                    "videoFieldOfView": lens.videoFieldOfView,
                    "videoZoomFactor": lens.videoZoomFactor,
                    "recordedWidth": lens.recordedWidth,
                    "recordedHeight": lens.recordedHeight
                ] as [String: Any]
            }
            // The same swing judged on its own, with no session behind it.
            switch CoachingFeedback.verdict(for: swing.report) {
            case .notJudged(let why): entry["alone"] = why.rawValue
            case .good, .better: entry["alone"] = "good"
            case .focus(let finding): entry["alone"] = "focus"; entry["aloneFault"] = finding.fault.rawValue
            }
            entry["findings"] = CoachingFeedback.findings(in: swing.report).map {
                ["fault": $0.fault.rawValue, "metric": $0.metric.rawValue, "level": $0.level, "score": $0.score,
                 "supporting": $0.supporting.count] as [String: Any]
            }
            switch verdict {
            case .notJudged(let why): entry["kind"] = why.rawValue
            case .good: entry["kind"] = "good"
            case .better(let fault): entry["kind"] = "better"; entry["fault"] = fault.rawValue
            case .focus(let finding):
                entry["kind"] = "focus"; entry["fault"] = finding.fault.rawValue
                entry["metric"] = finding.metric.rawValue; entry["level"] = finding.level
            }
            verdicts.append(entry)
        }
        let themes: [[String: Any]] = CoachingFeedback.themes(in: session.map(\.report)).map {
            ["fault": $0.fault.rawValue, "title": $0.fault.title, "metric": $0.metric.rawValue, "position": $0.position,
             "text": $0.text, "swings": $0.swings, "measured": $0.measured, "medianLevel": $0.medianLevel, "score": $0.score]
        }
        try JSONSerialization.data(withJSONObject: ["themes": themes, "verdicts": verdicts], options: [.prettyPrinted])
            .write(to: outRoot.appendingPathComponent("session.json"))
        for theme in themes {
            print("theme:", theme["title"]!, "-", theme["text"]!, "\(theme["swings"]!)/\(theme["measured"]!) swings, median level", theme["medianLevel"]!)
        }
    }
}
