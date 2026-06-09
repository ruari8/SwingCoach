//
//  AnalysisResultView.swift
//  SwingCoach
//
//  Shared rendering for completed swing analysis results.
//

import SwiftUI
import AVFoundation

struct AnalysisResultView: View {
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let annotatedVideo = result.annotatedVideo {
                AnnotatedAnalysisVideo(video: annotatedVideo, analysisID: result.analysisID)
            }

            if !result.metrics.isEmpty {
                metricsSection
            }

            coachNotesSection

            if !result.drills.isEmpty {
                drillsSection
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(result.metrics, id: \.key) { metric in
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.name)
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    Text(metric.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var coachNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coach Notes")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(result.summary)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var drillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(result.drills, id: \.title) { drill in
                VStack(alignment: .leading, spacing: 3) {
                    Text(drill.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(drill.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

struct AnnotatedAnalysisVideo: View {
    enum Presentation {
        case card
        case immersive
    }

    private enum ImmersiveRailSide {
        case leading
        case trailing

        var alignment: Alignment {
            switch self {
            case .leading:
                return .leading
            case .trailing:
                return .trailing
            }
        }

        var edgePadding: EdgeInsets {
            switch self {
            case .leading:
                return EdgeInsets(top: 0, leading: 12, bottom: 64, trailing: 0)
            case .trailing:
                return EdgeInsets(top: 0, leading: 0, bottom: 64, trailing: 12)
            }
        }

        var toggleIconName: String {
            switch self {
            case .leading:
                return "arrow.right"
            case .trailing:
                return "arrow.left"
            }
        }

        var toggleAccessibilityLabel: String {
            switch self {
            case .leading:
                return "Move annotation tools to right side"
            case .trailing:
                return "Move annotation tools to left side"
            }
        }
    }

    let video: SavedAnalysisVideo
    let analysisID: String
    let presentation: Presentation

    @ObservedObject private var manualStore = ManualAnnotationStore.shared

    @State private var playerItem: AVPlayerItem?
    @State private var annotationTracks: AnnotationTrackPayload?
    @State private var enabledLayerNames: Set<String> = []
    @State private var errorMessage: String?
    @State private var tracksErrorMessage: String?
    @State private var isManualCanvasEnabled = false
    @State private var selectedManualTool: ManualAnnotationTool = .line
    @State private var selectedManualColor = "#FFD60A"
    @State private var manualAppliesToFullSwing = true
    @State private var manualLabelText = "Checkpoint"
    @State private var draftManualAnnotation: ManualAnnotation?
    @State private var immersiveRailSide: ImmersiveRailSide = .trailing

    init(video: SavedAnalysisVideo, analysisID: String, presentation: Presentation = .card) {
        self.video = video
        self.analysisID = analysisID
        self.presentation = presentation
    }

    var body: some View {
        Group {
            switch presentation {
            case .card:
                VStack(alignment: .leading, spacing: 8) {
                    playerSurface
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !annotationLayerControls.isEmpty {
                        annotationControls
                        manualCanvasControls
                    } else if let tracksErrorMessage {
                        Text(tracksErrorMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            case .immersive:
                ZStack(alignment: immersiveRailSide.alignment) {
                    playerSurface
                        .ignoresSafeArea(edges: .top)

                    if let tracksErrorMessage {
                        VStack {
                            Spacer()
                            Text(tracksErrorMessage)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.black.opacity(0.68)))
                                .padding(.bottom, 102)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }

                    if !annotationLayerControls.isEmpty {
                        immersiveToolRail
                            .padding(immersiveRailSide.edgePadding)
                            .simultaneousGesture(railSideDragGesture)
                    }
                }
            }
        }
        .onAppear {
            prepareArtifacts()
        }
        .onChange(of: video.url) { _, _ in
            playerItem = nil
            annotationTracks = nil
            enabledLayerNames = []
            errorMessage = nil
            tracksErrorMessage = nil
            isManualCanvasEnabled = false
            draftManualAnnotation = nil
            prepareArtifacts()
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        if let playerItem {
            PlaybackChromeView<EmptyView, EmptyView>(
                playerItem: playerItem,
                playbackEnabled: true,
                showsSpeedControls: true,
                startsPlaying: false,
                allowsFullscreen: presentation == .card,
                allowsTransportGestures: presentation == .card,
                contentOverlayAllowsHitTesting: isManualCanvasEnabled,
                edgeToEdge: presentation == .immersive,
                contentOverlay: { currentTime, _ in
                    AnyView(
                        ZStack {
                            AnnotationVideoOverlay(
                                tracks: annotationTracks,
                                currentTime: currentTime,
                                enabledLayerNames: enabledLayerNames
                            )

                            ManualAnnotationCanvasOverlay(
                                tracks: annotationTracks,
                                currentTime: currentTime,
                                analysisID: analysisID,
                                annotations: manualStore.annotations(for: analysisID),
                                draftAnnotation: draftManualAnnotation,
                                enabled: enabledLayerNames.contains("manual"),
                                editingEnabled: isManualCanvasEnabled,
                                selectedTool: selectedManualTool,
                                selectedColorHex: selectedManualColor,
                                labelText: manualLabelText,
                                appliesToFullSwing: manualAppliesToFullSwing,
                                onDraftChanged: { draftManualAnnotation = $0 },
                                onCommit: { annotation in
                                    manualStore.add(annotation)
                                    draftManualAnnotation = nil
                                },
                                onErase: { point, seconds in
                                    manualStore.removeNearest(
                                        analysisID: analysisID,
                                        to: point,
                                        at: seconds
                                    )
                                }
                            )
                        }
                    )
                }
            ) {
                EmptyView()
            } overlayAccessory: {
                EmptyView()
            }
        } else {
            ZStack {
                Color.black
                if let errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading annotated video...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
    }

    private var annotationLayerControls: [SavedVisualizationLayer] {
        var controls = video.layers
        let hasServerAnnotationData =
            annotationTracks?.hasSpeedData == true ||
            annotationTracks?.hasClubPlaneData == true ||
            annotationTracks?.hasBallContactData == true ||
            annotationTracks?.hasPhaseMarkers == true ||
            annotationTracks?.hasConfidenceEvidence == true ||
            !(annotationTracks?.guideLayerNames ?? []).isEmpty
        guard !controls.isEmpty || hasServerAnnotationData else {
            return []
        }

        if annotationTracks?.hasSpeedData == true && !controls.contains(where: { $0.name == "speed" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "speed",
                    color: "#00FF80",
                    description: "Clubhead speed overlay",
                    enabled: true
                )
            )
        }
        if annotationTracks?.hasClubPlaneData == true && !controls.contains(where: { $0.name == "club_plane" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "club_plane",
                    color: "#FFA500",
                    description: "Address shaft plane reference",
                    enabled: true
                )
            )
        }
        if annotationTracks?.hasBallContactData == true && !controls.contains(where: { $0.name == "ball_contact" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "ball_contact",
                    color: "#FFFFFF",
                    description: "Ball contact evidence",
                    enabled: true
                )
            )
        }
        if annotationTracks?.hasPhaseMarkers == true && !controls.contains(where: { $0.name == "phase_markers" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "phase_markers",
                    color: "#FFFFFF",
                    description: "Detected swing phase markers",
                    enabled: true
                )
            )
        }
        if annotationTracks?.hasConfidenceEvidence == true && !controls.contains(where: { $0.name == "confidence" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "confidence",
                    color: "#00FF80",
                    description: "Confidence and impact evidence",
                    enabled: true
                )
            )
        }
        for guideLayerName in annotationTracks?.guideLayerNames ?? [] where !controls.contains(where: { $0.name == guideLayerName }) {
            controls.append(SavedVisualizationLayer.defaultGuideLayer(named: guideLayerName))
        }
        if hasServerAnnotationData && !controls.contains(where: { $0.name == "manual" }) {
            controls.append(
                SavedVisualizationLayer(
                    name: "manual",
                    color: "#FFD60A",
                    description: "Manual self-analysis drawings",
                    enabled: true
                )
            )
        }
        return controls
    }

    private var annotationControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(annotationLayerControls, id: \.name) { layer in
                    Button {
                        toggleLayer(layer.name)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: enabledLayerNames.contains(layer.name) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(layer.displayName)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(enabledLayerNames.contains(layer.name) ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle \(layer.displayName)")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var manualCanvasControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        isManualCanvasEnabled.toggle()
                        draftManualAnnotation = nil
                        enabledLayerNames.insert("manual")
                    } label: {
                        Image(systemName: isManualCanvasEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(isManualCanvasEnabled ? .black : .primary)
                            .frame(width: 36, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isManualCanvasEnabled ? Color.yellow : Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isManualCanvasEnabled ? "Disable drawing canvas" : "Enable drawing canvas")

                    if isManualCanvasEnabled {
                        ForEach(ManualAnnotationTool.allCases, id: \.self) { tool in
                            Button {
                                selectedManualTool = tool
                                draftManualAnnotation = nil
                            } label: {
                                Image(systemName: tool.systemImageName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(selectedManualTool == tool ? .black : .primary)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedManualTool == tool ? Color.yellow : Color(.secondarySystemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tool.accessibilityLabel)
                        }
                    }

                    Button {
                        manualStore.undoLast(for: analysisID)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo last drawing")

                    Button {
                        manualStore.clear(for: analysisID)
                        draftManualAnnotation = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear manual drawings")
                }
                .padding(.horizontal, 1)
            }

            if isManualCanvasEnabled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["#FFD60A", "#34C759", "#00E5FF", "#FF3B30", "#FFFFFF"], id: \.self) { colorHex in
                            Button {
                                selectedManualColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedManualColor == colorHex ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select drawing color")
                        }

                        Picker("Scope", selection: $manualAppliesToFullSwing) {
                            Text("All").tag(true)
                            Text("Moment").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 146)

                        if selectedManualTool == .label {
                            TextField("Label", text: $manualLabelText)
                                .font(.caption)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private var immersiveToolRail: some View {
        VStack(spacing: 10) {
            Button {
                toggleImmersiveRailSide()
            } label: {
                Image(systemName: immersiveRailSide.toggleIconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.54)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(immersiveRailSide.toggleAccessibilityLabel)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(annotationLayerControls, id: \.name) { layer in
                        immersiveLayerButton(layer)
                    }
                }
            }
            .frame(maxHeight: 430)

            Divider()
                .frame(width: 28)
                .overlay(Color.white.opacity(0.24))

            Button {
                isManualCanvasEnabled.toggle()
                draftManualAnnotation = nil
                enabledLayerNames.insert("manual")
            } label: {
                Image(systemName: isManualCanvasEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isManualCanvasEnabled ? .black : .white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(isManualCanvasEnabled ? Color.yellow : Color.black.opacity(0.54)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isManualCanvasEnabled ? "Disable drawing canvas" : "Enable drawing canvas")

            if isManualCanvasEnabled {
                ForEach(ManualAnnotationTool.allCases, id: \.self) { tool in
                    Button {
                        selectedManualTool = tool
                        draftManualAnnotation = nil
                    } label: {
                        Image(systemName: tool.systemImageName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(selectedManualTool == tool ? .black : .white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(selectedManualTool == tool ? Color.yellow : Color.black.opacity(0.54)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.accessibilityLabel)
                }

                Button {
                    manualStore.undoLast(for: analysisID)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.54)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last drawing")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.black.opacity(0.22)))
    }

    private var railSideDragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if value.translation.width < -24 {
                    immersiveRailSide = .leading
                } else if value.translation.width > 24 {
                    immersiveRailSide = .trailing
                }
            }
    }

    private func toggleImmersiveRailSide() {
        immersiveRailSide = immersiveRailSide == .trailing ? .leading : .trailing
    }

    private func immersiveLayerButton(_ layer: SavedVisualizationLayer) -> some View {
        let isEnabled = enabledLayerNames.contains(layer.name)
        return Button {
            toggleLayer(layer.name)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: layerIconName(layer.name))
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 30)

                Text(layer.shortDisplayName)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: 54)
            }
            .foregroundColor(isEnabled ? .black : .white)
            .frame(width: 58, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Color.yellow : Color.black.opacity(0.54))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle \(layer.displayName)")
        .accessibilityHint(layer.description)
    }

    private func layerIconName(_ name: String) -> String {
        switch name {
        case "skeleton":
            return "figure.golf"
        case "reference_lines":
            return "ruler"
        case "club_plane":
            return "angle"
        case "swing_path":
            return "scribble.variable"
        case "ball_contact":
            return "smallcircle.filled.circle"
        case "phase_markers":
            return "flag.checkered"
        case "confidence":
            return "checkmark.seal"
        case "speed":
            return "speedometer"
        case "shaft_checkpoints":
            return "target"
        case "clubhead_path":
            return "scope"
        case "setup_geometry":
            return "ruler.fill"
        case "head_reference":
            return "person.crop.circle"
        case "hip_depth":
            return "arrow.left.and.right"
        case "hand_depth":
            return "hand.raised"
        case "lead_arm_plane":
            return "line.3.horizontal.decrease"
        case "takeaway_checkpoint":
            return "arrow.turn.up.right"
        case "manual":
            return "pencil.tip.crop.circle"
        default:
            return "switch.2"
        }
    }

    private func toggleLayer(_ name: String) {
        if enabledLayerNames.contains(name) {
            enabledLayerNames.remove(name)
        } else {
            enabledLayerNames.insert(name)
        }
    }

    private func configureDefaultLayers() {
        guard enabledLayerNames.isEmpty else { return }
        enabledLayerNames = Set(annotationLayerControls.filter(\.enabled).map(\.name))
    }

    private func prepareArtifacts() {
        guard playerItem == nil else { return }
        let existingPlaybackURL = video.baseUrl ?? video.url

        if Date().timeIntervalSince(video.refreshedAt) > 45 * 60 {
            Task {
                do {
                    let refreshed = try await SwingCoachAPI.shared.refreshArtifactURL(key: video.key)
                    let refreshedBase = try? await refreshBaseURLIfNeeded()
                    let refreshedTracks = try? await refreshTracksURLIfNeeded()
                    await MainActor.run {
                        AnalysisLibrary.shared.updateAnnotatedVideoURLs(
                            for: analysisID,
                            url: refreshed.url,
                            baseUrl: refreshedBase,
                            tracksUrl: refreshedTracks
                        )
                        loadPlayer(urlString: refreshedBase ?? refreshed.url)
                        loadTracks(urlString: refreshedTracks ?? video.tracksUrl)
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Could not refresh annotated video."
                    }
                }
            }
        } else {
            loadPlayer(urlString: existingPlaybackURL)
            loadTracks(urlString: video.tracksUrl)
        }
    }

    private func refreshBaseURLIfNeeded() async throws -> String? {
        guard let baseKey = video.baseKey else { return nil }
        return try await SwingCoachAPI.shared.refreshArtifactURL(key: baseKey).url
    }

    private func refreshTracksURLIfNeeded() async throws -> String? {
        guard let tracksKey = video.tracksKey else { return nil }
        return try await SwingCoachAPI.shared.refreshArtifactURL(key: tracksKey).url
    }

    private func loadPlayer(urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "Annotated video link is invalid."
            return
        }
        playerItem = AVPlayerItem(url: url)
    }

    private func loadTracks(urlString: String?) {
        configureDefaultLayers()
        guard annotationTracks == nil, let urlString, let url = URL(string: urlString) else {
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(AnnotationTrackPayload.self, from: data)
                await MainActor.run {
                    annotationTracks = decoded
                    configureDefaultLayers()
                }
            } catch {
                await MainActor.run {
                    tracksErrorMessage = "Annotation overlays are unavailable for this result."
                    configureDefaultLayers()
                }
            }
        }
    }
}

private struct AnnotationTrackPayload: Decodable {
    let coordinateSpace: String
    let frameWidth: Double
    let frameHeight: Double
    let guideLayerNames: [String]
    let phaseMarkers: [PhaseMarker]
    let confidenceEvidence: ConfidenceEvidence?
    let frames: [Frame]

    var hasSpeedData: Bool {
        frames.contains { $0.layers.speed != nil }
    }

    var hasPhaseMarkers: Bool {
        !phaseMarkers.isEmpty
    }

    var hasClubPlaneData: Bool {
        frames.contains { $0.layers.clubPlane != nil }
    }

    var hasBallContactData: Bool {
        frames.contains { $0.layers.ballContact != nil }
    }

    var hasConfidenceEvidence: Bool {
        confidenceEvidence != nil
    }

    enum CodingKeys: String, CodingKey {
        case coordinateSpace = "coordinate_space"
        case frameWidth = "frame_width"
        case frameHeight = "frame_height"
        case guideLayerNames = "guide_layers"
        case phaseMarkers = "phase_markers"
        case confidenceEvidence = "confidence_evidence"
        case frames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinateSpace = try container.decode(String.self, forKey: .coordinateSpace)
        frameWidth = try container.decode(Double.self, forKey: .frameWidth)
        frameHeight = try container.decode(Double.self, forKey: .frameHeight)
        guideLayerNames = try container.decodeIfPresent([String].self, forKey: .guideLayerNames) ?? []
        phaseMarkers = try container.decodeIfPresent([PhaseMarker].self, forKey: .phaseMarkers) ?? []
        confidenceEvidence = try container.decodeIfPresent(ConfidenceEvidence.self, forKey: .confidenceEvidence)
        frames = try container.decode([Frame].self, forKey: .frames)
    }

    struct Frame: Decodable {
        let relativeTimestamp: Double
        let layers: Layers

        enum CodingKeys: String, CodingKey {
            case relativeTimestamp = "relative_timestamp"
            case layers
        }
    }

    struct Layers: Decodable {
        let skeleton: SkeletonLayer?
        let referenceLines: ReferenceLinesLayer?
        let swingPath: SwingPathLayer?
        let clubPlane: ClubPlaneLayer?
        let ballContact: BallContactLayer?
        let speed: SpeedLayer?
        let guides: [GuideShape]?

        enum CodingKeys: String, CodingKey {
            case skeleton
            case referenceLines = "reference_lines"
            case swingPath = "swing_path"
            case clubPlane = "club_plane"
            case ballContact = "ball_contact"
            case speed
            case guides
        }
    }

    struct PhaseMarker: Decodable {
        let phase: Int
        let name: String
        let description: String
        let relativeTimestamp: Double
        let confidence: Double

        var label: String {
            "P\(phase) \(displayName)"
        }

        var displayName: String {
            name
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }

        enum CodingKeys: String, CodingKey {
            case phase
            case name
            case description
            case relativeTimestamp = "relative_timestamp"
            case confidence
        }
    }

    struct ConfidenceEvidence: Decodable {
        let level: String
        let phaseConfidence: Double?
        let impact: ImpactEvidence
        let badges: [Badge]

        enum CodingKeys: String, CodingKey {
            case level
            case phaseConfidence = "phase_confidence"
            case impact
            case badges
        }
    }

    struct ImpactEvidence: Decodable {
        let detected: Bool
        let confidence: Double?
        let confidenceLevel: String
        let speedMph: Double?
        let speedAvailable: Bool
        let ballContactDetected: Bool?
        let ballContactConfidence: Double?

        enum CodingKeys: String, CodingKey {
            case detected
            case confidence
            case confidenceLevel = "confidence_level"
            case speedMph = "speed_mph"
            case speedAvailable = "speed_available"
            case ballContactDetected = "ball_contact_detected"
            case ballContactConfidence = "ball_contact_confidence"
        }
    }

    struct Badge: Decodable {
        let label: String
        let level: String
        let value: String
    }

    struct SkeletonLayer: Decodable {
        let keypoints: [String: NormalizedPoint]
        let connections: [Connection]
    }

    struct ReferenceLinesLayer: Decodable {
        let lines: [ReferenceLine]
    }

    struct SwingPathLayer: Decodable {
        let points: [NormalizedPoint]
    }

    struct ClubPlaneLayer: Decodable {
        let line: ReferenceLine
        let angleDegrees: Double
        let confidence: Double
        let frameIndex: Int

        enum CodingKeys: String, CodingKey {
            case line
            case angleDegrees = "angle_degrees"
            case confidence
            case frameIndex = "frame_index"
        }
    }

    struct BallContactLayer: Decodable {
        let center: NormalizedPoint
        let radius: Double
        let currentLuma: Double
        let baselineLuma: Double
        let lumaDelta: Double
        let isImpactWindow: Bool

        enum CodingKeys: String, CodingKey {
            case center
            case radius
            case currentLuma = "current_luma"
            case baselineLuma = "baseline_luma"
            case lumaDelta = "luma_delta"
            case isImpactWindow = "is_impact_window"
        }
    }

    struct SpeedLayer: Decodable {
        let speedMph: Double
        let isPeak: Bool

        enum CodingKeys: String, CodingKey {
            case speedMph = "speed_mph"
            case isPeak = "is_peak"
        }
    }

    struct GuideShape: Decodable {
        let id: String
        let layer: String
        let kind: String
        let label: String?
        let color: String?
        let confidence: Double?
        let style: String?
        let points: [NormalizedPoint]?
        let rect: NormalizedRect?
        let center: NormalizedPoint?
        let radius: Double?
    }

    struct NormalizedRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Connection: Decodable {
        let from: String
        let to: String
    }

    struct ReferenceLine: Decodable {
        let name: String
        let start: NormalizedPoint
        let end: NormalizedPoint

        enum CodingKeys: String, CodingKey {
            case name
            case start
            case end
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "reference"
            start = try container.decode(NormalizedPoint.self, forKey: .start)
            end = try container.decode(NormalizedPoint.self, forKey: .end)
        }
    }

    struct NormalizedPoint: Decodable {
        let x: Double
        let y: Double
    }
}

private struct AnnotationVideoOverlay: View {
    let tracks: AnnotationTrackPayload?
    let currentTime: CMTime
    let enabledLayerNames: Set<String>

    var body: some View {
        GeometryReader { geometry in
            if let tracks, let frame = frameForCurrentTime(in: tracks) {
                Canvas { context, size in
                    let videoRect = contentRect(for: tracks, in: size)
                    let guideLayerNames = Set(frame.layers.guides?.map(\.layer) ?? [])

                    if enabledLayerNames.contains("swing_path"),
                       let swingPath = frame.layers.swingPath,
                       !(enabledLayerNames.contains("clubhead_path") && guideLayerNames.contains("clubhead_path")) {
                        drawSwingPath(swingPath, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("skeleton"),
                       let skeleton = frame.layers.skeleton {
                        drawSkeleton(skeleton, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("reference_lines"),
                       let referenceLines = frame.layers.referenceLines {
                        drawReferenceLines(referenceLines, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("club_plane"),
                       let clubPlane = frame.layers.clubPlane,
                       !guideLayerNames.contains("club_plane") {
                        drawClubPlane(clubPlane, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("ball_contact"),
                       let ballContact = frame.layers.ballContact {
                        drawBallContact(ballContact, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("speed"),
                       let speed = frame.layers.speed {
                        drawSpeed(speed, in: &context, rect: videoRect)
                    }

                    if let guides = frame.layers.guides {
                        drawGuides(guides, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("phase_markers"),
                       let phaseMarker = currentPhaseMarker(in: tracks) {
                        drawPhaseMarker(phaseMarker, in: &context, rect: videoRect)
                    }

                    if enabledLayerNames.contains("confidence"),
                       let evidence = tracks.confidenceEvidence {
                        drawConfidenceEvidence(evidence, in: &context, rect: videoRect)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func frameForCurrentTime(in tracks: AnnotationTrackPayload) -> AnnotationTrackPayload.Frame? {
        let seconds = CMTimeGetSeconds(currentTime)
        guard seconds.isFinite else { return tracks.frames.first }
        return tracks.frames.last { $0.relativeTimestamp <= seconds } ?? tracks.frames.first
    }

    private func currentPhaseMarker(in tracks: AnnotationTrackPayload) -> AnnotationTrackPayload.PhaseMarker? {
        let seconds = CMTimeGetSeconds(currentTime)
        guard seconds.isFinite else { return nil }

        return tracks.phaseMarkers
            .filter { abs($0.relativeTimestamp - seconds) <= 0.18 }
            .min { abs($0.relativeTimestamp - seconds) < abs($1.relativeTimestamp - seconds) }
    }

    private func contentRect(for tracks: AnnotationTrackPayload, in size: CGSize) -> CGRect {
        let sourceAspect = CGFloat(max(tracks.frameWidth, 1) / max(tracks.frameHeight, 1))
        let containerAspect = size.width / max(size.height, 1)

        if containerAspect > sourceAspect {
            let height = size.height
            let width = height * sourceAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        } else {
            let width = size.width
            let height = width / sourceAspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height)
        }
    }

    private func point(_ normalized: AnnotationTrackPayload.NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(normalized.x) * rect.width,
            y: rect.minY + CGFloat(normalized.y) * rect.height
        )
    }

    private func drawSwingPath(
        _ layer: AnnotationTrackPayload.SwingPathLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        guard layer.points.count >= 2 else { return }
        var path = Path()
        path.move(to: point(layer.points[0], in: rect))
        for pointValue in layer.points.dropFirst() {
            path.addLine(to: point(pointValue, in: rect))
        }
        context.stroke(path, with: .color(.red), lineWidth: 3)

        if let last = layer.points.last {
            let center = point(last, in: rect)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.red))
        }
    }

    private func drawSkeleton(
        _ layer: AnnotationTrackPayload.SkeletonLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        for connection in layer.connections {
            guard let start = layer.keypoints[connection.from], let end = layer.keypoints[connection.to] else {
                continue
            }
            var path = Path()
            path.move(to: point(start, in: rect))
            path.addLine(to: point(end, in: rect))
            context.stroke(path, with: .color(.cyan), lineWidth: 2)
        }

        for keypoint in layer.keypoints.values {
            let center = point(keypoint, in: rect)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                with: .color(.cyan)
            )
        }
    }

    private func drawReferenceLines(
        _ layer: AnnotationTrackPayload.ReferenceLinesLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        for line in layer.lines {
            var path = Path()
            path.move(to: point(line.start, in: rect))
            path.addLine(to: point(line.end, in: rect))
            context.stroke(path, with: .color(.yellow), lineWidth: 2.5)
        }
    }

    private func drawClubPlane(
        _ layer: AnnotationTrackPayload.ClubPlaneLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        var path = Path()
        path.move(to: point(layer.line.start, in: rect))
        path.addLine(to: point(layer.line.end, in: rect))
        context.stroke(path, with: .color(.orange), lineWidth: 3)

        let label = Text("\(Int(layer.angleDegrees.rounded())) deg")
            .font(.caption2.weight(.bold))
            .foregroundColor(.orange)
        let start = point(layer.line.start, in: rect)
        let labelX = min(max(start.x + 44, rect.minX + 44), rect.maxX - 44)
        let labelY = min(max(start.y + 18, rect.minY + 18), rect.maxY - 18)
        context.draw(label, at: CGPoint(x: labelX, y: labelY))
    }

    private func drawBallContact(
        _ layer: AnnotationTrackPayload.BallContactLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        let center = point(layer.center, in: rect)
        let radius = max(9, CGFloat(layer.radius) * min(rect.width, rect.height))
        let color: Color = layer.isImpactWindow ? .white : .white.opacity(0.55)
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.stroke(circle, with: .color(color), lineWidth: layer.isImpactWindow ? 2.5 : 1.5)

        if layer.isImpactWindow {
            let label = Text("Ball \(Int(layer.lumaDelta.rounded()))")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
            let labelX = min(max(center.x, rect.minX + 42), rect.maxX - 42)
            let labelY = min(max(center.y - radius - 13, rect.minY + 13), rect.maxY - 13)
            context.draw(label, at: CGPoint(x: labelX, y: labelY))
        }
    }

    private func drawSpeed(
        _ layer: AnnotationTrackPayload.SpeedLayer,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        let text = Text("\(Int(layer.speedMph.rounded())) mph")
            .font(.caption.weight(.bold))
            .foregroundColor(layer.isPeak ? .yellow : .green)
        context.draw(text, at: CGPoint(x: rect.minX + 54, y: rect.minY + 58))
    }

    private func drawGuides(
        _ guides: [AnnotationTrackPayload.GuideShape],
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        for guide in guides where enabledLayerNames.contains(guide.layer) {
            drawGuide(guide, in: &context, rect: rect)
        }
    }

    private func drawGuide(
        _ guide: AnnotationTrackPayload.GuideShape,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        let color = Color(hex: guide.color ?? "#FFD60A")
        let lineWidth = guide.style == "dashed" ? 1.8 : 2.6

        switch guide.kind {
        case "line", "arrow":
            guard let points = guide.points, points.count >= 2 else { return }
            let start = point(points[0], in: rect)
            let end = point(points[1], in: rect)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                dash: guide.style == "dashed" ? [7, 5] : []
            ))
            if guide.kind == "arrow" {
                drawArrowHead(from: start, to: end, color: color, in: &context)
            }
            drawGuideLabel(guide.label, at: end, color: color, in: &context, rect: rect)

        case "polyline":
            guard let points = guide.points, points.count >= 2 else { return }
            var path = Path()
            path.move(to: point(points[0], in: rect))
            for next in points.dropFirst() {
                path.addLine(to: point(next, in: rect))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        case "rectangle":
            guard let normalizedRect = guide.rect else { return }
            let drawRect = CGRect(
                x: rect.minX + CGFloat(normalizedRect.x) * rect.width,
                y: rect.minY + CGFloat(normalizedRect.y) * rect.height,
                width: CGFloat(normalizedRect.width) * rect.width,
                height: CGFloat(normalizedRect.height) * rect.height
            )
            context.stroke(Path(roundedRect: drawRect, cornerRadius: 4), with: .color(color), lineWidth: lineWidth)
            drawGuideLabel(guide.label, at: CGPoint(x: drawRect.midX, y: drawRect.minY), color: color, in: &context, rect: rect)

        case "circle":
            guard let center = guide.center else { return }
            let centerPoint = point(center, in: rect)
            let radius = max(5, CGFloat(guide.radius ?? 0.02) * min(rect.width, rect.height))
            let circle = CGRect(x: centerPoint.x - radius, y: centerPoint.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: circle), with: .color(color), lineWidth: lineWidth)
            drawGuideLabel(guide.label, at: CGPoint(x: centerPoint.x, y: centerPoint.y - radius - 8), color: color, in: &context, rect: rect)

        case "label":
            guard let center = guide.center else { return }
            drawGuideLabel(guide.label, at: point(center, in: rect), color: color, in: &context, rect: rect)

        default:
            return
        }
    }

    private func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 13
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let p2 = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        var head = Path()
        head.move(to: end)
        head.addLine(to: p1)
        head.move(to: end)
        head.addLine(to: p2)
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawGuideLabel(
        _ label: String?,
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        guard let label, !label.isEmpty else { return }
        let clamped = CGPoint(
            x: min(max(point.x, rect.minX + 42), rect.maxX - 42),
            y: min(max(point.y, rect.minY + 14), rect.maxY - 14)
        )
        let text = Text(label)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
        context.draw(text, at: clamped)
    }

    private func drawPhaseMarker(
        _ marker: AnnotationTrackPayload.PhaseMarker,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        let label = Text(marker.label)
            .font(.caption.weight(.bold))
            .foregroundColor(.white)

        let badgeRect = CGRect(x: rect.midX - 74, y: rect.minY + 18, width: 148, height: 30)
        let background = Path(roundedRect: badgeRect, cornerRadius: 8)
        context.fill(background, with: .color(.black.opacity(0.62)))
        context.stroke(background, with: .color(.white.opacity(0.65)), lineWidth: 1)
        context.draw(label, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
    }

    private func drawConfidenceEvidence(
        _ evidence: AnnotationTrackPayload.ConfidenceEvidence,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        let badgeWidth: CGFloat = 112
        let badgeHeight: CGFloat = 26
        let startX = rect.minX + 12
        let startY = rect.minY + 18

        for (index, badge) in evidence.badges.prefix(3).enumerated() {
            let badgeRect = CGRect(
                x: startX,
                y: startY + CGFloat(index) * (badgeHeight + 6),
                width: badgeWidth,
                height: badgeHeight
            )
            let background = Path(roundedRect: badgeRect, cornerRadius: 7)
            context.fill(background, with: .color(.black.opacity(0.62)))
            context.stroke(background, with: .color(color(forConfidenceLevel: badge.level).opacity(0.85)), lineWidth: 1.2)

            let text = Text("\(badge.label): \(badge.value)")
                .font(.caption2.weight(.bold))
                .foregroundColor(color(forConfidenceLevel: badge.level))
            context.draw(text, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
        }
    }

    private func color(forConfidenceLevel level: String) -> Color {
        switch level {
        case "high":
            return .green
        case "medium":
            return .yellow
        case "low":
            return .orange
        default:
            return .white.opacity(0.78)
        }
    }
}

private extension SavedVisualizationLayer {
    var displayName: String {
        switch name {
        case "skeleton":
            return "Body Pose"
        case "reference_lines":
            return "Body Lines"
        case "club_plane":
            return "Shaft Plane"
        case "swing_path":
            return "Swing Path"
        case "ball_contact":
            return "Ball Contact"
        case "phase_markers":
            return "Phase Markers"
        case "confidence":
            return "Confidence"
        case "speed":
            return "Speed"
        case "shaft_checkpoints":
            return "Shaft Checkpoints"
        case "clubhead_path":
            return "Clubhead Path"
        case "setup_geometry":
            return "Setup Geometry"
        case "head_reference":
            return "Head Reference"
        case "hip_depth":
            return "Hip Depth"
        case "hand_depth":
            return "Hand Path"
        case "lead_arm_plane":
            return "Lead Arm Plane"
        case "takeaway_checkpoint":
            return "Takeaway"
        case "manual":
            return "Draw"
        default:
            return name
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    var shortDisplayName: String {
        switch name {
        case "skeleton":
            return "Pose"
        case "reference_lines":
            return "Body"
        case "club_plane":
            return "Plane"
        case "swing_path":
            return "Path"
        case "ball_contact":
            return "Ball"
        case "phase_markers":
            return "Phase"
        case "confidence":
            return "Conf"
        case "speed":
            return "Speed"
        case "shaft_checkpoints":
            return "Shaft"
        case "clubhead_path":
            return "Club"
        case "setup_geometry":
            return "Setup"
        case "head_reference":
            return "Head"
        case "hip_depth":
            return "Hips"
        case "hand_depth":
            return "Hands"
        case "lead_arm_plane":
            return "Arm"
        case "takeaway_checkpoint":
            return "Take"
        case "manual":
            return "Draw"
        default:
            return displayName
        }
    }

    static func defaultGuideLayer(named name: String) -> SavedVisualizationLayer {
        let catalog: [String: (String, String, Bool)] = [
            "shaft_checkpoints": ("#FFD400", "Shaft checkpoints at key swing phases", true),
            "clubhead_path": ("#FF3B30", "Clubhead trace through the analyzed swing window", true),
            "setup_geometry": ("#00E5FF", "Setup posture, stance, and alignment references", false),
            "head_reference": ("#FFFFFF", "Address head reference compared with later swing positions", true),
            "hip_depth": ("#FF9500", "Address hip-depth reference for posture checks", false),
            "hand_depth": ("#BF5AF2", "Hand-depth path and top-position checkpoint", false),
            "lead_arm_plane": ("#34C759", "Lead-arm plane compared with shoulder plane at the top", false),
            "takeaway_checkpoint": ("#FFD60A", "Takeaway hand and shaft relationship checkpoint", true),
        ]
        let item = catalog[name] ?? ("#FFD60A", "Swing checkpoint guide", true)
        return SavedVisualizationLayer(name: name, color: item.0, description: item.1, enabled: item.2)
    }
}

private struct ManualAnnotationCanvasOverlay: View {
    let tracks: AnnotationTrackPayload?
    let currentTime: CMTime
    let analysisID: String
    let annotations: [ManualAnnotation]
    let draftAnnotation: ManualAnnotation?
    let enabled: Bool
    let editingEnabled: Bool
    let selectedTool: ManualAnnotationTool
    let selectedColorHex: String
    let labelText: String
    let appliesToFullSwing: Bool
    let onDraftChanged: (ManualAnnotation?) -> Void
    let onCommit: (ManualAnnotation) -> Void
    let onErase: (ManualAnnotationPoint, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let videoRect = contentRect(in: geometry.size)
            Canvas { context, _ in
                guard enabled else { return }
                let seconds = currentSeconds
                for annotation in annotations where annotation.isVisible(at: seconds) {
                    draw(annotation, in: &context, rect: videoRect, isDraft: false)
                }
                if let draftAnnotation {
                    draw(draftAnnotation, in: &context, rect: videoRect, isDraft: true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: selectedTool == .label || selectedTool == .eraser ? 0 : 4)
                    .onChanged { value in
                        guard editingEnabled else { return }
                        updateDraft(with: value, rect: videoRect)
                    }
                    .onEnded { value in
                        guard editingEnabled else { return }
                        finishDraft(with: value, rect: videoRect)
                    }
            )
        }
        .allowsHitTesting(editingEnabled)
    }

    private var currentSeconds: Double {
        let seconds = CMTimeGetSeconds(currentTime)
        return seconds.isFinite ? seconds : 0
    }

    private func contentRect(in size: CGSize) -> CGRect {
        let sourceWidth = tracks?.frameWidth ?? Double(size.width)
        let sourceHeight = tracks?.frameHeight ?? Double(size.height)
        let sourceAspect = CGFloat(max(sourceWidth, 1) / max(sourceHeight, 1))
        let containerAspect = size.width / max(size.height, 1)

        if containerAspect > sourceAspect {
            let height = size.height
            let width = height * sourceAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        } else {
            let width = size.width
            let height = width / sourceAspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height)
        }
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> ManualAnnotationPoint {
        ManualAnnotationPoint(
            x: Double(min(max((point.x - rect.minX) / max(rect.width, 1), 0), 1)),
            y: Double(min(max((point.y - rect.minY) / max(rect.height, 1), 0), 1))
        )
    }

    private func screenPoint(_ point: ManualAnnotationPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.minY + CGFloat(point.y) * rect.height
        )
    }

    private func updateDraft(with value: DragGesture.Value, rect: CGRect) {
        let start = normalizedPoint(value.startLocation, in: rect)
        let current = normalizedPoint(value.location, in: rect)

        if selectedTool == .eraser {
            onErase(current, currentSeconds)
            return
        }

        if selectedTool == .label {
            onDraftChanged(
                ManualAnnotation(
                    analysisID: analysisID,
                    tool: .label,
                    points: [current],
                    text: labelText.isEmpty ? "Note" : labelText,
                    colorHex: selectedColorHex,
                    strokeWidth: 3,
                    timestamp: currentSeconds,
                    appliesToFullSwing: appliesToFullSwing
                )
            )
            return
        }

        if selectedTool == .freehand {
            var points = draftAnnotation?.points ?? [start]
            if points.last != current {
                points.append(current)
            }
            onDraftChanged(makeDraft(tool: .freehand, points: points))
            return
        }

        onDraftChanged(makeDraft(tool: selectedTool, points: [start, current]))
    }

    private func finishDraft(with value: DragGesture.Value, rect: CGRect) {
        if selectedTool == .eraser {
            onErase(normalizedPoint(value.location, in: rect), currentSeconds)
            onDraftChanged(nil)
            return
        }

        if selectedTool == .label {
            let point = normalizedPoint(value.location, in: rect)
            onCommit(
                ManualAnnotation(
                    analysisID: analysisID,
                    tool: .label,
                    points: [point],
                    text: labelText.isEmpty ? "Note" : labelText,
                    colorHex: selectedColorHex,
                    strokeWidth: 3,
                    timestamp: currentSeconds,
                    appliesToFullSwing: appliesToFullSwing
                )
            )
            return
        }

        if let draftAnnotation, draftAnnotation.points.count >= 2 {
            onCommit(draftAnnotation)
        }
        onDraftChanged(nil)
    }

    private func makeDraft(tool: ManualAnnotationTool, points: [ManualAnnotationPoint]) -> ManualAnnotation {
        ManualAnnotation(
            analysisID: analysisID,
            tool: tool,
            points: points,
            colorHex: selectedColorHex,
            strokeWidth: 3,
            timestamp: currentSeconds,
            appliesToFullSwing: appliesToFullSwing
        )
    }

    private func draw(
        _ annotation: ManualAnnotation,
        in context: inout GraphicsContext,
        rect: CGRect,
        isDraft: Bool
    ) {
        let color = Color(hex: annotation.colorHex).opacity(isDraft ? 0.72 : 1.0)
        let points = annotation.points.map { screenPoint($0, in: rect) }
        let stroke = StrokeStyle(lineWidth: CGFloat(annotation.strokeWidth), lineCap: .round, lineJoin: .round)

        switch annotation.tool {
        case .line, .arrow:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            context.stroke(path, with: .color(color), style: stroke)
            if annotation.tool == .arrow {
                drawManualArrowHead(from: points[0], to: points[1], color: color, in: &context)
            }

        case .freehand:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: stroke)

        case .rectangle:
            guard points.count >= 2 else { return }
            let drawRect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            context.stroke(Path(roundedRect: drawRect, cornerRadius: 4), with: .color(color), style: stroke)

        case .circle:
            guard points.count >= 2 else { return }
            let radius = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
            let circle = CGRect(x: points[0].x - radius, y: points[0].y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: circle), with: .color(color), style: stroke)

        case .label:
            guard let point = points.first else { return }
            let text = Text(annotation.text ?? "Note")
                .font(.caption.weight(.bold))
                .foregroundColor(color)
            context.draw(text, at: point)

        case .eraser:
            return
        }
    }

    private func drawManualArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 14
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let p2 = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        var path = Path()
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }
}

private extension ManualAnnotationTool {
    var systemImageName: String {
        switch self {
        case .line:
            return "line.diagonal"
        case .arrow:
            return "arrow.up.right"
        case .freehand:
            return "scribble"
        case .rectangle:
            return "rectangle"
        case .circle:
            return "circle"
        case .label:
            return "textformat"
        case .eraser:
            return "eraser"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .line:
            return "Line drawing tool"
        case .arrow:
            return "Arrow drawing tool"
        case .freehand:
            return "Freehand drawing tool"
        case .rectangle:
            return "Rectangle drawing tool"
        case .circle:
            return "Circle drawing tool"
        case .label:
            return "Text label tool"
        case .eraser:
            return "Eraser tool"
        }
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch sanitized.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 255
            green = 214
            blue = 10
        }

        self.init(
            .sRGB,
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: 1.0
        )
    }
}
