//
//  CoachingLiveJoin.swift
//  SwingCoach
//
//  Joins a swing's live reading to the swing once it is saved. The two
//  happen on different queues and either can come first, and either can
//  fail: the clip may not save, the reading may not be made. Each side
//  reports exactly once per request, and the request is forgotten as soon
//  as both have.
//

import Foundation

nonisolated struct CoachingLiveJoin<Reading> {
    /// The saved swing, and the mapping from the recording's timeline onto
    /// its clip: (time - offset) * scale.
    struct Owner: Equatable {
        let swing: UUID
        let offset: Double
        let scale: Double
    }

    private var swings: [UUID: Owner?] = [:]
    private var readings: [UUID: Reading?] = [:]

    /// Requests still waiting for their other side.
    var waiting: Int { swings.count + readings.count }

    /// The capture side: the request's swing was saved as `owner`, or
    /// (nil) was not saved. Returns the reading to keep, if it is here.
    mutating func swing(_ token: UUID, _ owner: Owner?) -> (reading: Reading, owner: Owner)? {
        guard let reading = readings.removeValue(forKey: token) else {
            swings[token] = .some(owner)
            return nil
        }
        guard let reading, let owner else { return nil }
        return (reading, owner)
    }

    /// The reading side: the request's reading was made, or (nil) never
    /// will be. Returns the swing to keep it on, if that is known.
    mutating func reading(_ token: UUID, _ reading: Reading?) -> (reading: Reading, owner: Owner)? {
        guard let owner = swings.removeValue(forKey: token) else {
            readings[token] = .some(reading)
            return nil
        }
        guard let reading, let owner else { return nil }
        return (reading, owner)
    }

    /// True when the request's swing is known not to have been saved, so
    /// making its reading would be wasted work.
    func isUnwanted(_ token: UUID) -> Bool {
        if case .some(.none) = swings[token] { return true }
        return false
    }

    /// Deleted swings keep no reading that arrives later.
    mutating func forget(swings ids: Set<UUID>) {
        for (token, owner) in swings {
            if let owner, ids.contains(owner.swing) { swings[token] = .some(nil) }
        }
    }
}
