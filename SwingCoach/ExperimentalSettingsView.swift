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
    static let backendTarget = "experimental.backendTarget"
    static let customBackendURL = "experimental.customBackendURL"
    static let useMockAnalysis = "experimental.useMockAnalysis"
    static let showDebugReplayTab = "experimental.showDebugReplayTab"
    static let debugReplaySpeedMultiplier = "experimental.debugReplaySpeedMultiplier"
    static let debugReplaySourceTiming = "experimental.debugReplaySourceTiming"
    static let detectorDefaultsRevision = "experimental.detectorDefaultsRevision"
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
    @AppStorage(ExperimentalSettingKey.liveAutoSwingDetectionEnabled) private var liveAutoSwingDetectionEnabled = true
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 8.0
    @AppStorage(ExperimentalSettingKey.backendTarget) private var backendTargetRaw = BackendTarget.local.rawValue
    @AppStorage(ExperimentalSettingKey.customBackendURL) private var customBackendURL = ""
    @AppStorage(ExperimentalSettingKey.useMockAnalysis) private var useMockAnalysis = false
    @AppStorage(ExperimentalSettingKey.showDebugReplayTab) private var showDebugReplayTab = true

    private let detectorSampleOptions = [2.0, 4.0, 8.0, 16.0]

    var body: some View {
        List {
            Section {
                Toggle("Model swing detection", isOn: $liveAutoSwingDetectionEnabled)

                Picker("Detector sample rate", selection: $liveModelDetectorSampleFPS) {
                    ForEach(detectorSampleOptions, id: \.self) { sampleFPS in
                        Text("\(Int(sampleFPS)) fps").tag(sampleFPS)
                    }
                }

            } footer: {
                Text("Capture and Replay Debug use SwingDetectorV2. The sample rate controls idle/address sampling; V2 raises its rate during startup and active swing evidence.")
            }

            #if DEBUG
            Section {
                Picker("Backend target", selection: $backendTargetRaw) {
                    ForEach(BackendTarget.allCases, id: \.rawValue) { target in
                        Text(target.label).tag(target.rawValue)
                    }
                }

                if backendTargetRaw == BackendTarget.custom.rawValue {
                    TextField("Backend URL", text: $customBackendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Toggle("Mock analysis", isOn: $useMockAnalysis)
            } footer: {
                Text("Current backend: \(SwingCoachAPI.baseURL). Mock analysis calls /mock/analyze; real analysis calls /analyze.")
            }
            #endif

            Section {
                Toggle("Replay Debug tab", isOn: $showDebugReplayTab)
            } footer: {
                Text("Shows the DEBUG-only video replay tool used to test auto swing detection with saved footage.")
            }
        }
        .navigationTitle("Experiments")
        .onAppear { ExperimentalDetectorDefaults.migrateIfNeeded() }
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
