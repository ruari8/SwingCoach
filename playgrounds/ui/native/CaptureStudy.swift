import SwiftUI
import UIKit

// Persistent UI playground; layout variants are experimental. No camera, Photos access, detector, or app data.
private enum LayoutChoice: Int, CaseIterable, Identifiable {
    case quiet = 1, reachable = 5
    var id: Int { rawValue }
    var title: String { self == .quiet ? "01 · Quiet camera" : "05 · Within reach" }
}
private enum Mode: String, CaseIterable { case auto = "Auto", manual = "Manual" }
private enum AppTab: Hashable { case library, capture, coach, debug }

@main
struct CaptureStudyApp: App {
    var body: some Scene { WindowGroup { StudyRoot().preferredColorScheme(.dark) } }
}

private struct StudyRoot: View {
    @State private var tab = AppTab.capture
    @State private var layout = LayoutChoice.quiet
    @State private var mode = Mode.auto
    @State private var sampleSwings = SavedSwing.samples()
    private var saved: Int { sampleSwings.count }
    @State private var fps = 240
    @State private var recordingStart: Date?
    @State private var review = false
    @State private var trim = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                List {
                    Section("Prototype") {
                        Text("The Library screen is outside this camera study.").foregroundStyle(.secondary)
                        Button("Return to camera") { tab = .capture }
                    }
                }.navigationTitle("Library")
            }.tabItem { Label("Library", systemImage: "film") }.tag(AppTab.library)

            camera.tabItem { Label("Capture", systemImage: "camera") }.tag(AppTab.capture)

            NavigationStack {
                List {
                    Text("The Coach screen is outside this camera study.").foregroundStyle(.secondary)
                    Button("Return to camera") { tab = .capture }
                }.navigationTitle("Coach")
            }.tabItem { Label("Coach", systemImage: "wand.and.stars") }.tag(AppTab.coach)

            settings.tabItem { Label("Debug", systemImage: "ladybug") }.tag(AppTab.debug)
        }
        .tint(.blue)
        .fullScreenCover(isPresented: $review) { StudyReview(swings: $sampleSwings) }
        .sheet(isPresented: $trim) {
            NavigationStack {
                VStack(spacing: 18) {
                    Image(systemName: "scissors").font(.largeTitle)
                    Text("Recording stopped").font(.title2.weight(.semibold))
                    Text("In SwingCoach, this opens Trim. This prototype only explores the camera controls.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Back to camera") { trim = false }.buttonStyle(.glassProminent)
                }.padding(30).navigationTitle("Prototype").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium])
        }
        .onOpenURL { url in
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.host == "design", let value = Int(url.lastPathComponent), let choice = LayoutChoice(rawValue: value) {
                layout = choice
                mode = parts?.queryItems?.first(where: { $0.name == "mode" })?.value == "manual" ? .manual : .auto
                recordingStart = mode == .manual ? Date().addingTimeInterval(-5) : nil
                tab = .capture
                review = false
                trim = false
            }
        }
    }

    private var camera: some View {
        ZStack {
            GeometryReader { proxy in
                Group {
                    if let image = Self.cameraImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color(white: 0.12)
                    }
                }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }.ignoresSafeArea()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.52), location: 0),
                .init(color: .clear, location: 0.27),
                .init(color: .clear, location: 0.64),
                .init(color: .black.opacity(0.70), location: 1)
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack(spacing: 0) {
                if layout == .quiet {
                    Group {
                        if recordingStart != nil {
                            timer.frame(maxWidth: .infinity).frame(height: 44)
                        } else {
                            HStack {
                                frameRate
                                Spacer()
                                modePicker
                            }.frame(height: 44)
                        }
                    }
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.2), value: recordingStart != nil)
                    Spacer()
                    if mode == .auto {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 6) {
                                autoStatus
                                Text("Swings save automatically")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
                            }
                            Spacer(minLength: 12)
                            savedShortcut
                        }
                        .padding(.bottom, 22)
                    } else {
                        ZStack(alignment: .leading) {
                            if recordingStart != nil { detectionStatus }
                            recordControl.frame(maxWidth: .infinity)
                        }.padding(.bottom, 20)
                    }
                } else {
                    HStack {
                        if mode == .auto { autoStatus }
                        else if recordingStart != nil { timer }
                        else { Text("Manual").font(.subheadline.weight(.medium)) }
                        Spacer()
                        frameRate
                    }.padding(.top, 8)
                    Spacer()
                    VStack(spacing: 19) {
                        if mode == .auto {
                            Button { review = true } label: {
                                HStack(spacing: 9) {
                                    Text("\(saved) saved").fontWeight(.medium)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }.font(.subheadline).padding(.horizontal, 7).padding(.vertical, 5)
                            }
                            .buttonStyle(.glass).tint(.white)
                            .accessibilityLabel("Review \(saved) saved swings")
                        } else { recordControl }
                        modePicker
                    }.padding(.bottom, 22)
                }
            }
            .padding(.horizontal, 22)
            .foregroundStyle(.white)
        }
    }

    private var modePicker: some View {
        Picker("Capture mode", selection: $mode) {
            Text("Auto").tag(Mode.auto)
            Text("Manual").tag(Mode.manual)
        }
        .pickerStyle(.segmented)
        .frame(width: 172)
        .disabled(recordingStart != nil)
        .accessibilityIdentifier("captureMode")
    }

    private var frameRate: some View {
        Menu {
            Picker("Frame rate", selection: $fps) {
                ForEach([30, 60, 120, 240], id: \.self) { rate in Text("\(rate) fps").tag(rate) }
            }
        } label: {
            HStack(spacing: 5) {
                Text("\(fps) fps").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.frame(minHeight: 44)
        }
        .disabled(recordingStart != nil)
        .accessibilityLabel("Frame rate, \(fps) frames per second")
    }

    private var autoStatus: some View {
        HStack(spacing: 7) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("Auto is on").font(.subheadline.weight(.medium))
        }.accessibilityElement(children: .combine)
    }

    private var savedShortcut: some View {
        Button { review = true } label: {
            HStack(spacing: 9) {
                Group {
                    if let image = Self.cameraImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else { Color(white: 0.2) }
                }
                    .frame(width: 32, height: 42).clipShape(.rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(saved) saved").font(.subheadline.weight(.medium))
                    Text("This session").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("Review \(saved) saved swings")
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(recordingStart ?? context.date))
            HStack(spacing: 7) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(String(format: "%02d:%04.1f", Int(elapsed) / 60, elapsed.truncatingRemainder(dividingBy: 60)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }.accessibilityLabel("Recording")
    }

    private var recordControl: some View {
        Button {
            if recordingStart == nil { recordingStart = Date() }
            else { recordingStart = nil; trim = true }
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 76, height: 76)
                if recordingStart == nil { Circle().fill(.red).frame(width: 62, height: 62) }
                else { RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 29, height: 29) }
            }.contentShape(Circle())
        }.buttonStyle(.plain)
        .accessibilityLabel(recordingStart == nil ? "Start recording" : "Stop recording")
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LayoutChoice.allCases) { choice in
                        Button {
                            layout = choice
                            tab = .capture
                        } label: {
                            HStack {
                                Text(choice.title).foregroundStyle(.primary)
                                Spacer()
                                if layout == choice { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: { Text("Choose a design") }
                  footer: { Text("Both use Apple's native tab bar and Auto / Manual selector. Selecting a design returns to the camera.") }
                Section("Try the states") {
                    Button("Auto · 3 saved swings") {
                        sampleSwings = SavedSwing.samples(); mode = .auto; recordingStart = nil; tab = .capture
                    }
                    Button("Manual · ready to record") {
                        mode = .manual; recordingStart = nil; tab = .capture
                    }
                    Button("Manual · recording") {
                        mode = .manual; recordingStart = Date().addingTimeInterval(-5); tab = .capture
                    }
                    Button("Simulate a saved swing") {
                        sampleSwings.append(SavedSwing.sample(number: saved + 1)); mode = .auto; recordingStart = nil; tab = .capture
                    }
                }
                Section {
                    Text("Camera and detection states are simulated. Saved swings use local sample videos with the app’s shared player. Deleting a sample only removes it from this prototype session.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Design study")
        }
    }

    private var detectionStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(recordingStart ?? context.date)
            let count = max(0, Int((elapsed + 4) / 8))
            VStack(alignment: .leading, spacing: 5) {
                Text("Detecting swings").font(.subheadline.weight(.medium))
                Text(count == 0 ? "No swings yet" : "\(count) detected")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }.allowsHitTesting(false)
    }

    private static let cameraImage = Bundle.main.path(forResource: "camera", ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }
}
