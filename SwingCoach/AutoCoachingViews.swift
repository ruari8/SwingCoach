//
//  AutoCoachingViews.swift
//  SwingCoach
//
//  Coaching on the Auto camera screen: the chip that sets how often the
//  coach speaks, the latest swing's verdict, the recap of the last few
//  swings, and the side-by-side comparison the recap opens.
//

import AVFoundation
import SwiftUI

/// What the Auto review cover opens on.
struct AutoSwingReviewPresentation: Identifiable {
    let id = UUID()
    /// The swing to start on; the newest when nil.
    var startAt: UUID?
    /// The recap's swings side by side first, before the player.
    var compare: CoachingComparison?
}

/// A recap's swings and the theme they are compared on.
struct CoachingComparison: Equatable {
    let swingIDs: [UUID]
    let theme: CoachingTheme
}

// MARK: - On the camera screen

/// Sits between the camera's top bar and its bottom row in Auto.
struct AutoCoachingPanel: View {
    /// The Auto session's swings, oldest first.
    let swings: [SavedSwing]
    let open: (AutoSwingReviewPresentation) -> Void

    @ObservedObject private var store = SwingCoachingStore.shared
    @AppStorage(CoachingCadence.key) private var cadenceName = CoachingCadence.standard.rawValue
    @State private var schedule = CoachingRecapSchedule()
    /// The swings of the recap on screen.
    @State private var recapIDs: [UUID]?

    private var cadence: CoachingCadence { CoachingCadence(rawValue: cadenceName) ?? .standard }

    private var measured: [(swing: SavedSwing, report: SwingCoachingReport)] {
        swings.compactMap { swing in store.report(for: swing).map { (swing, $0) } }
    }

