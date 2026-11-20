//
//  AppRootView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

struct AppRootView: View {
    @State private var selection: Tab
    #if DEBUG
    @AppStorage(ExperimentalSettingKey.showDebugReplayTab) private var showDebugReplayTab = true
    #endif

    init() {
        let initialTab: Tab = ProcessInfo.processInfo.arguments.contains("-ui-testing-library")
            ? .library
            : .capture
        _selection = State(initialValue: initialTab)
    }
    
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-auto-review") {
            AutoReviewFixture()
        } else {
            appTabs
        }
        #else
        appTabs
        #endif
    }

    private var appTabs: some View {
        TabView(selection: $selection) {
            LibraryView(onNavigateToCapture: { selection = .capture })
            .tabItem { Label("Library", systemImage: "film") }
            .tag(Tab.library)
            
            CaptureView()
            .tabItem { Label("Capture", systemImage: "camera") }
            .tag(Tab.capture)
            
            #if DEBUG
            if showDebugReplayTab {
                DebugReplayView()
                    .tabItem { Label("Debug", systemImage: "ladybug") }
                    .tag(Tab.debug)
            }
            #endif
        }
        // One accent for the whole app: tab selection, Select, Done,
        // toggles and links. Lime on dark surfaces, its ink on light ones.
        .tint(.appAccent)
        #if DEBUG
        .onChange(of: showDebugReplayTab) { _, isVisible in
            if !isVisible, selection == .debug {
                selection = .library
            }
        }
        #endif
    }
}

#if DEBUG
/// Exercises the real review UI with local clips, without camera or Photos writes.
private struct AutoReviewFixture: View {
    @State private var swings = SwingLibrary.shared.swings.filter(\.isReference)
    @State private var presentation: AutoSwingReviewPresentation? = AutoSwingReviewPresentation()

    var body: some View {
        VStack {
            Button("Review fixture swings") {
                presentation = AutoSwingReviewPresentation()
            }
            Button("Append fixture swing") {
                guard let source = swings.last else { return }
                swings.append(SavedSwing(
                    id: UUID(), photoAssetID: "", vantage: source.vantage,
                    duration: source.duration, createdAt: Date(), notes: nil, isReference: true, title: "New fixture swing",
                    localVideoFilename: source.localVideoFilename
                ))
            }
        }
        .fullScreenCover(item: $presentation) { _ in
            AutoReviewFixtureSession(swings: $swings)
        }
    }
}

private struct AutoReviewFixtureSession: View {
    @Binding var swings: [SavedSwing]

    var body: some View {
        AutoSwingReviewView(swings: swings) { swing in
            swings.removeAll { $0.id == swing.id }
        }
    }
}
#endif

enum Tab: Hashable {
    case library
    case capture
    #if DEBUG
    case debug
    #endif
}

#Preview {
    AppRootView()
}
