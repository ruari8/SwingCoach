//
//  SwingCoachApp.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

@main
struct SwingCoachApp: App {
    #if DEBUG
    init() {
        UITestFixture.prepareLaunch()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