    var body: some View {
        let measured = measured
        VStack(spacing: 0) {
            chip(canRecap: !measured.isEmpty)
                .padding(.top, 10)
            Spacer(minLength: 16)
            if let recapIDs {
                recapCard(for: measured.filter { recapIDs.contains($0.swing.id) })
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if cadence == .everySwing, let latest = swings.last, let report = store.report(for: latest) {
                latestVerdict(store.verdict(for: latest, report: report), swing: latest)
                    .padding(.bottom, 10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: recapIDs)
        .onAppear { update(measured.map(\.swing.id)) }
        .onChange(of: measured.map(\.swing.id)) { _, ids in update(ids) }
        .onChange(of: cadenceName) { _, _ in
            schedule.cadenceChanged(measured: measured.count, cadence: cadence)
        }
    }

    /// Shows a recap when a new one comes due. `ids` are the measured
    /// swings, oldest first.
    private func update(_ ids: [UUID]) {
        if let shown = recapIDs, !shown.allSatisfy(ids.contains) { recapIDs = nil }
        if let range = schedule.update(measured: ids.count, cadence: cadence) {
            recapIDs = Array(ids[range])
        }
    }

    private func chip(canRecap: Bool) -> some View {
        Menu {
            Picker("Coach speaks", selection: $cadenceName) {
                ForEach(CoachingCadence.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Recap the last swings", systemImage: "list.bullet.rectangle") {
                let size = cadence.recapSize ?? CoachingCadence.requestedRecapSize
                recapIDs = measured.suffix(size).map(\.swing.id)
            }
            .disabled(!canRecap)
        } label: {
            HStack(spacing: 6) {
                Text("Coach: \(cadence.title.lowercased())")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        }
        .accessibilityIdentifier("coach-cadence")
        .accessibilityLabel("Coach speaks: \(cadence.title)")
    }

    private func latestVerdict(_ verdict: CoachingVerdict, swing: SavedSwing) -> some View {
        Button {
            open(AutoSwingReviewPresentation(startAt: swing.id))
        } label: {
            HStack(spacing: 8) {
                Circle().fill(verdict.colour).frame(width: 9, height: 9)
                Text(verdict.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("coach-latest-verdict")
        .accessibilityLabel("Last swing: \(verdict.headline)")
    }

    private func recapCard(for group: [(swing: SavedSwing, report: SwingCoachingReport)]) -> some View {
        let recap = CoachingFeedback.recap(of: group.map(\.report))
        let numbers = group.map { entry in (swings.firstIndex { $0.id == entry.swing.id } ?? 0) + 1 }
        return CoachingRecapCard(recap: recap, numbers: numbers) {
            if let theme = recap.theme {
                open(AutoSwingReviewPresentation(compare: CoachingComparison(swingIDs: group.map(\.swing.id), theme: theme)))
            } else {
                open(AutoSwingReviewPresentation(startAt: group.first?.swing.id))
            }
        } onClose: {
            recapIDs = nil
        }
    }
}

extension CoachingVerdict {
    var colour: Color {
        switch self {
        case .notJudged: .gray
        case .good, .better: .coachingLevel(0)
        case .focus(let finding): .coachingLevel(finding.level)
        }
    }
}

/// What the last few swings had in common, over the camera.
struct CoachingRecapCard: View {
    let recap: CoachingRecap
    /// The swings' numbers in the session, oldest first.
    let numbers: [Int]
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(numbers.count == 1 ? "Last swing" : "Last \(numbers.count) swings")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close recap")
                .accessibilityIdentifier("coach-recap-close")
            }
            if let theme = recap.theme {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color.coachingLevel(theme.medianLevel)).frame(width: 9, height: 9)
                    Text(theme.text)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(theme.swings) of \(theme.measured) swings · P\(theme.position) \(SwingPosition.names[theme.position - 1].lowercased())")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                if CoachingMetricDefinition.definition(theme.metric).dependsOnCamera {
                    Text("A club reading: it shifts with where the camera stands.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                levelBars
            } else {
                Text(recap.judged == 0 ? "None of these could be judged" : "Nothing kept repeating")
                    .font(.title3.weight(.bold))
                Text(recap.judged == 0
                     ? "Chips, a moved camera or unclear positions are measured but not judged."
                     : "\(recap.good) of \(recap.judged) needed no pointer. Carry on.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(recap.theme == nil ? "Look at them" : "Compare them")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-recap-open")
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-recap")
    }

    /// One bar per swing: green where the theme didn't show, amber or red
    /// by how far out it was, grey where the swing couldn't be judged.
    private var levelBars: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(zip(numbers, recap.levels).enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(entry.1.map(Color.coachingLevel) ?? .gray.opacity(0.6))
                        .frame(height: 6)
                    Text("\(entry.0)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Swing \(entry.0): \(entry.1.map { $0 == 0 ? "in zone" : "level \($0)" } ?? "not judged")")
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - One check on one swing, as a picture

/// The frame a check was measured on, with its drawing. Reads the frame
/// from the swing's saved clip.
struct CoachingFrameView: View {
    let swing: SavedSwing
    let report: SwingCoachingReport
    let metric: CoachingMetricID

    @State private var frame: UIImage?
    @State private var loaded = false

    var body: some View {
        let result = report.metric(metric)
        ZStack {
            Color.black
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                if let result {
                    SwingCoachingOverlay(
                        report: report, picks: [],
                        aspectRatio: Double(frame.size.width / max(frame.size.height, 1)),
                        currentTime: CMTime(seconds: result.clipTime, preferredTimescale: 600),
                        timeScale: swing.sourceTimeScale ?? 1, highlighted: metric, still: true
                    )
                }
            } else if loaded {
                Image(systemName: "video.slash")
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: "\(swing.id.uuidString)-\(metric.rawValue)") {
            frame = await Self.frame(of: swing, at: result?.clipTime)
            loaded = true
        }
    }

    private static func frame(of swing: SavedSwing, at clipTime: Double?) async -> UIImage? {
        guard let clipTime, let url = SwingLibrary.shared.localVideoURL(for: swing) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try? await generator.image(at: CMTime(seconds: clipTime, preferredTimescale: 600)).image
        return image.map(UIImage.init(cgImage:))
    }
}

// MARK: - Comparison

/// A recap's swings side by side at the theme's position, each with the
/// theme's drawing. Tapping one opens it in the player.
struct CoachingCompareView: View {
    /// The swings with their numbers in the session, oldest first.
    let swings: [(number: Int, swing: SavedSwing)]
    let theme: CoachingTheme
    let onOpen: (SavedSwing) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = SwingCoachingStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.text).font(.title3.weight(.bold))
                        Text("P\(theme.position) \(SwingPosition.names[theme.position - 1].lowercased()) · white is where you were at address, green is where good players are, the colour is this swing")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                        ForEach(swings, id: \.swing.id) { entry in
                            tile(entry.number, entry.swing)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Last \(swings.count) swings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("coach-compare")
    }

    @ViewBuilder
    private func tile(_ number: Int, _ swing: SavedSwing) -> some View {
        let report = store.report(for: swing)
        let level = report.flatMap { CoachingFeedback.level(of: theme, in: $0) }
        let metric = report.flatMap { CoachingFeedback.metric(showing: theme, in: $0) }
        Button {
            onOpen(swing)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let report, let metric {
                        CoachingFrameView(swing: swing, report: report, metric: metric)
                    } else {
                        Color.black.overlay(Text("Not measured").font(.caption).foregroundStyle(.secondary))
                    }
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                HStack(spacing: 6) {
                    Circle().fill(level.map(Color.coachingLevel) ?? .gray).frame(width: 8, height: 8)
                    Text("Swing \(number)").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(level.map { $0 == 0 ? "in zone" : "level \($0)" } ?? "not judged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-compare-swing-\(number)")
    }
}

/// The Auto review cover: the recap's comparison first when it was asked
/// for, then the player.
struct AutoReviewCover: View {
    let presentation: AutoSwingReviewPresentation
    let swings: [SavedSwing]
    let onDelete: @MainActor (SavedSwing) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comparing: Bool
    @State private var startAt: UUID?

    init(presentation: AutoSwingReviewPresentation, swings: [SavedSwing],
         onDelete: @escaping @MainActor (SavedSwing) async throws -> Void) {
        self.presentation = presentation
        self.swings = swings
        self.onDelete = onDelete
        _comparing = State(initialValue: presentation.compare != nil)
        _startAt = State(initialValue: presentation.startAt)
    }

    var body: some View {
        if comparing, let compare = presentation.compare {
            CoachingCompareView(
                swings: swings.enumerated()
                    .filter { compare.swingIDs.contains($0.element.id) }
                    .map { (number: $0.offset + 1, swing: $0.element) },
                theme: compare.theme,
                onOpen: { swing in
                    startAt = swing.id
                    comparing = false
                },
                onClose: { dismiss() }
            )
        } else {
            AutoSwingReviewView(swings: swings, startAt: startAt, onDelete: onDelete)
        }
    }
}
