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
    static let hybridImpactConfirmationPostRoll = "experimental.hybridImpactConfirmationPostRoll"
    static let liveCaptureDetectionMode = "experimental.liveCaptureDetectionMode"
    static let showDebugReplayTab = "experimental.showDebugReplayTab"
    static let debugReplaySpeedMultiplier = "experimental.debugReplaySpeedMultiplier"
    static let debugReplaySourceTiming = "experimental.debugReplaySourceTiming"
    static let debugReplayDetectionMode = "experimental.debugReplayDetectionMode"
    static let detectorDefaultsRevision = "experimental.detectorDefaultsRevision"
}

enum LiveCaptureDetectionMode: String, CaseIterable {
    case contact
    case impact
    case hybrid

    var label: String {
        switch self {
        case .contact: "Contact"
        case .impact: "Impact"
        case .hybrid: "Hybrid"
        }
    }

    var detail: String {
        switch self {
        case .contact:
            return "Strict model/contact validation. Lower recall, fewer false positives."
        case .impact:
            return "Experimental fixed-window impact detector. Higher recall, noisier."
        case .hybrid:
            return "Experimental impact detector with sparse Apple Vision pose gating. Best current V2 result, but heavier."
        }
    }
}

enum ExperimentalDetectorDefaults {
    private static let currentRevision = 1
    private static let debugReplayHybridModeRaw = "hybridImpact"
    private static let debugReplayContactModeRaw = "contact"

    static func migrateIfNeeded() -> (captureModeRaw: String?, debugReplayModeRaw: String?) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: ExperimentalSettingKey.detectorDefaultsRevision) < currentRevision else {
            return (nil, nil)
        }

        var captureModeRaw: String?
        let storedCaptureMode = defaults.string(forKey: ExperimentalSettingKey.liveCaptureDetectionMode)
        if storedCaptureMode == nil || storedCaptureMode == LiveCaptureDetectionMode.contact.rawValue {
            let migratedCaptureMode = LiveCaptureDetectionMode.hybrid.rawValue
            captureModeRaw = migratedCaptureMode
            defaults.set(migratedCaptureMode, forKey: ExperimentalSettingKey.liveCaptureDetectionMode)
        }

        var debugReplayModeRaw: String?
        let storedDebugReplayMode = defaults.string(forKey: ExperimentalSettingKey.debugReplayDetectionMode)
        if storedDebugReplayMode == nil || storedDebugReplayMode == debugReplayContactModeRaw {
            debugReplayModeRaw = debugReplayHybridModeRaw
            defaults.set(debugReplayHybridModeRaw, forKey: ExperimentalSettingKey.debugReplayDetectionMode)
        }

        defaults.set(currentRevision, forKey: ExperimentalSettingKey.detectorDefaultsRevision)
        return (captureModeRaw, debugReplayModeRaw)
    }
}

struct ExperimentalSettingsView: View {
    @AppStorage(ExperimentalSettingKey.liveAutoSwingDetectionEnabled) private var liveAutoSwingDetectionEnabled = true
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 16.0
    @AppStorage(ExperimentalSettingKey.hybridImpactConfirmationPostRoll) private var hybridImpactConfirmationPostRoll = 0.20
    @AppStorage(ExperimentalSettingKey.liveCaptureDetectionMode) private var liveCaptureDetectionModeRaw = LiveCaptureDetectionMode.hybrid.rawValue
    @AppStorage(ExperimentalSettingKey.showDebugReplayTab) private var showDebugReplayTab = true

    private let detectorSampleOptions = [2.0, 4.0, 8.0, 16.0]
    private let confirmationWaitOptions = [0.20, 0.28, 0.35, 0.55]

    private var liveCaptureDetectionMode: LiveCaptureDetectionMode {
        get { LiveCaptureDetectionMode(rawValue: liveCaptureDetectionModeRaw) ?? .hybrid }
        nonmutating set { liveCaptureDetectionModeRaw = newValue.rawValue }
    }

    var body: some View {
        List {
            Section {
                Toggle("Model swing detection", isOn: $liveAutoSwingDetectionEnabled)

                Picker("Capture detector mode", selection: $liveCaptureDetectionModeRaw) {
                    ForEach(LiveCaptureDetectionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }

                Picker("Detector sample rate", selection: $liveModelDetectorSampleFPS) {
                    ForEach(detectorSampleOptions, id: \.self) { sampleFPS in
                        Text("\(Int(sampleFPS)) fps").tag(sampleFPS)
                    }
                }

                Picker("Impact confirm wait", selection: $hybridImpactConfirmationPostRoll) {
                    ForEach(confirmationWaitOptions, id: \.self) { wait in
                        Text(String(format: "%.2fs", wait)).tag(wait)
                    }
                }
            } footer: {
                Text("\(liveCaptureDetectionMode.detail) Capture and Replay Debug sample the YOLO model at this real-time rate. Hybrid impact detection waits this long after estimated impact before declaring a swing.")
            }

            Section {
                Toggle("Replay Debug tab", isOn: $showDebugReplayTab)
            } footer: {
                Text("Shows the DEBUG-only video replay tool used to test auto swing detection with saved footage.")
            }
        }
        .navigationTitle("Experiments")
        .onAppear {
            if let captureModeRaw = ExperimentalDetectorDefaults.migrateIfNeeded().captureModeRaw {
                liveCaptureDetectionModeRaw = captureModeRaw
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
