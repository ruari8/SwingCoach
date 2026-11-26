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
    /// Minimum clubhead or grip displacement from address (as a share of body
    /// scale) that counts as the start of the takeaway. Resting jitter at
    /// address stays under 0.8%; 1.5% sustained over `takeawayStartRun`
    /// consecutive track samples (~33 ms at 60 fps) catches first movement
    /// without tripping on single-frame detector noise or DTL foreshortening.
    static let takeawayStartThreshold = 0.015
    static let takeawayStartRun = 3

    struct Times: Equatable {
        /// Clip times; nil where the track couldn't place the position.
        var takeawayStart: Double?
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

        // First movement after P1 (address), before P2: takeaway start for tempo.
        times.takeawayStart = takeawayStart(geometry: geometry, modelTimes: modelTimes, takeawayTime: times.takeaway)

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

    /// First sustained movement of the clubhead or grip away from address (P1),
    /// strictly between P1 and P2. Returns nil when the address club is missing,
    /// too few track samples fall in (P1, P2), or displacement never sustains
    /// `takeawayStartThreshold` over `takeawayStartRun` consecutive samples.
    static func takeawayStart(
        geometry: CoachingSwingGeometry,
        modelTimes: [Int: Double],
        takeawayTime: Double? = nil
    ) -> Double? {
        guard let p1 = modelTimes[1],
              let p2 = takeawayTime ?? modelTimes[2],
              p2 > p1,
              let address = geometry.shaft(at: 1),
              geometry.bodyScale > 0
        else { return nil }

        let early: [(time: Double, displacement: Double)] = geometry.trackedShafts().compactMap { entry in
            guard entry.time > p1, entry.time < p2 else { return nil }
            let headMove = entry.shaft.head.distance(to: address.head)
            let gripMove = entry.shaft.grip.distance(to: address.grip)
            return (entry.time, max(headMove, gripMove) / geometry.bodyScale)
        }
        guard early.count >= takeawayStartRun else { return nil }

        for index in 0...(early.count - takeawayStartRun) {
            let window = early[index..<(index + takeawayStartRun)]
            guard window.allSatisfy({ $0.displacement >= takeawayStartThreshold }) else { continue }
            if index > 0 {
                let previous = early[index - 1]
                let current = early[index]
                let span = current.displacement - previous.displacement
                if previous.displacement < takeawayStartThreshold, span > 1e-9 {
                    let fraction = (takeawayStartThreshold - previous.displacement) / span
                    let interpolated = previous.time + fraction * (current.time - previous.time)
                    if interpolated > p1 && interpolated < p2 {
                        return interpolated
                    }
                }
            }
            return early[index].time
        }
        return nil
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
