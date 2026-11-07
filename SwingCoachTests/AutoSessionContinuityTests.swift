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

    func testAcceptedSwingStillCollectingFootageKeepsTheSessionAlive() {
        var activity = AutoSessionActivity()
        activity.sessionStarted(at: start)
        activity.swingSaved(at: start)                                              // A saved at 0
        XCTAssertFalse(activity.swingAccepted(at: start.addingTimeInterval(29 * 60 + 50)))  // B accepted
        XCTAssertFalse(activity.swingAccepted(at: start.addingTimeInterval(30 * 60 + 5)),   // C, B still exporting
                       "B's acceptance 15 s earlier must keep the session")
        XCTAssertTrue(activity.continuesSession(at: start.addingTimeInterval(59 * 60)))
    }

    func testSwingAfterThirtyIdleMinutesOpensAFreshReview() {
        var activity = AutoSessionActivity()
        activity.sessionStarted(at: start)
        activity.swingSaved(at: start)
        XCTAssertTrue(activity.swingAccepted(at: start.addingTimeInterval(30 * 60)))
        XCTAssertFalse(activity.swingAccepted(at: start.addingTimeInterval(31 * 60)), "Then it continues")
    }
}
