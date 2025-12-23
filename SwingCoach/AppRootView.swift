//
//  AppRootView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

struct AppRootView: View {
    @State private var selection: Tab = .capture
    
    // Shared state for analysis - set by Library or TrimView, consumed by AnalyseView
    @State private var swingsToAnalyze: [SavedSwing] = []
    
    var body: some View {
        TabView(selection: $selection) {
            LibraryView(
                onNavigateToCapture: {
                    selection = .capture
                },
                onAnalyzeSwings: { swings in
                    swingsToAnalyze = swings
                    selection = .analyse
                }
            )
            .tabItem { Label("Library", systemImage: "film") }
            .tag(Tab.library)
            
            CaptureView(onAnalyzeSwings: { swings in
                swingsToAnalyze = swings
                selection = .analyse
            })
            .tabItem { Label("Capture", systemImage: "camera") }
            .tag(Tab.capture)
            
            AnalyseView(
                swingsToAnalyze: $swingsToAnalyze,
                onNavigateToLibrary: {
                    selection = .library
                }
            )
            .tabItem { Label("Coach", systemImage: "wand.and.stars") }
            .tag(Tab.analyse)
        }
    }
}

enum Tab: Hashable {
    case library
    case capture
    case analyse
}

#Preview {
    AppRootView()
}
