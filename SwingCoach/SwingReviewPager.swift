import SwiftUI

/// Stable, viewport-sized pages. ScrollView owns dragging, cancellation and
/// deceleration; changing selection never rebuilds or rebases the page strip.
struct SwingReviewPager<Page: View>: View {
    let swings: [SavedSwing]
    @Binding var selection: UUID?
    var pagingEnabled = true
    @ViewBuilder let page: (SavedSwing) -> Page
    @State private var scrollID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(swings) { swing in
                        page(swing)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            // Video layers that ignore safe areas must never draw
                            // into their neighbour while either page is moving.
                            .clipped()
                            .allowsHitTesting(swing.id == selection)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("swing-review-page")
                            .accessibilityLabel(swing.title ?? "Swing video")
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
