import AVFoundation

/// Owns the shared audio session only while a Manual movie uses the microphone.
/// CameraSession serializes access on its session queue. Release runs after the
/// microphone is detached and before the movie is published to Trim.
nonisolated protocol CaptureAudioSession: AnyObject {
    var category: AVAudioSession.Category { get }
    var mode: AVAudioSession.Mode { get }
    var categoryOptions: AVAudioSession.CategoryOptions { get }
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

nonisolated extension AVAudioSession: CaptureAudioSession {}

nonisolated final class CaptureRecordingAudioSession {
    private struct Configuration {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private let audio: CaptureAudioSession
    private var previous: Configuration?

    init(audio: CaptureAudioSession = AVAudioSession.sharedInstance()) {
        self.audio = audio
    }

    func begin() throws {
        // Retry any cleanup that failed at the end of the previous recording.
        try end()
        let configuration = Configuration(category: audio.category, mode: audio.mode, options: audio.categoryOptions)
        try audio.setCategory(.playAndRecord, mode: .videoRecording,
                              options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
        previous = configuration
        try audio.setActive(true, options: [])
    }

    /// Detach the microphone before calling this, including on recording errors.
    /// A failed release retains the configuration so the next call can retry it.
    func end() throws {
        guard let previous else { return }
        try audio.setActive(false, options: .notifyOthersOnDeactivation)
        try audio.setCategory(previous.category, mode: previous.mode, options: previous.options)
        self.previous = nil
    }
}
