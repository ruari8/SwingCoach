import XCTest
@testable import SwingCoach

final class CaptureDiagnosticsExportTests: XCTestCase {
    func testSavedSwingJoinsItsFirstChunkWriterAndRunBuild() throws {
        // Lines in the shape the phone wrote on October 12, split across a rotation.
        let previous = """
        {"runID":"RUN-A","state":{"build":"2026.10.4","version":"1.0","os":"26.6.2"},"boundary":"run","date":"2026-10-12T16:45:00Z","uptime":1,"schema":1,"id":"","values":{}}
        {"schema":1,"uptime":2,"date":"2026-10-12T17:17:03Z","values":{"rotation":90,"sourceFPS":240,"bitRate":50000000,"relativeTime":200.5,"height":1080,"width":1920},"boundary":"writer-start","state":{"recordingPolicy":"consecutive-v2","writerSource":"standby","codec":"h264"},"id":"CHUNK-1","runID":"RUN-A"}
        {"schema":1,"uptime":3,"date":"2026-10-12T17:17:03Z","values":{"frames":240},"boundary":"camera","state":{},"id":"","runID":"RUN-A"}
        """
        let current = """
        {"runID":"RUN-A","id":"CHUNK-1","boundary":"swing-saved","schema":1,"uptime":4,"date":"2026-10-12T17:17:04Z","values":{"end":2.9,"start":0,"chunkStart":207.73,"slowMotionFactor":8},"state":{"file":"auto_swing_A.mp4","swingID":"SWING-1"}}
        {"runID":"RUN-A","id":"CHUNK-9","boundary":"swing-saved","schema":1,"uptime":5,"date":"2026-10-12T17:18:04Z","values":{"end":2.9,"start":0,"chunkStart":260},"state":{"swingID":"NOT-EXPORTED"}}

        """
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previousURL = folder.appendingPathComponent("previous.jsonl")
        let currentURL = folder.appendingPathComponent("current.jsonl")
        try previous.write(to: previousURL, atomically: true, encoding: .utf8)
        try current.write(to: currentURL, atomically: true, encoding: .utf8)

        let records = CaptureCadenceDiagnostics.captureRecords(in: [previousURL, currentURL],
                                                               swingIDs: ["SWING-1", "MISSING"])
        XCTAssertEqual(Set(records.keys), ["SWING-1"])
        let record = try XCTUnwrap(records["SWING-1"])
        XCTAssertEqual(record.runID, "RUN-A")
        XCTAssertEqual(record.build, "2026.10.4")
        XCTAssertEqual(record.recordingPolicy, "consecutive-v2")
        XCTAssertEqual(record.sourceFPS, 240)
        XCTAssertEqual(record.width, 1920)
        XCTAssertEqual(record.height, 1080)
        XCTAssertEqual(record.bitRate, 50_000_000)
        XCTAssertEqual(record.sourceStart ?? 0, 207.73, accuracy: 0.0001)
        XCTAssertEqual(record.sourceEnd ?? 0, 210.63, accuracy: 0.0001)
    }

    func testExportedLogKeepsOnlyTheRunsOfTheSelectedSwings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previousURL = folder.appendingPathComponent("previous.jsonl")
        let currentURL = folder.appendingPathComponent("current.jsonl")
        try """
        {"runID":"RUN-OLD","boundary":"run","values":{}}
        {"runID":"RUN-A","boundary":"run","values":{}}
        """.write(to: previousURL, atomically: true, encoding: .utf8)
        try """
        {"runID":"RUN-A","boundary":"camera","values":{}}
        {"runID":"RUN-OLD","boundary":"camera","values":{}}

        """.write(to: currentURL, atomically: true, encoding: .utf8)

        let data = try CaptureCadenceDiagnostics.runLines(in: [previousURL, currentURL], runIDs: ["RUN-A"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), """
        {"runID":"RUN-A","boundary":"run","values":{}}
        {"runID":"RUN-A","boundary":"camera","values":{}}

        """)
    }
}
