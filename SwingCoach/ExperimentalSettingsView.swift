//
//  ExperimentalSettingsView.swift
//  SwingCoach
//
//  Created by Codex on 22/05/2026.
//

import Foundation
import SwiftUI

enum ExperimentalSettingKey {
    static let liveAutoSwingDetectionEnabled = "experimental.liveAutoSwingDetectionEnabled"
    static let liveModelDetectorSampleFPS = "experimental.liveModelDetectorSampleFPS"
    static let capturePracticeSwings = "capture.capturePracticeSwings"
    static let showCaptureModelStats = "experimental.showCaptureModelStats"
    static let showDebugReplayTab = "experimental.showDebugReplayTab"
    static let debugReplaySpeedMultiplier = "experimental.debugReplaySpeedMultiplier"
    static let debugReplaySourceTiming = "experimental.debugReplaySourceTiming"
    static let debugReplayPracticeSwings = "experimental.debugReplayPracticeSwings"
    static let detectorDefaultsRevision = "experimental.detectorDefaultsRevision"
    static let keepAutoRecordings = "experimental.keepAutoRecordings"
    static let coachDuringAuto = "coaching.coachDuringAuto"
}

enum ExperimentalDetectorDefaults {
    private static let currentRevision = 2
    private static let defaultLiveModelDetectorSampleFPS = 8.0

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: ExperimentalSettingKey.detectorDefaultsRevision) < currentRevision else {
            return
        }

        let storedSampleFPS = defaults.object(forKey: ExperimentalSettingKey.liveModelDetectorSampleFPS) as? NSNumber
        if storedSampleFPS == nil || storedSampleFPS?.doubleValue == 16.0 {
            defaults.set(defaultLiveModelDetectorSampleFPS, forKey: ExperimentalSettingKey.liveModelDetectorSampleFPS)
        }

        defaults.set(currentRevision, forKey: ExperimentalSettingKey.detectorDefaultsRevision)
    }
}

struct ExperimentalSettingsView: View {
    @AppStorage(SwingClipContext.beforeKey) private var extraSecondsBefore = 0.0
    @AppStorage(SwingClipContext.afterKey) private var extraSecondsAfter = 0.0
    @AppStorage(ClipStoragePreference.saveToPhotosKey) private var saveToPhotos = true
    @AppStorage(ExperimentalSettingKey.liveAutoSwingDetectionEnabled) private var liveAutoSwingDetectionEnabled = true
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 8.0
    @AppStorage(ExperimentalSettingKey.capturePracticeSwings) private var capturePracticeSwings = false
    @AppStorage(CaptureSoundPreference.recordsSoundKey) private var recordsSound = false
    @AppStorage(ExperimentalSettingKey.showCaptureModelStats) private var showCaptureModelStats = false
    @AppStorage(ExperimentalSettingKey.showDebugReplayTab) private var showDebugReplayTab = true
    @AppStorage(ExperimentalSettingKey.coachDuringAuto) private var coachDuringAuto = false
    @AppStorage(CoachingCadence.key) private var coachingCadence = CoachingCadence.standard.rawValue
    #if DEBUG
    @AppStorage(ExperimentalSettingKey.keepAutoRecordings) private var keepAutoRecordings = false
    #endif

    private let detectorSampleOptions = [2.0, 4.0, 8.0, 16.0]

