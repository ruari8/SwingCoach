//
//  ExperimentalSettingsView.swift
//  SwingCoach
//
//  Created by Codex on 22/05/2026.
//

import SwiftUI

enum ExperimentalSettingKey {
    static let liveAutoSwingDetectionEnabled = "experimental.liveAutoSwingDetectionEnabled"
    static let showDebugReplayTab = "experimental.showDebugReplayTab"
    static let debugReplaySpeedMultiplier = "experimental.debugReplaySpeedMultiplier"
}

struct ExperimentalSettingsView: View {
    @AppStorage(ExperimentalSettingKey.liveAutoSwingDetectionEnabled) private var liveAutoSwingDetectionEnabled = true
    @AppStorage(ExperimentalSettingKey.showDebugReplayTab) private var showDebugReplayTab = true
    @AppStorage(ExperimentalSettingKey.debugReplaySpeedMultiplier) private var debugReplaySpeedMultiplier = 8.0

    private let replaySpeedOptions = [1.0, 2.0, 4.0, 8.0]

    var body: some View {
        List {
            Section {
                Toggle("Model swing detection", isOn: $liveAutoSwingDetectionEnabled)
            } footer: {
                Text("Experimental. When off, capture still records normally and trim opens without model-detected swing ranges.")
            }

            Section {
                Toggle("Replay Debug tab", isOn: $showDebugReplayTab)
            } footer: {
                Text("Shows the DEBUG-only video replay tool used to test auto swing detection with saved footage.")
            }

            Section {
                Picker("Replay speed", selection: $debugReplaySpeedMultiplier) {
                    ForEach(replaySpeedOptions, id: \.self) { multiplier in
                        Text("\(Int(multiplier))x").tag(multiplier)
                    }
                }
            } footer: {
                Text("Speeds up long-session review in the DEBUG replay tool. Detector timestamps remain on the selected video's source timeline.")
            }
        }
        .navigationTitle("Experiments")
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
