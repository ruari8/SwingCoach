//
//  Theme.swift
//  SwingCoach
//
//  The shared look: the one accent colour, the player's chrome over video,
//  the style every sheet over the player uses, and a wrapping layout.
//  The red / amber / green level colours are `Color.coachingLevel` and
//  mean coaching status only.
//

import SwiftUI
import UIKit

// MARK: - Accent

extension Color {
    /// The accent on dark surfaces: the player, Capture and the sheets
    /// over the player. Text and icons on it are black.
    static let accentLime = Color(red: 0.847, green: 0.953, blue: 0.416)
    /// The same lime hue as an ink for light surfaces: 5.6:1 on white and
    /// 5:1 on grouped grey, so it passes WCAG AA for text.
    static let accentInk = Color(red: 0.353, green: 0.44, blue: 0)
    /// The app's tint: lime in dark appearance, the ink in light. The
    /// asset catalog's AccentColor holds the same two values.
    static let appAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(Color.accentLime) : UIColor(Color.accentInk)
    })
    /// Text and icons on an `appAccent` fill: black on lime, white on the ink.
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
}

// MARK: - Level colours as text

extension Color {
    /// A level's colour for text: the level colour itself in dark
    /// appearance, a darker ink of the same hue in light (4.5:1 or more on
    /// white), since the bright amber and green are unreadable as text on
    /// white.
    static func coachingLevelText(_ level: Int) -> Color {
        let ink: Color = switch abs(level) {
        case 0: Color(red: 0.084, green: 0.456, blue: 0.198)
        case 1...3: Color(red: 0.54, green: 0.379, blue: 0)
        default: Color(red: 0.8, green: 0.066, blue: 0)
        }
        let bright = Color.coachingLevel(level)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(bright) : UIColor(ink)
        })
    }
}

// MARK: - Player chrome

/// Buttons over the video. The fill and edge show on sky and grass and
/// on the black around a letterboxed clip, so a button never looks cut
/// off where the video ends.
enum PlayerChrome {
    static let fill = Color(white: 0.16).opacity(0.62)
    static let edge = Color.white.opacity(0.2)
    /// The step card, the folded coaching line and other panels over the video.
    static let panel = Color(white: 0.07).opacity(0.9)
    static let panelEdge = Color.white.opacity(0.12)
    static let panelRadius: CGFloat = 20
    /// Background of every sheet over the player: dark and near opaque, so
    /// the card and strip behind never ghost through.
    static let sheetBackground = Color(white: 0.09).opacity(0.97)
}

extension View {
    /// A player button's background in `shape`.
    func playerChromeBackground<S: InsettableShape>(_ shape: S) -> some View {
        background(shape.fill(PlayerChrome.fill))
            .overlay(shape.strokeBorder(PlayerChrome.edge, lineWidth: 1))
    }

    /// The one style for sheets over the player (All checks, Drawings,
    /// Swing Info): dark, near-opaque, the accent, and room under the
    /// last row so the sheet's corner never clips it. Each sheet carries
    /// its own Done.
    func playerSheetStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .background(PlayerChrome.sheetBackground)
            .presentationBackground(PlayerChrome.sheetBackground)
            .preferredColorScheme(.dark)
            .tint(.appAccent)
    }
}

extension View {
    /// A navigation bar that gets a background of its own once content
    /// scrolls under it, so its title and buttons never sit on the content.
    @ViewBuilder
    func hardTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.hard, for: .top)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Library cards

enum LibraryCard {
    /// The swing card and its thumbnail.
    static let radius: CGFloat = 12
    static let thumbnailRadius: CGFloat = 8
    /// A card's surface in light and dark, so captions never float on the
    /// page.
    static let fill = Color(.secondarySystemGroupedBackground)
}

// MARK: - Position tags

/// A swing position named in a list or a heading, e.g. "P5": a neutral
/// capsule, never a level's colour, so it does not read as a level.
struct PositionTag: View {
    let position: Int

    var body: some View {
        Text("P\(position)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}

// MARK: - Wrapping layout

/// Lays children left to right and wraps to a new line when a row is
/// full, keeping their order.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let added = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if added > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = added
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
