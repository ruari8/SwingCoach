//
//  SwingCoachApp.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

@main
struct SwingCoachApp: App {
    init() {
        // Before the fixture records the launch audio policy.
        PlaybackAudioSession.configure()
        #if DEBUG
        UITestFixture.prepareLaunch()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
