import AVFoundation

/// The app's resting audio policy: clip playback mixes with other apps, so
/// opening a review never stops the user's music. Without it AVPlayer uses
/// the default solo-ambient category, which interrupts other audio on play.
/// Manual recording borrows the session (`CaptureRecordingAudioSession`)
/// and restores this policy when it is done.
nonisolated enum PlaybackAudioSession {
    static func configure(audio: CaptureAudioSession = AVAudioSession.sharedInstance()) {
        try? audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
    }
}

/// Whether Manual recordings include microphone sound. Off by default; Auto
/// clips never record sound.
enum CaptureSoundPreference {
    static let recordsSoundKey = "capture.recordsSound"

    static var recordsSound: Bool { UserDefaults.standard.bool(forKey: recordsSoundKey) }
}
