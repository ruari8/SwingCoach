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
    
    // Shared state for analysis - set by Library or TrimView, consumed by AnalyseView
    @State private var swingsToAnalyze: [SavedSwing] = []

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

            #if DEBUG
            if showDebugReplayTab {
                DebugReplayView()
                    .tabItem { Label("Debug", systemImage: "ladybug") }
                    .tag(Tab.debug)
            }
            #endif
        }
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
                    duration: source.duration, createdAt: Date(), notes: nil,
                    analyzed: false, isReference: true, title: "New fixture swing",
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
    case analyse
    #if DEBUG
    case debug
    #endif
}

#Preview {
    AppRootView()
}
