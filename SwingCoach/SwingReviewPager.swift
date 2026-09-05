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
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
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
