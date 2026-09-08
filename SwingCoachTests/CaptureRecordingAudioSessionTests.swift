import XCTest
import AVFoundation
@testable import SwingCoach

final class CaptureRecordingAudioSessionTests: XCTestCase {
    func testConstructionAndIdleReleaseDoNotTouchAudio() throws {
        let audio = AudioSpy()
        let recording = CaptureRecordingAudioSession(audio: audio)
        try recording.end()
        try recording.end()
        XCTAssertTrue(audio.calls.isEmpty)
    }

    func testRecordingMixesAndRestoresPreviousPlaybackConfiguration() throws {
        let audio = AudioSpy()
        let recording = CaptureRecordingAudioSession(audio: audio)
        for _ in 0..<2 {
            try recording.begin()
            XCTAssertEqual(audio.category, .playAndRecord)
            XCTAssertEqual(audio.mode, .videoRecording)
            XCTAssertEqual(audio.categoryOptions, [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            XCTAssertTrue(audio.active)
            try recording.end()
            XCTAssertEqual(audio.category, .playback)
            XCTAssertEqual(audio.mode, .moviePlayback)
            XCTAssertEqual(audio.categoryOptions, [.mixWithOthers])
            XCTAssertFalse(audio.active)
        }
        XCTAssertEqual(audio.calls, Array(repeating: ["category", "activate", "deactivate-notify", "category"], count: 2).flatMap { $0 })
        try recording.end()
        XCTAssertEqual(audio.calls.count, 8)
    }

    func testActivationFailureCanReleaseAndNextRecordingCanAcquireAudio() throws {
        let audio = AudioSpy()
        let recording = CaptureRecordingAudioSession(audio: audio)
        audio.failActivation = true
        XCTAssertThrowsError(try recording.begin())
        try recording.end()
        XCTAssertEqual(audio.category, .playback)
        XCTAssertFalse(audio.active)
        audio.failActivation = false
        try recording.begin()
        XCTAssertTrue(audio.active)
        try recording.end()
    }

    func testConfigurationFailureDoesNotDeactivateAnotherAudioOwner() throws {
        let audio = AudioSpy()
        let recording = CaptureRecordingAudioSession(audio: audio)
        audio.failConfiguration = true
        XCTAssertThrowsError(try recording.begin())
        try recording.end()
        XCTAssertEqual(audio.calls, ["category"])
    }

    func testFailedReleaseCanBeRetried() throws {
        let audio = AudioSpy()
        let recording = CaptureRecordingAudioSession(audio: audio)
        try recording.begin()
        audio.failDeactivation = true
        XCTAssertThrowsError(try recording.end())
        audio.failDeactivation = false
        try recording.end()
        XCTAssertEqual(audio.category, .playback)
        XCTAssertFalse(audio.active)
    }
}

private final class AudioSpy: CaptureAudioSession {
    var category: AVAudioSession.Category = .playback
    var mode: AVAudioSession.Mode = .moviePlayback
    var categoryOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    var active = false
    var calls: [String] = []
    var failActivation = false
    var failDeactivation = false
    var failConfiguration = false

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        calls.append("category")
        if failConfiguration { throw Failure.simulated }
        self.category = category
        self.mode = mode
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        calls.append(active ? "activate" : options == .notifyOthersOnDeactivation ? "deactivate-notify" : "deactivate")
        if active && failActivation || !active && failDeactivation { throw Failure.simulated }
        self.active = active
    }

    enum Failure: Error { case simulated }
}
