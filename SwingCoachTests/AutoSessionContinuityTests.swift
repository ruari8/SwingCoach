import XCTest
@testable import SwingCoach

final class AutoSessionContinuityTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testFirstStartIsANewSession() {
        XCTAssertFalse(AutoSessionContinuity.continues(lastActivity: nil, now: start))
    }

    func testReturningWithinThirtyMinutesContinues() {
        XCTAssertTrue(AutoSessionContinuity.continues(lastActivity: start, now: start.addingTimeInterval(5)))
        XCTAssertTrue(AutoSessionContinuity.continues(lastActivity: start, now: start.addingTimeInterval(29 * 60 + 59)))
    }

    func testThirtyMinutesIdleStartsANewSession() {
        XCTAssertFalse(AutoSessionContinuity.continues(lastActivity: start, now: start.addingTimeInterval(30 * 60)))
        XCTAssertFalse(AutoSessionContinuity.continues(lastActivity: start, now: start.addingTimeInterval(3 * 3600)))
    }

    func testClockGoingBackwardsStartsANewSession() {
        XCTAssertFalse(AutoSessionContinuity.continues(lastActivity: start, now: start.addingTimeInterval(-60)))
    }
}
