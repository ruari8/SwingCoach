import XCTest
@testable import SwingCoach

final class LiveSwingPosesTests: XCTestCase {
    /// Every slot of grid `grid` anchored at `anchor` whose scheduled time
    /// falls inside `window`.
    private func slots(anchor: Double, grid: Int = 1, in window: ClosedRange<Double>) -> [LiveSwingPoses.Slot] {
        (0..<2000).map { LiveSwingPoses.Slot(grid: grid, index: $0, anchor: anchor) }
            .filter { LiveSwingPoses.inWindow($0, window) }
    }

    func testCompleteWindowsAreCoveredAtAnyOffset() {
        // Slot multiples and not, e.g. `-positions-live-after` windows.
        for window in [10.0...12.4, 10.0...12.41, 10.0...12.399833333, 10.0...12.3] {
            for anchor in [0.0, 0.004, 0.0167, 0.03325, 0.029] {
                XCTAssertTrue(LiveSwingPoses.coversWindow(slots(anchor: anchor, in: window), window: window),
                              "window \(window), anchor \(anchor)")
            }
        }
    }

    func testAMissingCopyAnywhereFails() {
        for window in [10.0...12.4, 10.0...12.41, 10.0...12.399833333] {
            for anchor in [0.0, 0.004, 0.0083, 0.03325] {
                let full = slots(anchor: anchor, in: window)
                XCTAssertFalse(LiveSwingPoses.coversWindow(Array(full.dropFirst()), window: window),
                               "first, window \(window), anchor \(anchor)")
                XCTAssertFalse(LiveSwingPoses.coversWindow(Array(full.dropLast()), window: window),
                               "last, window \(window), anchor \(anchor)")
                var middle = full
                middle.remove(at: full.count / 2)
                XCTAssertFalse(LiveSwingPoses.coversWindow(middle, window: window),
                               "middle, window \(window), anchor \(anchor)")
            }
        }
    }

    func testTruncatedTailFails() {
        // Copies through 3.167, then nothing inside the window.
        let window = 1.0...3.4
        XCTAssertFalse(LiveSwingPoses.coversWindow(slots(anchor: 0, in: 1.0...3.2), window: window))
    }

    func testWindowStartingBeforeTheGridFails() {
        // A gap re-anchored the grid at 10.5, after the window's start.
        let window = 10.0...12.4
        XCTAssertFalse(LiveSwingPoses.coversWindow(slots(anchor: 10.5, in: window), window: window))
    }

    func testMixedGridsFail() {
        let window = 10.0...12.4
        let early = slots(anchor: 0, grid: 1, in: 10.0...11.0)
        let late = slots(anchor: 11.004, grid: 2, in: 11.0...12.4)
        XCTAssertFalse(LiveSwingPoses.coversWindow(early + late, window: window))
    }

    func testEmptyWindowFails() {
        XCTAssertFalse(LiveSwingPoses.coversWindow([], window: 10.0...12.4))
    }

    // MARK: - Schedule

    /// 240 fps frame times from `start`, with `jitter(frame)` added and the
    /// frames in `dropped` left out.
    private func frames(count: Int, start: Double = 0, dropped: Set<Int> = [],
                        jitter: (Int) -> Double = { _ in 0 }) -> [Double] {
        (0..<count).filter { !dropped.contains($0) }.map { start + Double($0) / 240 + jitter($0) }
    }

    private func take(_ times: [Double]) -> [LiveSwingPoses.Slot] {
        var schedule = LiveSwingPoses.SlotSchedule()
        return times.compactMap { schedule.take($0) }
    }

    func testScheduleTakesEveryEighthFrame() {
        let slots = take(frames(count: 240))
        XCTAssertEqual(slots.map(\.index), Array(0..<30))
        XCTAssertEqual(Set(slots.map(\.grid)), [1])
    }

    func testScheduleIgnoresJitterBothWays() {
        // ±1 ms, drifting from one sign to the other across the run.
        for sign in [1.0, -1.0] {
            let slots = take(frames(count: 2400) { sign * (0.001 - 0.002 * Double($0) / 2400) })
            XCTAssertEqual(slots.map(\.index), Array(0..<300), "sign \(sign)")
        }
    }

    func testDroppedFramesLeaveGapsNotLateDuplicates() {
        // One dropped frame on a slot: the next frame, 4 ms late, stands in.
        XCTAssertEqual(take(frames(count: 120, dropped: [80])).map(\.index), Array(0..<15))
        // Frames 79-86 dropped: slot 10 is missing, not filled 29 ms late.
        let indices = take(frames(count: 120, dropped: Set(79...86))).map(\.index)
        XCTAssertFalse(indices.contains(10))
        XCTAssertEqual(indices.filter { $0 != 10 }, Array(0..<15).filter { $0 != 10 })
        // A frame exactly one slot late keeps the grid and skips one number.
        var schedule = LiveSwingPoses.SlotSchedule()
        XCTAssertEqual(schedule.take(0)?.index, 0)
        XCTAssertEqual(schedule.take(1.0 / 30)?.index, 1)
        let late = schedule.take(0.1)
        XCTAssertEqual(late?.index, 3)
        XCTAssertEqual(late?.grid, 1)
    }

    func testRestartStartsANewGrid() {
        let slots = take(frames(count: 240) + frames(count: 240))
        XCTAssertEqual(Set(slots.map(\.grid)), [1, 2])
        XCTAssertEqual(slots.filter { $0.grid == 2 }.map(\.index), Array(0..<30))
    }

    func testScheduledCopiesCoverTheWindow() {
        let window = 1.0...3.4
        let slots = take(frames(count: 1000, start: 0.0021) { _ in 0.0009 })
        XCTAssertTrue(LiveSwingPoses.coversWindow(slots.filter { LiveSwingPoses.inWindow($0, window) }, window: window))
    }

    func testWindowIsDueOnlyAfterItsLastSlot() {
        // Review example: slot 481 (16.0333…) is still inside this window.
        let window = 13.633333333333333...16.033333333333335
        let slot480 = LiveSwingPoses.Slot(grid: 1, index: 480, anchor: 0)
        XCTAssertTrue(LiveSwingPoses.inWindow(slot480.next, window))
        XCTAssertFalse(LiveSwingPoses.isDue(window, latest: slot480))
        XCTAssertTrue(LiveSwingPoses.isDue(window, latest: slot480.next))
    }
}
