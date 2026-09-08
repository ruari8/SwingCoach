import Foundation

@main
struct CaptureCadenceProbe {
    static func main() throws {
        // A pause straddling two reports must still be visible. Bad timestamps
        // must not poison the next report; queue backlog stays separate from PTS.
        var window = CaptureCadenceWindow()
        window.record(pts: 0, expectedFPS: 240)
        window.record(pts: 1.0 / 240, expectedFPS: 240)
        precondition(window.takeSummary()?.gaps == 0)
        window.record(pts: .nan, expectedFPS: 240)
        window.record(pts: 6.0 / 240, expectedFPS: 240, queueDelay: 0.2, pendingFrames: 18)
        let gap = window.takeSummary()!
        precondition(gap.frames == 1 && gap.gaps == 1)
        precondition(gap.maxQueueDelaySeconds == 0.2 && gap.maxPendingFrames == 18)
        window.record(pts: 6.0 / 240, expectedFPS: 240)
        precondition(window.takeSummary()?.nonIncreasing == 1)
        precondition(window.takeSummary() == nil)

        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        let file = CaptureDiagnosticFile(directory: directory, maxBytes: 64)
        let first = Data("{\"record\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}\n".utf8)
        let second = Data("{\"record\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}\n".utf8)
        try file.append(first)
        try file.append(second)
        precondition(tryData(directory.appendingPathComponent("capture.previous.jsonl")) == first)
        precondition(tryData(directory.appendingPathComponent("capture.jsonl")) == second)
        try file.append(first)
        precondition(tryData(directory.appendingPathComponent("capture.previous.jsonl")) == second)
        // Oversized payloads do not destroy an existing log.
        try file.append(Data(repeating: 0, count: 65))
        precondition(tryData(directory.appendingPathComponent("capture.jsonl")) == first)

        let timestamps = try JSONDecoder().decode([Double].self, from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        // Replay measured playback timestamps through the production counter.
        // Use 30fps on the playback timeline, without guessing original capture FPS.
        var replay = CaptureCadenceWindow()
        var reports: [CaptureCadenceWindow.Summary] = []
        for (index, pts) in timestamps.enumerated() {
            replay.record(pts: pts, expectedFPS: 30)
            if index % 30 == 29, let summary = replay.takeSummary() { reports.append(summary) }
        }
        if let summary = replay.takeSummary() { reports.append(summary) }
        let expectedGaps = zip(timestamps, timestamps.dropFirst()).filter { $1 - $0 > 0.05 }.count
        precondition(expectedGaps > 0, "Use an affected clip as the regression scenario")
        precondition(reports.reduce(0) { $0 + $1.frames } == timestamps.count)
        precondition(reports.reduce(0) { $0 + $1.gaps } == expectedGaps)
        let output = CaptureDiagnosticFile(directory: directory.appendingPathComponent("replay"))
        for report in reports {
            var data = try JSONEncoder().encode(report)
            data.append(0x0A)
            try output.append(data)
        }
        let lines = try String(contentsOf: directory.appendingPathComponent("replay/capture.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        precondition(lines.count == reports.count)
        let persisted = try lines.map { try JSONDecoder().decode(CaptureCadenceWindow.Summary.self, from: Data($0.utf8)) }
        precondition(persisted.reduce(0) { $0 + $1.gaps } == expectedGaps)
        print("PASS: boundary gap, invalid/duplicate PTS, queue metrics, file rotation and persisted replay: \(timestamps.count) frames, \(expectedGaps) gaps >50ms across \(reports.count) reports")
    }

    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
