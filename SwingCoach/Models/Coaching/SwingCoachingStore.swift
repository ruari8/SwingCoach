//
//  SwingCoachingStore.swift
//  SwingCoach
//
//  Coaches library swings and keeps the results. For a down-the-line swing
//  with positions and an app-owned clip, it builds the evidence from the
//  clip in the background (one swing at a time), scores it, and saves both
//  beside the library: `<id>.evidence.json` and `<id>.report.json` under
//  Application Support/SwingCoaching. Reports are small and read on demand;
//  evidence is kept so a change to the metrics can re-score without the clip.
//
//  Coaching runs when a swing is opened and when a session summary asks for
//  its swings. It does not run during Auto capture unless
//  `coaching.coachDuringAuto` is on: reading clips next to the camera has
//  not been checked on a phone.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class SwingCoachingStore: ObservableObject {
    static let shared = SwingCoachingStore()

    /// Counts reports produced or removed this session, so views that read
    /// `report(for:)` redraw when one arrives.
    @Published private(set) var revision = 0
    /// Swings queued or running.
    @Published private(set) var pending: Set<UUID> = []
    /// Swings whose last run failed this session; not retried until relaunch.
    @Published private(set) var failed: Set<UUID> = []

    private var queue: [UUID] = []
    /// The swing being coached now, and its task.
    private var running: (id: UUID, task: Task<Void, Never>)?
    private var extractor: CoachingEvidenceExtractor?
    /// Reports read from disk or produced this session. Not published:
    /// views call `report(for:)` while drawing, and it fills this in.
    private var reports: [UUID: SwingCoachingReport] = [:]
    /// Verdicts worked out for the current `revision`; they depend on the
    /// other swings' reports, so any report change clears them.
    private var verdicts: [UUID: (revision: Int, verdict: CoachingVerdict)] = [:]
    /// Swings whose report file has been looked for, found or not.
    private var checkedDisk: Set<UUID> = []
    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = support.appendingPathComponent("SwingCoaching", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func canCoach(_ swing: SavedSwing) -> Bool {
        SwingPositionProcessor.canFindPositions(for: swing)
            && swing.swingPositions?.model == SwingPositions.currentModel
    }

    /// The swing's current report, from memory or disk. Nil until coached.
    func report(for swing: SavedSwing) -> SwingCoachingReport? {
        if let report = reports[swing.id] { return report }
        guard !checkedDisk.contains(swing.id) else { return nil }
        checkedDisk.insert(swing.id)
        guard let data = try? Data(contentsOf: reportURL(swing.id)),
              let report = try? JSONDecoder().decode(SwingCoachingReport.self, from: data),
              report.version == SwingCoachingReport.currentVersion
        else { return nil }
        reports[swing.id] = report
        return report
    }

    /// What to say about the swing, judged against the swings hit before it
    /// in the same session.
    func verdict(for swing: SavedSwing, report: SwingCoachingReport) -> CoachingVerdict {
        if let cached = verdicts[swing.id], cached.revision == revision { return cached.verdict }
        let earlier = earlierInSession(swing).filter(Self.canCoach)
        let reports = earlier.compactMap { self.report(for: $0) }
        // The session's themes only apply once every earlier swing has been
        // coached; until then the swing is judged on its own, so the pill
        // doesn't depend on which swings happen to have been opened.
        let verdict = CoachingFeedback.verdict(for: report, earlier: reports.count == earlier.count ? reports : [])
        verdicts[swing.id] = (revision, verdict)
        return verdict
    }

    /// The checks the coach draws on this swing by default.
    func coachPicks(for swing: SavedSwing) -> Set<CoachingMetricID> {
        guard let report = report(for: swing) else { return [] }
        return CoachingFeedback.picks(for: verdict(for: swing, report: report))
    }

    /// The swings hit before this one in its session, oldest first.
    private func earlierInSession(_ swing: SavedSwing) -> [SavedSwing] {
        let session = SwingSession.group(SwingLibrary.shared.swings.filter { !$0.isReference })
            .first { $0.swings.contains { $0.id == swing.id } }
        return (session?.swings ?? [])
            .filter { $0.createdAt < swing.createdAt }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Queues the swing and the swings before it in its session, so its
    /// verdict has the session behind it. The swing itself goes first.
    func coachWithSession(_ swing: SavedSwing) {
        coachIfNeeded(swing)
        for earlier in earlierInSession(swing).reversed() { coachIfNeeded(earlier) }
    }

    /// Queues the swing unless it already has a current report.
    func coachIfNeeded(_ swing: SavedSwing) {
        guard Self.canCoach(swing),
              report(for: swing) == nil,
              !pending.contains(swing.id),
              !failed.contains(swing.id)
        else { return }
        pending.insert(swing.id)
        queue.append(swing.id)
        runNext()
    }

    /// After an Auto save. Off by default; see the file header.
    func coachAfterCapture(_ swing: SavedSwing) {
        guard coachesDuringAuto else { return }
        coachIfNeeded(swing)
    }

    private var coachesDuringAuto: Bool {
        UserDefaults.standard.bool(forKey: ExperimentalSettingKey.coachDuringAuto)
    }

    /// Set by the camera while Auto is recording (not while it is paused
    /// for review). Unless the setting allows it, nothing runs meanwhile:
    /// a run in progress is stopped and starts again when Auto stops.
    var autoCaptureIsRecording = false {
        didSet {
            guard autoCaptureIsRecording != oldValue else { return }
            if mayRun {
                runNext()
            } else {
                running?.task.cancel()
            }
        }
    }

    private var mayRun: Bool { !autoCaptureIsRecording || coachesDuringAuto }

    func removeCoaching(for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        revision += 1
        queue.removeAll { ids.contains($0) }
        for id in ids {
            // A run in progress finds its swing gone and saves nothing.
            if running?.id == id { running?.task.cancel() }
            pending.remove(id)
            reports[id] = nil
            checkedDisk.remove(id)
            try? FileManager.default.removeItem(at: reportURL(id))
            try? FileManager.default.removeItem(at: evidenceURL(id))
        }
    }

    private func reportURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).report.json")
    }

    private func evidenceURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).evidence.json")
    }

    private enum Outcome {
        /// `freshEvidence` is true when it was just built from the clip and
        /// still has to be saved.
        case coached(SwingCoachingReport, SwingCoachingEvidence, freshEvidence: Bool)
        case cancelled
        case failed
    }

    private func runNext() {
        guard running == nil, mayRun, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        let library = SwingLibrary.shared
        guard let swing = library.swings.first(where: { $0.id == id }),
              let stored = swing.swingPositions,
              let timeScale = swing.sourceTimeScale
        else {
            pending.remove(id)
            failed.insert(id)
            runNext()
            return
        }
        // Start from the model's own times, not ones an earlier run re-timed.
        let positions = Self.modelPositions(stored)
        let videoURL = library.localVideoURL(for: swing)
        let evidenceURL = evidenceURL(id)
        let extractor = self.extractor

        let task = Task.detached(priority: .utility) {
            let startedAt = ProcessInfo.processInfo.systemUptime
            var worker = extractor
            var outcome = Outcome.failed
            var failure = "no clip"
            do {
                // Stored evidence of the current kind is re-scored as is.
                var evidence = (try? Data(contentsOf: evidenceURL))
                    .flatMap { try? JSONDecoder().decode(SwingCoachingEvidence.self, from: $0) }
                if evidence?.version != SwingCoachingEvidence.currentVersion { evidence = nil }
                var timing = CoachingEvidenceExtractor.Timing()
                var fresh = false
                if evidence == nil, let videoURL {
                    let made = try worker ?? CoachingEvidenceExtractor(objectDetector: GolfObjectDetector())
                    worker = made
                    (evidence, timing) = try await made.extract(asset: AVURLAsset(url: videoURL), positions: positions,
                                                                timeScale: timeScale)
                    fresh = true
                }
                if let evidence {
                    if let report = CoachingAnalyzer.analyze(evidence, positions: positions) {
                        outcome = .coached(report, evidence, freshEvidence: fresh)
                        CaptureCadenceDiagnostics.shared.emit("swing-coaching", id: id.uuidString, values: [
                            "seconds": ProcessInfo.processInfo.systemUptime - startedAt,
                            "trackSeconds": timing.trackSeconds,
                            "trackSamples": Double(timing.trackSamples),
                            "frameSeconds": timing.frameSeconds,
                            "outlineSeconds": timing.outlineSeconds,
                            "metrics": Double(report.metrics.count),
                        ])
                    } else {
                        failure = "no golfer at address"
                    }
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                failure = error.localizedDescription
            }
            if case .failed = outcome {
                CaptureCadenceDiagnostics.shared.emit("swing-coaching-failed", id: id.uuidString, state: ["error": failure])
            }
            await self.finish(id, positions: positions, outcome: outcome, extractor: worker)
        }
        running = (id, task)
    }

    private func finish(_ id: UUID, positions: SwingPositions, outcome: Outcome, extractor: CoachingEvidenceExtractor?) {
        self.extractor = extractor
        running = nil
        // Nothing is saved for a swing deleted while it was being coached.
        let stillThere = SwingLibrary.shared.swings.contains { $0.id == id }
        switch outcome {
        case .coached(let report, let evidence, let freshEvidence) where stillThere:
            // Files are written here, after the check, so a deleted swing's
            // files can't come back. They are small.
            if freshEvidence {
                try? JSONEncoder().encode(evidence).write(to: evidenceURL(id), options: .atomic)
            }
            try? JSONEncoder().encode(report).write(to: reportURL(id), options: .atomic)
            reports[id] = report
            checkedDisk.insert(id)
            revision += 1
            pending.remove(id)
            // The player's position strip jumps to the same frames the
            // drawings were measured on.
            let retimed = Self.retimed(positions, by: evidence)
            if SwingLibrary.shared.swings.first(where: { $0.id == id })?.swingPositions != retimed {
                SwingLibrary.shared.setSwingPositions(retimed, for: id)
            }
        case .cancelled where stillThere:
            // Stopped for Auto: first in line when coaching may run again.
            queue.insert(id, at: 0)
        case .failed where stillThere:
            failed.insert(id)
            pending.remove(id)
        default:
            pending.remove(id)
        }
        runNext()
    }

    nonisolated static func modelPositions(_ stored: SwingPositions) -> SwingPositions {
        guard let modelTimes = stored.modelClipTimes, modelTimes.count == stored.positions.count else { return stored }
        return SwingPositions(model: stored.model, positions: zip(stored.positions, modelTimes).map { position, time in
            SwingPosition(number: position.number, clipTime: time, confidence: position.confidence)
        })
    }

    nonisolated static func retimed(_ positions: SwingPositions, by evidence: SwingCoachingEvidence) -> SwingPositions {
        var result = SwingPositions(model: positions.model, positions: positions.positions.map { position in
            SwingPosition(number: position.number,
                          clipTime: evidence.frame(position.number)?.clipTime ?? position.clipTime,
                          confidence: position.confidence)
        })
        if result.positions != positions.positions {
            result.modelClipTimes = positions.positions.map(\.clipTime)
        }
        return result
    }
}
