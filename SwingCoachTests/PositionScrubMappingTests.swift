import XCTest
@testable import SwingCoach

final class PositionScrubMappingTests: XCTestCase {
    private let times = [0.4, 0.9, 1.15, 1.6, 1.85, 1.9, 1.95, 2.05, 2.15, 2.7]

    func testWithoutPositionsTheScrubberIsLinear() {
        let mapping = PositionScrubMapping(duration: 3)
        XCTAssertEqual(mapping.fraction(at: 1.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(mapping.time(at: 0.25), 0.75, accuracy: 1e-9)
    }

    func testShortDownswingStretchesGetMoreRoomThanTimeGivesThem() {
        let mapping = PositionScrubMapping(duration: 3, positionTimes: times)
        // P5 to P7 is 0.1 s, a thirtieth of the clip; it gets far more of the bar.
        let downswing = mapping.fraction(at: 1.95) - mapping.fraction(at: 1.85)
        XCTAssertGreaterThan(downswing, 0.1 / 3 * 2)
        // The long follow-through still gets more room than the short stretches.
        let followThrough = mapping.fraction(at: 2.7) - mapping.fraction(at: 2.15)
        XCTAssertGreaterThan(followThrough, mapping.fraction(at: 1.9) - mapping.fraction(at: 1.85))
        XCTAssertEqual(mapping.fraction(at: 0), 0)
        XCTAssertEqual(mapping.fraction(at: 3), 1)
    }

    func testTimeAndFractionRoundTripAndStayInOrder() {
        let mapping = PositionScrubMapping(duration: 3, positionTimes: times)
        var previous = -1.0
        for step in 0...300 {
            let time = Double(step) / 100
            let fraction = mapping.fraction(at: time)
            XCTAssertGreaterThanOrEqual(fraction, previous)
            XCTAssertEqual(mapping.time(at: fraction), time, accuracy: 1e-9)
            previous = fraction
        }
    }

    func testPositionsSharingAFrameStayApartAndOutOfOrderFallsBackToLinear() {
        let shared = PositionScrubMapping(duration: 3, positionTimes: [0.4, 1.9, 1.9, 2.7])
        XCTAssertGreaterThan(shared.fractions[3], shared.fractions[2])
        XCTAssertEqual(shared.time(at: (shared.fractions[2] + shared.fractions[3]) / 2), 1.9, accuracy: 1e-9)

        let outOfOrder = PositionScrubMapping(duration: 3, positionTimes: [1.0, 0.5])
        XCTAssertEqual(outOfOrder.fractions, [0, 1])
    }
}
