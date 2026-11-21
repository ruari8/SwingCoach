import SwiftUI

enum ReviewPlaybackControlsPlacement {
    case inline
    case selectedPage
    case otherPage
}

private struct ReviewPlaybackControlsPlacementKey: EnvironmentKey {
    static let defaultValue = ReviewPlaybackControlsPlacement.inline
}

private struct ReviewCornerControlsInNavigationKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReviewToolRailTrailingTopKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var reviewPlaybackControlsPlacement: ReviewPlaybackControlsPlacement {
        get { self[ReviewPlaybackControlsPlacementKey.self] }
        set { self[ReviewPlaybackControlsPlacementKey.self] = newValue }
    }

    var reviewCornerControlsInNavigation: Bool {
        get { self[ReviewCornerControlsInNavigationKey.self] }
        set { self[ReviewCornerControlsInNavigationKey.self] = newValue }
    }

    /// Where a navigation-hosted tool rail starts on the right: under the
    /// top-right button by default, or 0 to take an empty top-right slot.
    var reviewToolRailTrailingTop: CGFloat? {
        get { self[ReviewToolRailTrailingTopKey.self] }
        set { self[ReviewToolRailTrailingTopKey.self] = newValue }
    }
}

/// A page owns its playback state, but the pager renders its controls outside
/// the moving strip. Type erasure lets different player headers/accessories
/// use the same fixed overlay.
struct ReviewPlaybackControlsKey: PreferenceKey {
    static var defaultValue: AnyView? { nil }

    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        value = nextValue() ?? value
    }
}

struct ReviewPlaybackCornerControlsKey: PreferenceKey {
    static var defaultValue: AnyView? { nil }

    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        value = nextValue() ?? value
    }
}

/// Stable, viewport-sized pages. ScrollView owns dragging, cancellation and
/// deceleration; changing selection never rebuilds or rebases the page strip.
struct SwingReviewPager<Item: Identifiable, Page: View>: View where Item.ID == UUID {
    let swings: [Item]
    @Binding var selection: UUID?
    var pagingEnabled = true
    var title: (Item) -> String = { _ in "Swing video" }
    @ViewBuilder let page: (Item) -> Page
    @State private var scrollID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(swings) { swing in
                        page(swing)
                            .environment(\.reviewPlaybackControlsPlacement,
                                         swing.id == selection ? .selectedPage : .otherPage)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            // Video layers that ignore safe areas must never draw
                            // into their neighbour while either page is moving.
                            .clipped()
                            .allowsHitTesting(swing.id == selection)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("swing-review-page")
                            .accessibilityLabel(title(swing))
                            .id(swing.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(SingleVideoScrollTargetBehavior())
            .scrollPosition(id: $scrollID, anchor: .center)
            .scrollDisabled(!pagingEnabled)
            .onChange(of: selection, initial: true) { _, id in
                // Apply the initial destination after the scroll view exists.
                // A pre-filled external binding alone can leave it on page one.
                if scrollID != id { scrollID = id }
            }
            .onChange(of: scrollID) { _, id in
                if let id, selection != id { selection = id }
            }
            .overlayPreferenceValue(ReviewPlaybackControlsKey.self) { controls in
                controls
            }
        }
    }
}

/// Bound the projected destination to the pages adjacent to the gesture's
/// starting page. View-aligned limiting can still skip on high-velocity flicks.
private struct SingleVideoScrollTargetBehavior: ScrollTargetBehavior {
    func properties(context: PropertiesContext) -> Properties {
        var properties = Properties()
        // Use the shorter native settling motion appropriate for discrete pages.
        properties.limitsScrolls = true
        return properties
    }

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let width = context.containerSize.width
        guard width > 0 else { return }

        let start = (context.originalTarget.rect.minX / width).rounded()
        // Commit sooner than the halfway point. The projected position includes
        // release velocity, so a short flick can also pull the next page in.
        let progress = target.rect.minX / width - start
        let step: CGFloat = abs(progress) >= 0.25 ? (progress > 0 ? 1 : -1) : 0
        let destination = start + step
        let maximumOffset = max(0, context.contentSize.width - width)
        target.rect.origin.x = min(max(destination * width, 0), maximumOffset)
        target.rect.size.width = width
    }
}

/// The review player's top row, the same in Library and Auto review: a
/// button out on the left, the swing's number in the order hit in the
/// middle, the star on the right. The tool rail hangs under the star.
/// It is pinned `topPadding` under the safe area in every player state,
/// never to the video, and its buttons carry an edge so they read on
/// the black around a letterboxed or lifted clip as well as on video.
struct ReviewTopBar: View {
    let leadingTitle: String
    let leadingAccessibilityLabel: String
    let onLeading: () -> Void
    /// "Swing 3 of 5", or nil for a single swing.
    let counter: String?
    var counterValue: String = ""
    let isStarred: Bool
    let onStar: () -> Void

    static let buttonSize: CGFloat = 44
    /// Gap between the safe area's top and the row, in every player.
    static let topPadding: CGFloat = 8
    /// The row's bottom edge, measured from the safe area's top.
    static let bottom: CGFloat = topPadding + buttonSize
    /// Where a tool rail under the star starts.
    static let railTop: CGFloat = buttonSize + 10
    /// Side inset of the tool rail: its fold button and capsule share the
    /// rail's edge margin, about centred under the star.
    static let railInset: CGFloat = PlayerToolRail.edgeMargin

    var body: some View {
        HStack {
            // A capsule as tall as the star's circle, so the row's two
            // buttons read as one family.
            Button(leadingTitle, action: onLeading)
                .buttonStyle(PlayerChromeCapsuleButtonStyle())
            .accessibilityLabel(leadingAccessibilityLabel)
            .accessibilityIdentifier("review-leading")

            Spacer(minLength: 8)

            if let counter {
                Text(counter)
                    .font(.appLabel.monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                    .accessibilityIdentifier("swing-position")
                    .accessibilityValue(counterValue)
            }

            Spacer(minLength: 8)

            Button(action: onStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isStarred ? Color.yellow : Color.white)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .playerChromeBackground(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStarred ? "Remove star" : "Star swing")
        }
    }

    /// The swing's number in the order the swings were hit, oldest first.
    static func counter<Item>(for id: UUID, in swings: [Item], id key: (Item) -> UUID, date: (Item) -> Date) -> String? {
        guard swings.count > 1 else { return nil }
        let ordered = swings.sorted { date($0) < date($1) }
        guard let index = ordered.firstIndex(where: { key($0) == id }) else { return nil }
        return "Swing \(index + 1) of \(swings.count)"
    }
}
