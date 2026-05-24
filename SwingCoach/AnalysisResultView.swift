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
    let video: SavedAnalysisVideo
    let analysisID: String

    @State private var playerItem: AVPlayerItem?
    @State private var annotationTracks: AnnotationTrackPayload?
    @State private var enabledLayerNames: Set<String> = []
    @State private var errorMessage: String?
    @State private var tracksErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let playerItem {
                    PlaybackChromeView(
                        playerItem: playerItem,
                        playbackEnabled: true,
                        showsSpeedControls: true,
                        startsPlaying: false,
                        contentOverlay: { currentTime, _ in
                            AnyView(
                                AnnotationVideoOverlay(
                                    tracks: annotationTracks,
                                    currentTime: currentTime,
                                    enabledLayerNames: enabledLayerNames
                                )
                            )
                        }
                    ) {
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
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !annotationLayerControls.isEmpty {
                annotationControls
            } else if let tracksErrorMessage {
                Text(tracksErrorMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            prepareArtifacts()
        }
    }

    private var annotationLayerControls: [SavedVisualizationLayer] {
        var controls = video.layers
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
        case phaseMarkers = "phase_markers"
        case confidenceEvidence = "confidence_evidence"
        case frames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinateSpace = try container.decode(String.self, forKey: .coordinateSpace)
        frameWidth = try container.decode(Double.self, forKey: .frameWidth)
        frameHeight = try container.decode(Double.self, forKey: .frameHeight)
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

        enum CodingKeys: String, CodingKey {
            case skeleton
            case referenceLines = "reference_lines"
            case swingPath = "swing_path"
            case clubPlane = "club_plane"
            case ballContact = "ball_contact"
            case speed
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

    struct Connection: Decodable {
        let from: String
        let to: String
    }

    struct ReferenceLine: Decodable {
        let name: String
        let start: NormalizedPoint
        let end: NormalizedPoint
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

                    if enabledLayerNames.contains("swing_path"),
                       let swingPath = frame.layers.swingPath {
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
                       let clubPlane = frame.layers.clubPlane {
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
        name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
