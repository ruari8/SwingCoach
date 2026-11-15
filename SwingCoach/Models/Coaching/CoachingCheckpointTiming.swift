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
