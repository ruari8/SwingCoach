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
//  Every Auto swing is queued once it has positions, and a swing or a
//  session summary being opened queues what it needs. Clips are only read
//  while Auto is not recording (paused for review, or stopped): reading
//  them next to the camera has not been checked on a phone.
//
//  With `coaching.coachDuringAuto` on, a swing also gets a first reading
//  while Auto records, from the small copies of its frames Auto already
//  holds in memory (`coachLive`). That reading has the body checks only
//  and is replaced by the clip's when the clip is read.
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
    /// Swings whose last run failed this session; not retried until
    /// relaunch or `retry`.
    @Published private(set) var failed: Set<UUID> = []
    /// Why each failed swing failed, in words for the golfer.
    @Published private(set) var failureReasons: [UUID: String] = [:]
    /// Swings whose first reading from Auto was just replaced by the
    /// clip's, with what the first reading said, until the player has
    /// shown it (`acknowledgeUpdate`).
    @Published private(set) var replacedFirstReadings: [UUID: String] = [:]

    private var queue: [UUID] = []
    /// The clip or live reading in progress, and its task. `id` is the
    /// swing for a clip, the request's token for a live reading.
    private var running: (id: UUID, live: Bool, task: Task<Void, Never>)?

    /// A swing's frames waiting for a live reading.
    private struct LiveJob {
        let token: UUID
        let copies: [SwingLiveCopy]
        let positions: SwingPositions
        let queuedAt: Double
    }

    /// Waiting live readings, oldest first. Only the newest few are kept:
    /// a reading that has fallen behind the golfer is left for the clip.
    private var liveJobs: [LiveJob] = []
    private static let liveJobLimit = 2
    /// Joins each live reading to its swing once that is saved.
    private var liveJoin = CoachingLiveJoin<(evidence: SwingCoachingEvidence, positions: SwingPositions)>()
    private var extractor: CoachingEvidenceExtractor?
    /// Reports read from disk or produced this session. Not published:
    /// views call `report(for:)` while drawing, and it fills this in.
    private var reports: [UUID: SwingCoachingReport] = [:]
    /// Verdicts worked out for the current `revision`; they depend on the
    /// other swings' reports, so any report change clears them. They also
    /// depend on which swings sit earlier in the session and can be
    /// coached, so any library change clears them too.
    private var verdicts: [UUID: (revision: Int, verdict: CoachingVerdict)] = [:]
    private var libraryWatch: AnyCancellable?
    /// Swings whose report file has been looked for, found or not.
    private var checkedDisk: Set<UUID> = []
    /// Club-head trails worked out from stored evidence, per swing and
    /// `revision`. Nil inside means the swing has none.
    private var trails: [UUID: (revision: Int, trail: CoachingClubTrail?)] = [:]
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
        if libraryWatch == nil {
            // Started here, not in init: the library and this store reach
            // for each other. A swing gaining positions, or one added or
            // deleted, changes what "the session so far" is.
            libraryWatch = SwingLibrary.shared.$swings.dropFirst().sink { [weak self] _ in
                self?.verdicts.removeAll()
            }
        }
        if let cached = verdicts[swing.id], cached.revision == revision { return cached.verdict }
        let earlier = earlierInSession(swing).filter(Self.canCoach)
        let verdict = CoachingFeedback.verdict(for: report, earlierInSession: earlier.map { self.report(for: $0) })
        verdicts[swing.id] = (revision, verdict)
        return verdict
    }

    /// The walkthrough for the swing's current report, verdict first.
    func steps(for swing: SavedSwing) -> [CoachingStep] {
        guard let report = report(for: swing) else { return [] }
        return CoachingWalkthrough.steps(for: report, verdict: verdict(for: swing, report: report))
    }

    /// The club head's path from the clip's evidence, or nil when the swing
    /// only has a first reading or the club couldn't be followed.
    func clubTrail(for swing: SavedSwing) -> CoachingClubTrail? {
        if let cached = trails[swing.id], cached.revision == revision { return cached.trail }
        var trail: CoachingClubTrail?
        if let report = report(for: swing), !report.fromLiveCopies,
           let data = try? Data(contentsOf: evidenceURL(swing.id)),
           let evidence = try? JSONDecoder().decode(SwingCoachingEvidence.self, from: data),
           evidence.fromLiveCopies != true {
            trail = CoachingClubTrail.make(from: evidence)
        }
        trails[swing.id] = (revision, trail)
        return trail
    }

    /// How many swings will be read before this one: 0 while it is being
    /// read or when it is next, nil when it isn't waiting.
    func swingsAhead(of swing: SavedSwing) -> Int? {
        if running?.live == false, running?.id == swing.id { return 0 }
        guard let index = queue.firstIndex(of: swing.id) else { return nil }
        return index + (running == nil ? 0 : 1)
    }

    /// True when Auto is recording, so clips wait.
    var isWaitingForAuto: Bool { autoCaptureIsRecording }

    func acknowledgeUpdate(_ id: UUID) {
        if replacedFirstReadings[id] != nil { replacedFirstReadings[id] = nil }
    }

    /// Reads a failed swing again.
    func retry(_ swing: SavedSwing) {
        failed.remove(swing.id)
        failureReasons[swing.id] = nil
        coachWithSession(swing)
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
    /// verdict has the session behind it. The swing itself goes first,
    /// ahead of anything already waiting: it is the one being looked at.
    func coachWithSession(_ swing: SavedSwing) {
        coachIfNeeded(swing)
        if let index = queue.firstIndex(of: swing.id), index > 0 {
            queue.insert(queue.remove(at: index), at: 0)
        }
        for earlier in earlierInSession(swing).reversed() { coachIfNeeded(earlier) }
    }

    /// Queues the swing's clip unless it already has a report from it.
    func coachIfNeeded(_ swing: SavedSwing) {
        guard Self.canCoach(swing),
              report(for: swing).map(\.fromLiveCopies) ?? true,
              !pending.contains(swing.id),
              !failed.contains(swing.id)
        else { return }
        pending.insert(swing.id)
        queue.append(swing.id)
        runNext()
    }

    /// True when a swing gets a first reading while Auto records. Off by
    /// default: it has not been checked on a phone.
    nonisolated static var coachesWhileAutoRecords: Bool {
        UserDefaults.standard.bool(forKey: ExperimentalSettingKey.coachDuringAuto)
    }

    /// Set by the camera while Auto is recording (not while it is paused
    /// for review). No clip is read meanwhile: one being read is stopped
    /// and starts again when Auto stops. Live readings carry on.
    var autoCaptureIsRecording = false {
        didSet {
            guard autoCaptureIsRecording != oldValue else { return }
            if autoCaptureIsRecording {
                if running?.live == false { running?.task.cancel() }
            } else {
                runNext()
            }
        }
    }

    // MARK: - Live readings

    /// Any queue: reads a swing from Auto's copies of its frames, as soon
    /// as its positions are found on them. `token` is the live request,
    /// which `attachLive` or `dropLive` later settles from the capture
    /// side.
    nonisolated static func coachLive(token: UUID, copies: [SwingLiveCopy], positions: SwingPositions) {
        let queuedAt = ProcessInfo.processInfo.systemUptime
        // Only the frame nearest each position is read, so only those are
        // held while the reading waits its turn.
        let copies = positions.positions.compactMap { position in
            copies.min { abs($0.time - position.clipTime) < abs($1.time - position.clipTime) }
        }
        Task { @MainActor in
            let store = SwingCoachingStore.shared
            guard !store.liveJoin.isUnwanted(token) else {
                store.liveReading(token, nil)
                return
            }
            store.liveJobs.append(LiveJob(token: token, copies: copies, positions: positions, queuedAt: queuedAt))
            // Swings hit faster than they can be read: the oldest waits
            // for its clip instead.
            while store.liveJobs.count > liveJobLimit { store.liveReading(store.liveJobs.removeFirst().token, nil) }
            store.runNext()
        }
    }

    /// The request's positions were not found, so no copies will come.
    func noLiveReading(_ token: UUID) {
        liveReading(token, nil)
    }

    /// The request's swing was saved: its reading belongs to `swing`, with
    /// the recording's times mapped onto the clip by (time - offset) * scale.
    func attachLive(_ token: UUID, to swing: SavedSwing, offset: Double, scale: Double) {
        guard SwingPositionProcessor.canFindPositions(for: swing) else {
            dropLive(token)
            return
        }
        if let ready = liveJoin.swing(token, .init(swing: swing.id, offset: offset, scale: scale)) {
            saveLive(ready.reading.evidence, positions: ready.reading.positions, for: ready.owner)
        }
    }

    /// The request's swing was not saved: its reading is not wanted.
    func dropLive(_ token: UUID) {
        _ = liveJoin.swing(token, nil)
        // A waiting reading is settled here; one in progress settles
        // itself when it stops.
        if let index = liveJobs.firstIndex(where: { $0.token == token }) {
            liveJobs.remove(at: index)
            liveReading(token, nil)
        } else if running?.live == true, running?.id == token {
            running?.task.cancel()
        }
    }

    /// The reading side of the join: `evidence`, or nil when none was made.
    private func liveReading(_ token: UUID, _ reading: (evidence: SwingCoachingEvidence, positions: SwingPositions)?) {
        if let ready = liveJoin.reading(token, reading) {
            saveLive(ready.reading.evidence, positions: ready.reading.positions, for: ready.owner)
        }
    }

    private func finishLive(_ token: UUID, positions: SwingPositions, evidence: SwingCoachingEvidence?,
                            extractor: CoachingEvidenceExtractor?) {
        self.extractor = extractor ?? self.extractor
        running = nil
        liveReading(token, evidence.map { ($0, positions) })
        runNext()
    }

    /// Scores live evidence on the swing's clip timeline and keeps the
    /// report, unless the clip has already been read.
    private func saveLive(_ evidence: SwingCoachingEvidence, positions: SwingPositions,
                          for owner: CoachingLiveJoin<(evidence: SwingCoachingEvidence, positions: SwingPositions)>.Owner) {
        guard let swing = SwingLibrary.shared.swings.first(where: { $0.id == owner.swing }),
              report(for: swing).map(\.fromLiveCopies) ?? true
        else { return }
        let mapped = evidence.onClip(offset: owner.offset, scale: owner.scale)
        let clipPositions = SwingPositions(model: positions.model, positions: positions.positions.map {
            SwingPosition(number: $0.number, clipTime: ($0.clipTime - owner.offset) * owner.scale, confidence: $0.confidence)
        })
        guard let report = CoachingAnalyzer.analyze(mapped, positions: clipPositions) else { return }
        // Only the report is kept: the evidence file is the clip's.
        try? JSONEncoder().encode(report).write(to: reportURL(owner.swing), options: .atomic)
        reports[owner.swing] = report
        checkedDisk.insert(owner.swing)
        revision += 1
    }

    func removeCoaching(for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        revision += 1
        queue.removeAll { ids.contains($0) }
        liveJoin.forget(swings: ids)
        for id in ids {
            // A run in progress finds its swing gone and saves nothing.
            if running?.live == false, running?.id == id { running?.task.cancel() }
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
        case failed(String)
    }

    private func runNext() {
        guard running == nil else { return }
        if !liveJobs.isEmpty {
            runLive(liveJobs.removeFirst())
            return
        }
        guard !autoCaptureIsRecording, !queue.isEmpty else { return }
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

        #if DEBUG
        if let simulated = UITestFixture.simulatedClipRead {
            // UI tests: a clip read that takes a set time and gives the
            // fixture's full report, or fails, without Vision.
            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(simulated.seconds * 1_000_000_000))
                let outcome: Outcome
                if Task.isCancelled {
                    outcome = .cancelled
                } else if simulated.fails {
                    outcome = .failed("unreadable")
                } else {
                    outcome = .coached(UITestFixture.fixtureCoachingReport(steep: true), UITestFixture.fixtureEvidence(),
                                       freshEvidence: true)
                }
                self.finish(id, positions: positions, outcome: outcome, extractor: extractor)
            }
            running = (id, false, task)
            return
        }
        #endif

        let task = Task.detached(priority: .utility) {
            let startedAt = ProcessInfo.processInfo.systemUptime
            var worker = extractor
            var outcome = Outcome.failed("no clip")
            var failure = "no clip"
            do {
                // Stored evidence of the current kind is re-scored as is.
                var evidence = (try? Data(contentsOf: evidenceURL))
                    .flatMap { try? JSONDecoder().decode(SwingCoachingEvidence.self, from: $0) }
                if evidence?.version != SwingCoachingEvidence.currentVersion || evidence?.fromLiveCopies == true {
                    evidence = nil
                }
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
                outcome = .failed(failure)
                CaptureCadenceDiagnostics.shared.emit("swing-coaching-failed", id: id.uuidString, state: ["error": failure])
            }
            await self.finish(id, positions: positions, outcome: outcome, extractor: worker)
        }
        running = (id, false, task)
    }

    private func runLive(_ job: LiveJob) {
        let extractor = self.extractor
        let task = Task.detached(priority: .utility) {
            let startedAt = ProcessInfo.processInfo.systemUptime
            var worker = extractor
            var evidence: SwingCoachingEvidence?
            do {
                let made = try worker ?? CoachingEvidenceExtractor(objectDetector: GolfObjectDetector())
                worker = made
                let (read, timing) = try await made.extract(copies: job.copies, positions: job.positions)
                evidence = read
                CaptureCadenceDiagnostics.shared.emit("swing-coaching-live", id: job.token.uuidString, values: [
                    "seconds": ProcessInfo.processInfo.systemUptime - startedAt,
                    "queuedSeconds": startedAt - job.queuedAt,
                    "copies": Double(job.copies.count),
                    "frameSeconds": timing.frameSeconds,
                    "poseSeconds": timing.poseSeconds,
                    "outlineSeconds": timing.outlineSeconds,
                    "detectorSeconds": timing.detectorSeconds,
                ])
            } catch {
                CaptureCadenceDiagnostics.shared.emit("swing-coaching-failed", id: job.token.uuidString,
                                                      state: ["error": error.localizedDescription, "path": "live"])
            }
            await self.finishLive(job.token, positions: job.positions, evidence: evidence, extractor: worker)
        }
        running = (job.token, true, task)
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
            // The player says what the clip's reading changed.
            if let swing = SwingLibrary.shared.swings.first(where: { $0.id == id }),
               let previous = self.report(for: swing), previous.fromLiveCopies {
                replacedFirstReadings[id] = verdict(for: swing, report: previous).headline
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
        case .failed(let reason) where stillThere:
            failed.insert(id)
            failureReasons[id] = Self.plainReason(reason)
            pending.remove(id)
        default:
            pending.remove(id)
        }
        runNext()
    }

    /// The extractor's failure in words for the golfer.
    nonisolated static func plainReason(_ failure: String) -> String {
        switch failure {
        case "no clip": "The video isn't on this phone."
        case "no golfer at address": "No golfer was found at address."
        default: "The video couldn't be read."
        }
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
