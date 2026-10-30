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
}
