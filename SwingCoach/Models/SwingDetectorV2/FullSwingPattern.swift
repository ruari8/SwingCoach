//
//  FullSwingPattern.swift
//  SwingCoach
//
//  Pose-pattern full-swing detection, ported from detectSwings
//  (detect_shots.py find_full_swings / swung_club_visible). The signal is
//  wrist height above the hips in torso units: a backswing top, a fast dip
//  through impact, then a finish held above the shoulders. Fires on every
//  real or practice full swing, never on putts or waggles.
//
//  The offline pipeline additionally masks samples on camera cuts and whip
//  pans; a tripod-mounted live stream has neither, so that logic is dropped.
//

import Foundation

nonisolated enum FullSwingPattern {
    /// Impact times (realTime seconds) of completed full-swing pose patterns
    /// inside `samples`, ordered ascending. A dip only appears once its
    /// finish evidence (up to 2.5s later) has been observed, so streaming
    /// callers can re-run this every frame and emit dips past a watermark.
    static func confirmedDips(in samples: [FrameSampleV2]) -> [Double] {
        let pts = samples.compactMap { sample in
            sample.handHeight.map { (t: sample.realTime, h: $0) }
        }
        guard pts.count >= 4 else { return [] }

        var dips: [Double] = []
        for index in pts.indices {
            let (t, h) = pts[index]
            // Impact: hands at/below hip height, but not absurdly far below
            // (slow-motion/garbage pose readings sit way outside the body).
            guard h <= 0.45, h >= -1.8 else { continue }
            guard pts.allSatisfy({ abs($0.t - t) > 1.5 || $0.h >= -2.0 }) else { continue }

            // Local minimum against the neighboring valid samples.
            if index > 0, pts[index - 1].h < h { continue }
            if index < pts.count - 1, pts[index + 1].h < h { continue }

            // Finish: hands held above the shoulders shortly after impact.
            let after = pts.filter { $0.t > t && $0.t <= t + 2.5 }
            let strong = clustered(after.filter { $0.h > 0.95 }.map(\.t))
            let weak = h < 0.1 && clustered(after.filter { $0.h > 0.8 }.map(\.t))
            guard strong || weak else { continue }

            // Backswing top shortly before, with a fast drop into the dip.
            guard let topIndex = (0..<index).last(where: {
                pts[$0].t >= t - 1.2 && pts[$0].h > 0.6
            }) else { continue }
            let top = pts[topIndex]
            let dt = t - top.t
            guard dt > 0, (top.h - h) / dt >= 1.5 else { continue }

            // A real top is not a single-sample pose-jitter spike: one of the
            // adjacent samples must also be raised.
            var adjacent: [Double] = []
            if topIndex > 0 { adjacent.append(pts[topIndex - 1].h) }
            if topIndex + 1 < pts.count { adjacent.append(pts[topIndex + 1].h) }
            guard let highestAdjacent = adjacent.max(), highestAdjacent >= 0.3 else { continue }

            if let last = dips.last, t - last <= 3.0 { continue }
            dips.append(t)
        }
        return dips
    }

    /// Gate for accepting a practice swing at pose-swing time `t`. Rejects
    /// pose-pattern false positives with no club anywhere near the swinger's
    /// wrists (gestures, stretches) and club-detection storms (several false
    /// club hits per frame means the detector is hallucinating on the scene).
    static func swungClubVisible(around t: Double, in samples: [FrameSampleV2]) -> Bool {
        let window = samples.filter { abs($0.realTime - t) <= 1.5 }
        guard !window.isEmpty else { return false }

        var anchoredClubDetections = 0
        var clubCounts: [Int] = []
        for sample in window {
            let clubs = sample.clubBoxes.filter { $0.confidence >= 0.2 }
            clubCounts.append(clubs.count)
            guard let wrist = sample.wristPoint, let torso = sample.torsoHeight else { continue }
            let radius = 4.5 * max(torso, 0.04)
            anchoredClubDetections += clubs.filter {
                GeometryV2.distance($0.center, wrist) <= radius
            }.count
        }

        let density = Double(clubCounts.reduce(0, +)) / Double(clubCounts.count)
        return anchoredClubDetections >= 3 && density <= 3.0
    }

    /// At least two qualifying sample times with two of them close together:
    /// pose jitter throws isolated one-sample spikes, a real top/finish holds
    /// its height across neighboring samples.
    private static func clustered(_ times: [Double], gap: Double = 0.6) -> Bool {
        guard times.count >= 2 else { return false }
        return zip(times.dropFirst(), times).contains { $0 - $1 <= gap }
    }
}
