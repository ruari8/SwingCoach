import XCTest
@testable import SwingCoach

final class LiveSwingPosesTests: XCTestCase {
    private let slot = 1.0 / 30

    /// Copy times every slot from `start`, inside `window`.
    private func grid(from start: Double, in window: ClosedRange<Double>) -> [Double] {
        stride(from: start, to: window.upperBound, by: slot).filter { window.contains($0) }
    }

    func testFullWindowIsCovered() {
        let window = 10.0...12.4
        for phase in [0.0, 0.004, 0.0167, 0.029] {
            XCTAssertTrue(LiveSwingPoses.coversWindow(grid(from: 10 + phase, in: window), window: window),
                          "phase \(phase)")
        }
    }

    func testMissingEdgeCopiesFail() {
        let window = 10.0...12.4
        for phase in [0.0, 0.0083, 0.025] {
            let times = grid(from: 10 + phase, in: window)
            XCTAssertFalse(LiveSwingPoses.coversWindow(Array(times.dropFirst()), window: window), "first, phase \(phase)")
            XCTAssertFalse(LiveSwingPoses.coversWindow(Array(times.dropLast()), window: window), "last, phase \(phase)")
        }
        // Review examples: 71 copies with the first or the last missing.
        XCTAssertFalse(LiveSwingPoses.coversWindow(stride(from: 10.041667, through: 12.375001, by: slot).map { $0 },
                                                   window: window))
        XCTAssertFalse(LiveSwingPoses.coversWindow(stride(from: 10.025, through: 12.358334, by: slot).map { $0 },
                                                   window: window))
    }

    func testMissingMiddleCopyFails() {
        let window = 10.0...12.4
        var times = grid(from: 10.01, in: window)
        times.remove(at: 30)
        XCTAssertFalse(LiveSwingPoses.coversWindow(times, window: window))
    }

    func testTruncatedTailFails() {
        // Contiguous copies through 3.167, then nothing inside the window.
        let window = 1.0...3.4
        XCTAssertFalse(LiveSwingPoses.coversWindow(grid(from: 1.0, in: 1.0...3.2), window: window))
    }
}
