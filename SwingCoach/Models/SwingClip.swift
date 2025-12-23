//
//  SwingClip.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import Foundation
import AVFoundation
import UIKit

/// Camera angle for the swing recording
enum Vantage: String, Codable, CaseIterable {
    case dtl = "DTL"
    case faceOn = "Face-On"
    
    var displayName: String {
        switch self {
        case .dtl: return "Down the Line"
        case .faceOn: return "Face-On"
        }
    }
    
    var shortName: String {
        rawValue
    }
}

/// Represents a single swing clip extracted from a longer video
struct SwingClip: Identifiable, Codable {
    let id: UUID
    var startTime: Double  // Seconds (CMTime doesn't conform to Codable)
    var endTime: Double
    var vantage: Vantage
    var notes: String?
    var createdAt: Date
    
    // Not persisted - loaded at runtime
    var thumbnail: UIImage?
    
    init(
        id: UUID = UUID(),
        startTime: CMTime,
        endTime: CMTime,
        vantage: Vantage = .dtl,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startTime = CMTimeGetSeconds(startTime)
        self.endTime = CMTimeGetSeconds(endTime)
        self.vantage = vantage
        self.notes = notes
        self.createdAt = createdAt
    }
    
    var startCMTime: CMTime {
        CMTime(seconds: startTime, preferredTimescale: 600)
    }
    
    var endCMTime: CMTime {
        CMTime(seconds: endTime, preferredTimescale: 600)
    }
    
    var duration: Double {
        endTime - startTime
    }
    
    var durationFormatted: String {
        let seconds = Int(duration)
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return "\(seconds).\(tenths)s"
    }
    
    // Codable conformance (exclude thumbnail)
    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, vantage, notes, createdAt
    }
}

/// Represents a trimming session - the source video and clips extracted from it
struct TrimSession {
    let sourceURL: URL
    let asset: AVAsset
    var clips: [SwingClip]
    var defaultVantage: Vantage
    
    init(sourceURL: URL, defaultVantage: Vantage = .dtl) {
        self.sourceURL = sourceURL
        self.asset = AVURLAsset(url: sourceURL)
        self.clips = []
        self.defaultVantage = defaultVantage
    }
}


