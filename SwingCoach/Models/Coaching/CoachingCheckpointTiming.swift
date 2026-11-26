//
//  CoachingCheckpointTiming.swift
//  SwingCoach
//
//  Times the club-defined swing positions off the club itself. The position
//  model reads body pose and lands P2, P6 and P7 within a frame or two at
//  30 fps, which is a long way for a clubhead. With the club followed
//  through the swing, P2 and P6 are where the shaft is level (clubhead at
//  hand height) and P7 is where the ball leaves its spot.
//

import Foundation

nonisolated enum CoachingCheckpointTiming {
    /// Hysteresis thresholds for takeaway start (as a share of body scale):
    /// - Still at address: `takeawayStillRun` consecutive samples under
    ///   `takeawayStillThreshold` (1.1%).
    /// - Sustained takeaway: `takeawayStartRun` consecutive samples at or above
    ///   `takeawayStartThreshold` (1.5%, ~33 ms at 60 fps).
    /// Taking the last still-to-moving transition before P2 skips waggles or
    /// regrips that return to address, while the 1.1% still band avoids false
    /// resets from down-the-line foreshortening mid-takeaway.
    static let takeawayStillThreshold = 0.011
    static let takeawayStillRun = 2
    static let takeawayStartThreshold = 0.015
    static let takeawayStartRun = 3

    struct Times: Equatable {
        /// Clip times; nil where the track couldn't place the position.
        var takeaway: Double?
        var delivery: Double?
        var impact: Double?
    }

    /// `modelTimes` maps position number to the position model's clip time.
    static func refine(geometry: CoachingSwingGeometry, modelTimes: [Int: Double]) -> Times {
        let samples = geometry.evidence.track.sorted { $0.clipTime < $1.clipTime }
        guard let top = modelTimes[4] else { return Times() }

        // Clubhead height above the hands for each sample that shows the club.
        let club: [(time: Double, rise: Double)] = geometry.trackedShafts().map {
            ($0.time, $0.shaft.grip.y - $0.shaft.head.y)
        }

        var times = Times()
        // Going back: the first time the clubhead climbs through hand height.
        let back = club.filter { $0.time <= top }
        for (before, after) in zip(back, back.dropFirst()) where before.rise < 0 && after.rise >= 0 {
            times.takeaway = crossing(before, after)
            break
        }
        // Coming down: the last time it drops through hand height.
        let down = club.filter { $0.time > top }
        for (before, after) in zip(down, down.dropFirst()).reversed() where before.rise > 0 && after.rise <= 0 {
            times.delivery = crossing(before, after)
            break
        }

        // Impact: the ball is on its spot through the downswing, then gone
        // for good. Any later sighting on the spot means an earlier gap was
        // the club or the hands passing in front of it, so impact is where
        // the last absence starts. The clubhead covers the ball a frame or
        // two early from down the line, which is within the body's
        // stillness at impact.
        let after = samples.filter { $0.clipTime > (times.delivery ?? top) }
        let present = after.map(geometry.ballPresent(in:))
        if let lastSeen = present.lastIndex(of: true),
           present.filter({ $0 }).count >= 3,
           present.count - lastSeen - 1 >= 4 {
            times.impact = after[lastSeen + 1].clipTime
        }
        return times
    }

    /// Last still-to-moving departure of the clubhead or grip away from address
    /// (P1), strictly between P1 and P2.
    ///
    /// Requires a detected address clubhead (`address.headDetected`) so clubhead
    /// centres are compared like-for-like, and at least `takeawayStillRun`
    /// consecutive still samples (< `takeawayStillThreshold`) before a sustained
    /// `takeawayStartRun` run (>= `takeawayStartThreshold`). Returns nil when
    /// the club is already moving at P1, the address head wasn't seen, or no
    /// sustained departure follows a still baseline.
    static func takeawayStart(
        geometry: CoachingSwingGeometry,
        modelTimes: [Int: Double],
        takeawayTime: Double? = nil
    ) -> Double? {
        guard let p1 = modelTimes[1],
              let p2 = takeawayTime ?? modelTimes[2],
              p2 > p1,
              let address = geometry.shaft(at: 1),
              address.headDetected,
              geometry.bodyScale > 0
        else { return nil }

        let early: [(time: Double, displacement: Double)] = geometry.trackedShafts().compactMap { entry in
            guard entry.time > p1, entry.time < p2 else { return nil }
            let headMove = entry.shaft.head.distance(to: address.head)
            let gripMove = entry.shaft.grip.distance(to: address.grip)
            return (entry.time, max(headMove, gripMove) / geometry.bodyScale)
        }
        guard early.count >= takeawayStillRun + takeawayStartRun else { return nil }

        var lastTransition: Double?
        var stillStreak = 0
        var hasStillBaseline = false
        var index = 0
        while index < early.count {
            if early[index].displacement < takeawayStillThreshold {
                stillStreak += 1
                if stillStreak >= takeawayStillRun { hasStillBaseline = true }
                index += 1
                continue
            }
            stillStreak = 0
            if hasStillBaseline,
               index + takeawayStartRun <= early.count,
               early[index..<(index + takeawayStartRun)].allSatisfy({ $0.displacement >= takeawayStartThreshold }) {
                var crossingTime = early[index].time
                if index > 0 {
                    let previous = early[index - 1]
                    let current = early[index]
                    let span = current.displacement - previous.displacement
                    if previous.displacement < takeawayStartThreshold, span > 1e-9 {
                        let fraction = (takeawayStartThreshold - previous.displacement) / span
                        let interpolated = previous.time + fraction * (current.time - previous.time)
                        if interpolated > p1 && interpolated < p2 {
                            crossingTime = interpolated
                        }
                    }
                }
                lastTransition = crossingTime
                hasStillBaseline = false
                index += takeawayStartRun
            } else {
                index += 1
            }
        }
        return lastTransition
    }

    /// Applies club-timed frame times and takeaway start from `evidence` onto
    /// `positions` (which holds the position model's own times), preserving
    /// `modelClipTimes` when any position moved. Shared by the app store and the
    /// Mac coaching harness.
    static func retimed(_ positions: SwingPositions, by evidence: SwingCoachingEvidence) -> SwingPositions {
        var result = SwingPositions(model: positions.model, positions: positions.positions.map { position in
            SwingPosition(number: position.number,
                          clipTime: evidence.frame(position.number)?.clipTime ?? position.clipTime,
                          confidence: position.confidence)
        })
        var modelTimes: [Int: Double] = [:]
        for position in positions.positions { modelTimes[position.number] = position.clipTime }
        if let geometry = CoachingSwingGeometry(evidence: evidence) {
            let takeawayTime = result.positions.first { $0.number == 2 }?.clipTime
            result.takeawayStartClipTime = takeawayStart(
                geometry: geometry, modelTimes: modelTimes, takeawayTime: takeawayTime
            )
        }
        if result.positions != positions.positions {
            result.modelClipTimes = positions.positions.map(\.clipTime)
        }
        return result
    }

    /// The model's times with the club's times swapped in where they can
    /// be believed. A club time far from the model's is a tracking slip,
    /// not a better answer, and so is one that would put the positions out
    /// of order. P6 is settled before P7, so P7 is checked against it.
    static func accepting(_ refined: Times, over modelTimes: [Int: Double], timeScale: Double) -> [Int: Double] {
        let slot = timeScale / 30
        var times = modelTimes
        for (position, time, slots) in [(2, refined.takeaway, 4.0), (6, refined.delivery, 2.5), (7, refined.impact, 2.5)] {
            guard let time, let model = modelTimes[position],
                  abs(time - model) <= slots * slot,
                  time > times[position - 1] ?? -.infinity,
                  time < times[position + 1] ?? .infinity
            else { continue }
            times[position] = time
        }
        return times
    }

    private static func crossing(_ before: (time: Double, rise: Double), _ after: (time: Double, rise: Double)) -> Double {
        let span = after.rise - before.rise
        guard abs(span) > 1e-9 else { return before.time }
        return before.time + (after.time - before.time) * (0 - before.rise) / span
    }
}