    private func clipContextControl(_ title: String, value: Binding<Double>, identifier: String) -> some View {
        let boundedValue = Binding(
            get: { SwingClipContext.validSeconds(value.wrappedValue) },
            set: { value.wrappedValue = SwingClipContext.validSeconds($0) }
        )
        return HStack {
            Text(title)
            Spacer()
            TextField("Seconds", value: boundedValue, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 55)
                .accessibilityLabel(title + " seconds")
                .accessibilityIdentifier(identifier)
            Text("s").foregroundStyle(Color.helpText)
            Stepper(title, value: boundedValue, in: 0...SwingClipContext.maximumSeconds, step: 0.5)
                .labelsHidden()
                .accessibilityIdentifier(identifier + "-stepper")
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Save to Photos", isOn: $saveToPhotos)
                    .accessibilityIdentifier("save-to-photos")
            } header: {
                SectionHeading("Video storage")
            } footer: {
                HelpFooter("Also saves new clips (Auto, Manual, Trim) to Photos.",
                           "When off, clips stay in SwingCoach's library and review. Existing videos are unchanged.")
            }

            Section {
                clipContextControl("Before swing", value: $extraSecondsBefore, identifier: "swing-context-before")
                clipContextControl("After swing", value: $extraSecondsAfter, identifier: "swing-context-after")
            } header: {
                SectionHeading("Extra swing footage")
            } footer: {
                HelpFooter("Add 0–30 s before or after the swing; +/− is 0.5 s.",
                           "Real seconds, before slow-motion export, in Auto and Manual/Trim. Auto waits for the extra footage; stopping early saves what was recorded. New clips only.")
            }

            Section {
                Toggle("Record sound", isOn: $recordsSound)
                    .accessibilityIdentifier("record-sound")
            } header: {
                SectionHeading("Sound")
            } footer: {
                HelpFooter("When on, Manual recordings include microphone sound.",
                           "Off by default. Auto clips never have sound. Clips play alongside your music either way.")
            }

            Section {
                Toggle("Capture practice swings", isOn: $capturePracticeSwings)
            } header: {
                SectionHeading("Auto & Manual Capture")
            } footer: {
                HelpFooter("Off by default: only real shots are detected.",
                           "Turn this on to include practice swings in Auto capture and in Manual recording's detected trim ranges. Replay Debug has its own option under Advanced.")
            }

            Section {
                Picker("Coach speaks in Auto", selection: $coachingCadence) {
                    ForEach(CoachingCadence.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .accessibilityIdentifier("coach-cadence-setting")
                Toggle("Measure swings while Auto records", isOn: $coachDuringAuto)
                    .accessibilityIdentifier("coach-during-auto-toggle")
            } header: {
                SectionHeading("Coaching")
            } footer: {
                HelpFooter("Every down-the-line swing is measured on the phone when Auto pauses or stops, so the coach is quiet while you hit.",
                           "Measuring while Auto records gives a first reading of each swing as it is saved: body checks only, the clip fills in the rest later.",
                           "Off by default: it has not been checked on a phone for dropped frames or heat.")
            }

            Section {
                Toggle("Model swing detection", isOn: $liveAutoSwingDetectionEnabled)

                Picker("Detector sample rate", selection: $liveModelDetectorSampleFPS) {
                    ForEach(detectorSampleOptions, id: \.self) { sampleFPS in
                        Text("\(Int(sampleFPS)) fps").tag(sampleFPS)
                    }
                }

            } footer: {
                HelpFooter("Capture, Trim, and Replay Debug use SwingDetectorV3.",
                           "The sample rate controls idle/address sampling; V3 raises its rate during an active swing episode.")
            }

            Section {
                Toggle("Show model stats", isOn: $showCaptureModelStats)
                    .accessibilityIdentifier("show-capture-model-stats")
            } header: {
                SectionHeading("Capture diagnostics")
            } footer: {
                HelpFooter("Shows measured detector FPS and average model processing time under the capture status in Auto and Manual.",
                           "Off by default; this does not change detection or recording.")
            }

            #if DEBUG
            Section {
                Toggle("Keep Auto recordings", isOn: $keepAutoRecordings)
                    .accessibilityIdentifier("keep-auto-recordings")
            } footer: {
                HelpFooter("Keeps everything Auto records in Documents/KeptRecordings instead of deleting it after 45 s, a new folder each time Auto starts or resumes.",
                           "About 22 GB an hour at 240 fps. Play a folder back with the -footage-camera launch option. Starts with the next Auto session.")
            }
            #endif

            Section {
                Toggle("Replay Debug tab", isOn: $showDebugReplayTab)
            } footer: {
                HelpFooter("Shows the DEBUG-only video replay tool used to test auto swing detection with saved footage.")
            }
        }
        .navigationTitle("Settings")
        // Sheets don't reliably inherit the app's tint; toggles need it set.
        .tint(.appAccent)
        .onAppear { ExperimentalDetectorDefaults.migrateIfNeeded() }
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
