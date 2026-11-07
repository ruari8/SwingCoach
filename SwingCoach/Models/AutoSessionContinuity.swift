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
