//
//  SwingSession.swift
//  SwingCoach
//

import Foundation

/// A run of personal swings recorded close together, such as one range visit.
/// Library groups and batch-selects swings by session.
struct SwingSession: Identifiable, Equatable {
    /// Newest first, matching the Library grid.
    let swings: [SavedSwing]

    var id: UUID { swings[0].id }
    var start: Date { swings[swings.count - 1].createdAt }
    var end: Date { swings[0].createdAt }

    /// A new session starts after this much time without a swing, or on a new calendar day.
    static let maximumGap: TimeInterval = 30 * 60

    /// Groups swings into sessions, newest session first.
    static func group(_ swings: [SavedSwing], calendar: Calendar = .current) -> [SwingSession] {
        let newestFirst = swings.sorted { $0.createdAt > $1.createdAt }
        var sessions: [[SavedSwing]] = []
        for swing in newestFirst {
            if let previous = sessions.last?.last,
               previous.createdAt.timeIntervalSince(swing.createdAt) <= maximumGap,
               calendar.isDate(previous.createdAt, inSameDayAs: swing.createdAt) {
                sessions[sessions.count - 1].append(swing)
            } else {
                sessions.append([swing])
            }
        }
        return sessions.map(SwingSession.init(swings:))
    }
}

/// Photos-style drag selection: the swing under the finger when the drag starts
/// decides whether the dragged range is added or removed.
struct SwingRangeSelection {
    let orderedIDs: [UUID]
    let anchorIndex: Int
    let initialSelection: Set<UUID>
    let adds: Bool

    init?(orderedIDs: [UUID], anchor: UUID, initialSelection: Set<UUID>) {
        guard let anchorIndex = orderedIDs.firstIndex(of: anchor) else { return nil }
        self.orderedIDs = orderedIDs
        self.anchorIndex = anchorIndex
        self.initialSelection = initialSelection
        self.adds = !initialSelection.contains(anchor)
    }

    /// The selection after dragging from the anchor to `id`. Swings the drag
    /// passed over and then left return to their state before the drag.
    func selection(extendingTo id: UUID) -> Set<UUID> {
        guard let index = orderedIDs.firstIndex(of: id) else { return initialSelection }
        let range = Set(orderedIDs[min(anchorIndex, index)...max(anchorIndex, index)])
        return adds ? initialSelection.union(range) : initialSelection.subtracting(range)
    }
}
