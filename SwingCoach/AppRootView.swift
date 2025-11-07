//
//  AppRootView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

struct AppRootView: View {
    @State private var selection: Tab = .capture
    
    var body: some View {
        TabView(selection: $selection) {
            LibraryView(onNavigateToCapture: {
                selection = .capture
            })
            .tabItem{Label("Library", systemImage: "film")}
            .tag(Tab.library)
            
            CaptureView()
            .tabItem{Label("Capture", systemImage: "camera")}
            .tag(Tab.capture)
        }
    }
}

enum Tab: Hashable {
    case library
    case capture
}

#Preview {
    AppRootView()
}
