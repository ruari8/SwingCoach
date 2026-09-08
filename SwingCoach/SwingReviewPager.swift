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

extension EnvironmentValues {
    var reviewPlaybackControlsPlacement: ReviewPlaybackControlsPlacement {
        get { self[ReviewPlaybackControlsPlacementKey.self] }
        set { self[ReviewPlaybackControlsPlacementKey.self] = newValue }
    }

    var reviewCornerControlsInNavigation: Bool {
        get { self[ReviewCornerControlsInNavigationKey.self] }
        set { self[ReviewCornerControlsInNavigationKey.self] = newValue }
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
