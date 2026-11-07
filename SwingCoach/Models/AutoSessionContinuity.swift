import Foundation

/// When Auto starts again, whether it continues the previous review session.
/// A range visit is one session: leaving Capture for Library or another app
/// keeps it, and 30 minutes without a new swing starts a fresh one. A relaunch
/// always starts fresh because the session lives in memory.
nonisolated enum AutoSessionContinuity {
    static let idleLimit: TimeInterval = 30 * 60

    static func continues(lastActivity: Date?, now: Date) -> Bool {
        guard let lastActivity else { return false }
        let idle = now.timeIntervalSince(lastActivity)
        return idle >= 0 && idle < idleLimit
    }
}

/// The session's idle clock. Starting a session, accepting a swing and saving
/// one all count as activity; acceptance counts so a swing still collecting
/// its after-swing footage keeps the session alive.
nonisolated struct AutoSessionActivity {
    private(set) var last: Date?

    func continuesSession(at now: Date) -> Bool {
        AutoSessionContinuity.continues(lastActivity: last, now: now)
    }

    mutating func sessionStarted(at now: Date) { last = now }

    /// Returns true when this swing comes after the idle limit and so opens a
    /// fresh review.
    mutating func swingAccepted(at now: Date) -> Bool {
        let opensFreshReview = !continuesSession(at: now)
        last = now
        return opensFreshReview
    }

    mutating func swingSaved(at now: Date) { last = now }
}
