//
//  Theme.swift
//  SwingCoach
//
//  The shared look: the one accent colour, the player's chrome over video,
//  the style every sheet over the player uses, the Library grid, the
//  capsule buttons, the position and low-confidence tags, and a wrapping
//  layout.
//  The red / amber / green level colours are `Color.coachingLevel` and
//  mean coaching status only.
//

import Combine
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

// MARK: - Type ramp

/// The app's one type ramp: three sizes, each a Dynamic Type text style so
/// large text keeps working. A screen uses these and nothing else, apart
/// from the fixed sizes in `FixedType`. Bold is for headings (titles, and
/// a summary's count at the same size), semibold for labels (a row's name, a button, a caption that
/// names something); numbers in rows and badges add `.monospacedDigit()`.
extension Font {
    /// A card's or a group's title, a finding: title 3, bold.
    static let appTitle = Font.title3.weight(.bold)
    /// Sentences, rows and values: subheadline.
    static let appBody = Font.subheadline
    /// A row's name, a button's label: subheadline, semibold.
    static let appLabel = Font.subheadline.weight(.semibold)
    /// Help, footnotes, keys and captions: caption.
    static let appCaption = Font.caption
    /// A caption that names something (a column head, "Start here", a
    /// tag): caption, semibold.
    static let appCaptionLabel = Font.caption.weight(.semibold)
}

/// Fixed point sizes for chrome inside fixed-size cells, which must not
/// grow with Dynamic Type: the tool rail, the position strip, readouts
/// over the video, Trim's timeline and labels drawn on a frame. Level
/// badges size their glyphs to the badge. Everything else uses the ramp.
enum FixedType {
    /// The smallest text anywhere: nothing is drawn, or shrinks to fit,
    /// below 11 points.
    static let minimumSize: CGFloat = 11

    /// The scale factor that lets text `size` points tall shrink to fit
    /// down to the floor and no further.
    static func minimumScale(of size: CGFloat) -> CGFloat {
        min(1, minimumSize / size)
    }

    /// The tool rail's captions and the timeline's ticks: 11 points, with
    /// `PlayerToolRail.captionInset` either side, so "Positions" never
    /// touches the rail's edges.
    static let railCaption = Font.system(size: 11, weight: .semibold)
    /// A label inside a fixed cell: the strip's "P3", "¼ speed", Trim's
    /// detector line.
    static let cellLabel = Font.system(size: 11, weight: .semibold)
    /// A tag or readout over the video: the scrub badge, the time beside
    /// the transport, Trim's timecodes, a label drawn on a frame.
    static let readoutSize: CGFloat = 12
    static let readout = Font.system(size: readoutSize, weight: .semibold)
    /// A second readout line in a slot too narrow for the readout: the
    /// transport row's "Low confidence" under the position's name, so the
    /// two stay two lines. At the floor size, condensed, never shrunk;
    /// `readoutTightest` is the compressed width for the narrowest phones.
    static let readoutTight = Font.system(size: minimumSize, weight: .semibold).width(.condensed)
    static let readoutTightest = Font.system(size: minimumSize, weight: .semibold).width(.compressed)
    /// The rail's names shown beside it, and the drawing tool's buttons.
    static let railLabel = Font.system(size: 14, weight: .semibold)
    /// A position's name on the pose strip ("P3"): the rail labels' size,
    /// a step over the readouts, so it reads from the tripod under the pose.
    static let stripLabel = Font.system(size: 14, weight: .semibold)
}

// MARK: - Help text

extension Color {
    /// Secondary text: footers, help, captions and footnotes on Library,
    /// Settings, the session review and the sheets. The system's secondary
    /// label is about 3.3:1 on grouped grey in light appearance; this is
    /// 6.2:1 on grouped grey and 6.9:1 on white, so a thin caption at 12
    /// points still clears 4.5:1 once antialiased, and 6.2:1 or more on
    /// the dark grouped backgrounds (5.1:1 on an elevated sheet's rows).
    /// Lighter than `sectionHeading`, so a heading still leads.
    static let helpText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.612, green: 0.612, blue: 0.635, alpha: 1)
            : UIColor(red: 0.353, green: 0.353, blue: 0.373, alpha: 1)
    })
}

// MARK: - Help footers

/// A section's help under a list group, as short paragraphs in
/// `Color.helpText`. No paragraph runs past three lines on an iPhone;
/// Settings' footers are one short line each.
struct HelpFooter: View {
    let paragraphs: [String]

    init(_ paragraphs: String...) {
        self.paragraphs = paragraphs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paragraphs, id: \.self) { Text($0) }
        }
        .foregroundStyle(Color.helpText)
    }
}

// MARK: - Section headings

extension Color {
    /// Every list section's heading ("What kept happening", "Coaching").
    /// The system's header grey is about 3.3:1 on grouped grey in light
    /// appearance; this is 9.5:1 there and 10:1 or more on the dark
    /// grouped backgrounds (8:1 on an elevated sheet's).
    static let sectionHeading = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.8, green: 0.8, blue: 0.82, alpha: 1)
            : UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 1)
    })
}

/// A list section's heading in `Color.sectionHeading`; use it for every
/// `Section` header so they all read the same.
struct SectionHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title).foregroundStyle(Color.sectionHeading)
    }
}

// MARK: - Coaching levels

/// The one severity system: a level's colour, its word, its badge glyph
/// and its text ink come from here and nowhere else, so a badge, a pill
/// and a drawing never disagree. In zone is green "In zone" and a tick;
/// one to three steps out is amber "A little out" and "!"; `wellOutFrom`
/// steps or more is red "Well out" and "!!". The numbers ("N steps out")
/// are said only in All checks' rows.
enum CoachingSeverity: Equatable {
    case inZone, littleOut, wellOut

    /// Where amber turns red: the one threshold.
    static let wellOutFrom = 4

    init(level: Int) {
        let steps = abs(level)
        self = steps == 0 ? .inZone : steps < Self.wellOutFrom ? .littleOut : .wellOut
    }

    /// The word beside a badge: "In zone", "A little out", "Well out".
    var word: String {
        switch self {
        case .inZone: "In zone"
        case .littleOut: "A little out"
        case .wellOut: "Well out"
        }
    }

    /// The level badge's glyph out of zone (`CoachingLevelBadge`, every
    /// verdict badge): one "!" a little out, "!!" well out, so amber and
    /// red differ by shape as well as colour. Nil in zone (a tick).
    var markSymbol: String? {
        switch self {
        case .inZone: nil
        case .littleOut: "exclamationmark"
        case .wellOut: "exclamationmark.2"
        }
    }

    /// The word mid-sentence, after "Typically": "typically well out".
    var lowercasedWord: String { word.prefix(1).lowercased() + word.dropFirst() }

    /// The level's colour: green, amber, red.
    var colour: Color {
        switch self {
        case .inZone: Color(red: 0.24, green: 0.86, blue: 0.43)
        case .littleOut: Color(red: 1.0, green: 0.75, blue: 0.16)
        case .wellOut: Color(red: 1.0, green: 0.33, blue: 0.27)
        }
    }

    /// A darker ink of the same hue for text on light surfaces.
    fileprivate var ink: Color {
        switch self {
        case .inZone: Color(red: 0.084, green: 0.456, blue: 0.198)
        case .littleOut: Color.amberInk
        case .wellOut: Color(red: 0.8, green: 0.066, blue: 0)
        }
    }
}

extension Color {
    /// A level's colour: its `CoachingSeverity` band's.
    static func coachingLevel(_ level: Int) -> Color {
        CoachingSeverity(level: level).colour
    }

    /// Amber as text on light surfaces: a dark amber, 7:1 on white and
    /// 6:1 or more on an amber pill's pale fill, where the bright amber is
    /// about 1.6:1. The disc and the pill's edge keep the bright amber.
    static let amberInk = Color(red: 0.42, green: 0.27, blue: 0)

    /// The neutral grey of "not judged": a dash badge, a guide, and other
    /// marks that carry no level, so they never read as a colour's meaning.
    static let notJudged = Color(white: 0.5)

    /// A level's colour for text: the level colour itself in dark
    /// appearance, a darker ink of the same hue in light (4.5:1 or more on
    /// white), since the bright amber and green are unreadable as text on
    /// white.
    static func coachingLevelText(_ level: Int) -> Color {
        let severity = CoachingSeverity(level: level)
        let ink = severity.ink, bright = severity.colour
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
    /// The tool rail's and the player buttons' fill: 80% opaque, so the
    /// white captions keep their contrast over bright cloud, sunlit grass
    /// and the bay's divider alike, while the picture still shows through.
    static let fill = Color(white: 0.16).opacity(0.8)
    static let edge = Color.white.opacity(0.2)
    /// The step card, the folded coaching line and other panels over the video.
    static let panel = Color(white: 0.07).opacity(0.9)
    static let panelEdge = Color.white.opacity(0.12)
    static let panelRadius: CGFloat = 20
    /// An opaque dark surface for a card that must read on any camera
    /// picture: the recap and the last swing's verdict on Capture.
    static let solidPanel = Color(white: 0.1)
    static let stateRadius: CGFloat = 16
    /// Inside every solid panel over the camera (the recap, the last
    /// swing's verdict): one inset, so they read as one family.
    static let stateInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    /// Secondary text on the player's dark panels (captions, caveats):
    /// near-white, 11:1 or more on `panel`, so a caveat beside a level's
    /// colour still reads.
    static let secondaryText = Color.white.opacity(0.85)
    /// Background of every sheet over the player: dark and near opaque, so
    /// the card and strip behind never ghost through.
    static let sheetBackground = Color(white: 0.09).opacity(0.97)
    /// The one gap between the bands at the player's bottom: the coaching
    /// card, the scrubber, the transport row and the pose strip.
    static let bandGap: CGFloat = 8
}

/// Sheets' lists: the margin above a sheet's first card, instead of the
/// grouped list's taller default band. With the list's own section inset
/// the first card starts about 14 points under the title bar.
enum SheetLayout {
    static let contentTop: CGFloat = 8
    /// Under a sheet's last row: more than the sheet's corner radius, so
    /// the corner never cuts a row when the list is scrolled to its end.
    static let contentBottom: CGFloat = 48
    /// Under the last row of a sheet sized to its content (Layers), over
    /// the home indicator's band: a little air, since nothing scrolls.
    static let fittedBottom: CGFloat = 12
}

extension View {
    /// A sheet's list starts `SheetLayout.contentTop` under its title bar.
    func sheetContentTop() -> some View {
        contentMargins(.top, SheetLayout.contentTop, for: .scrollContent)
    }

    /// A solid panel over the camera: `PlayerChrome.solidPanel` at the
    /// state radius, with the state insets.
    func solidPanelBackground() -> some View {
        padding(PlayerChrome.stateInsets)
            .background(RoundedRectangle(cornerRadius: PlayerChrome.stateRadius).fill(PlayerChrome.solidPanel))
            .overlay(RoundedRectangle(cornerRadius: PlayerChrome.stateRadius).strokeBorder(PlayerChrome.panelEdge, lineWidth: 0.5))
    }
}

extension View {
    /// A player button's background in `shape`.
    func playerChromeBackground<S: InsettableShape>(_ shape: S) -> some View {
        background(shape.fill(PlayerChrome.fill))
            .overlay(shape.strokeBorder(PlayerChrome.edge, lineWidth: 1))
    }

    /// The one style for sheets over the player (All checks, Layers,
    /// Swing Info): dark, near-opaque, the accent, and room under the
    /// last row so the sheet's corner never clips it. Each sheet carries
    /// its own Done. While one is up the player behind dims the same in
    /// light and dark appearance (`PlayerSheetDim`).
    func playerSheetStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .sheetContentTop()
            .contentMargins(.bottom, SheetLayout.contentBottom, for: .scrollContent)
            .background(PlayerChrome.sheetBackground)
            .presentationBackground(PlayerChrome.sheetBackground)
            .preferredColorScheme(.dark)
            .tint(.appAccent)
            .onAppear { PlayerSheetDim.shared.presented += 1 }
            .onDisappear { PlayerSheetDim.shared.presented = max(0, PlayerSheetDim.shared.presented - 1) }
    }

    /// The player under a sheet: dimmed as in dark appearance whatever the
    /// system appearance. Put it over a player screen's whole stack.
    func playerSheetDimming() -> some View {
        overlay { PlayerSheetDimLayer().ignoresSafeArea() }
    }
}

/// How many sheets over the player are up. The system dims what is behind
/// a sheet less in light appearance than in dark, so the player, dark by
/// design, adds the difference itself.
@MainActor
final class PlayerSheetDim: ObservableObject {
    static let shared = PlayerSheetDim()
    @Published var presented = 0

    /// Added under the system's own dimming in light appearance, so the
    /// two together match dark appearance's (about half the light).
    static let lightExtra = Color.black.opacity(0.35)
}

private struct PlayerSheetDimLayer: View {
    @ObservedObject private var dim = PlayerSheetDim.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (dim.presented > 0 && colorScheme == .light ? PlayerSheetDim.lightExtra : Color.clear)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.3), value: dim.presented > 0)
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

// MARK: - Library grid

/// The Library's grid, as in Photos: square tiles with hairline gutters,
/// pinched between a few column counts.
nonisolated enum LibraryGrid {
    /// Between tiles, across and down.
    static let gutter: CGFloat = 2
    /// Under each group's tiles, before the next group's header.
    static let sectionGap: CGFloat = 14
    /// The column counts a pinch steps between, fewest first.
    static let columnChoices = [2, 3, 5]
    static let defaultColumns = 3
    /// The remembered column count, in user defaults.
    static let columnsKey = "library.gridColumns"
    /// The biggest a tile gets: two columns on the widest iPhone (440
    /// points). A tile's picture is made at the tile's own size times
    /// the screen scale, and never above this (`LibraryTilePictures`).
    static let largestTile: CGFloat = 220
    /// After a pinch last moves or ends, how long tiles ignore taps: a
    /// finger lifting from the pinch must not open or select the tile
    /// under it.
    static let pinchTapCooldown: TimeInterval = 0.3
    /// Where a portrait clip's square thumbnail is cut, from 0 (its top)
    /// to 1 (its bottom): above the middle, so a down-the-line golfer's
    /// head and body show rather than the feet and the mat.
    static let thumbnailFocus: CGFloat = 0.38

    static func validColumns(_ columns: Int) -> Int {
        columnChoices.contains(columns) ? columns : defaultColumns
    }

    /// One step bigger (fewer columns), or the same at the biggest.
    static func fewerColumns(than columns: Int) -> Int {
        columnChoices.last { $0 < columns } ?? columnChoices.first!
    }

    /// One step smaller (more columns), or the same at the smallest.
    static func moreColumns(than columns: Int) -> Int {
        columnChoices.first { $0 > columns } ?? columnChoices.last!
    }
}

// MARK: - Capture controls

/// Capture's controls (the Auto / Manual switch, the saved count): every
/// control is at least 44 points tall, since it is tapped from a step
/// away while the phone sits on a tripod.
enum CaptureControl {
    static let height: CGFloat = 44
    /// The switch's titles: subheadline, one step under body. Capped at
    /// its default size, since the switch keeps one width (`modeWidth`).
    static var modeFont: UIFont {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: modeFontSize), maximumPointSize: modeFontSize)
    }
    static let modeFontSize: CGFloat = 15
    /// The Auto / Manual switch's width, two equal segments.
    static let modeWidth: CGFloat = 168
    /// A menu chip over the camera (the frame rate, the coach's cadence):
    /// drawn this tall, 44 to tap.
    static let chipHeight: CGFloat = 36
    /// Inside a chip, each side: tight enough that the frame rate and
    /// "Recap: 10" share the top row with the Auto / Manual switch.
    static let chipPadding: CGFloat = 10
    /// Between the chips in the top row, and the least between them and
    /// the switch.
    static let chipGap: CGFloat = 6
    /// Capture's controls from the screen's sides: room for the frame
    /// rate, "Recap: 10" and the switch in one row on a 402-point phone.
    static let edgeMargin: CGFloat = 16
}

extension View {
    /// A menu's label over the camera (the frame rate, the coach's
    /// cadence): a dark capsule with a hairline edge, so its white text
    /// holds up over bright sky like the Auto / Manual switch beside it.
    /// Its value alone ("240 fps", "Recap: 5"), no chevron, so both chips
    /// fit the top row beside the switch. Drawn
    /// `CaptureControl.chipHeight` tall, 44 to tap.
    func captureChip() -> some View {
        padding(.horizontal, CaptureControl.chipPadding)
            .frame(minHeight: CaptureControl.chipHeight)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .minimumHitArea(visible: CGSize(width: HitArea.minimum, height: CaptureControl.chipHeight))
    }
}

// MARK: - Coaching previews

enum CoachingPreview {
    /// Width over height of a comparison tile: shorter than a portrait
    /// clip, which the tile cuts toward the golfer and club, so its sky
    /// and foreground don't push the other swings off screen.
    static let compareAspect: CGFloat = 4.0 / 5.0
    /// The recap card's picture over the camera: as tall as the card,
    /// cut toward the golfer and club, wide enough to read from the
    /// tripod, with that swing's own badge on its corner.
    static let recapPictureWidth: CGFloat = 96
    static let recapPictureMinHeight: CGFloat = 120
    /// The session review's two pictures of its lead theme: the same
    /// golfer-centred 4:5 region on both (`CoachingFrameView.golferRegion`),
    /// so the drawing is large and the sky and turf are cut away.
    static let golferAspect: CGFloat = 4.0 / 5.0
}

// MARK: - Capsule buttons

/// The pair of capsule buttons on a header (Select all beside Review):
/// one height, so the two read as a pair.
enum CapsuleButton {
    static let height: CGFloat = 32
    /// The capsule plus the space above and below it: 44 points to tap.
    static let tapPadding: CGFloat = 6
}

/// A secondary action beside a primary one ("Select all 12" beside
/// Review): a neutral filled capsule with a hairline edge, so it reads as
/// a button, never as grey metadata, without competing with the primary
/// one. 44 points to tap.
struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appLabel)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: CapsuleButton.height)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .padding(.vertical, CapsuleButton.tapPadding)
            .contentShape(Rectangle())
    }
}

/// The primary action on a header (Review): the accent fill, the same
/// height as `SecondaryCapsuleButtonStyle` beside it.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appLabel)
            .foregroundStyle(Color.onAccent)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: CapsuleButton.height)
            .background(Capsule().fill(Color.appAccent))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .padding(.vertical, CapsuleButton.tapPadding)
            .contentShape(Rectangle())
    }
}

// MARK: - Hit areas

/// Every control is at least 44 points to tap, whatever it looks like.
enum HitArea {
    static let minimum: CGFloat = 44
}

extension View {
    /// In a UI test, an element the test can find by `identifier` to read
    /// this view's frame on screen. Nothing outside UI tests: VoiceOver
    /// gets no extra stop.
    @ViewBuilder
    func uiTestFrameProbe(_ identifier: String) -> some View {
        #if DEBUG
        if UITestFixture.isActive {
            accessibilityElement(children: .ignore)
                .accessibilityIdentifier(identifier)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Grows the tappable area to `HitArea.minimum` around a control drawn
    /// `visible` big, without changing the layout around it.
    func minimumHitArea(visible: CGSize) -> some View {
        let dx = max(0, (HitArea.minimum - visible.width) / 2)
        let dy = max(0, (HitArea.minimum - visible.height) / 2)
        return padding(.horizontal, dx)
            .padding(.vertical, dy)
            .contentShape(Rectangle())
            .padding(.horizontal, -dx)
            .padding(.vertical, -dy)
    }
}

/// A secondary action on a dark panel over the video (the step card's
/// All checks): an outlined capsule drawn 28 points tall, 44 to tap.
struct PanelCapsuleButtonStyle: ButtonStyle {
    static let height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appLabel)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: Self.height)
            .background(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .minimumHitArea(visible: CGSize(width: HitArea.minimum, height: Self.height))
    }
}

/// A full button on a dark panel over the video or the camera (the step
/// card's Back, Play swing and Next, the recap's Compare, Try again): a
/// rounded slab the 44-point minimum tall. The card's one primary action
/// (Next, or Play swing on the last step, All checks on a picked check,
/// Look on the last swing's verdict) is `prominent`: the lime accent with
/// a dark label, like Review and Auto ready; the rest are a quiet
/// translucent grey with a white label, so the finding above, not a
/// white slab, is what the eye lands on.
struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    /// Fills the row's width, shared with the buttons beside it; off for
    /// a square icon button or one sized to its label.
    var fills = true

    static let height: CGFloat = HitArea.minimum
    static let radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appLabel)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, fills ? 0 : 16)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: Self.height)
            .background(RoundedRectangle(cornerRadius: Self.radius)
                .fill(prominent ? Color.accentLime : Color.white.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Self.radius))
    }
}

/// Closes a card over the camera (the recap): an xmark in a 28-point
/// circle, 44 to tap, without making the card's row taller.
struct CloseButtonStyle: ButtonStyle {
    static let size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .minimumHitArea(visible: CGSize(width: Self.size, height: Self.size))
    }
}

/// A button over the video (the player's Done and Back): a capsule with
/// the player chrome's fill and edge, as tall as the star beside it.
struct PlayerChromeCapsuleButtonStyle: ButtonStyle {
    static let height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appLabel)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minWidth: Self.height, minHeight: Self.height)
            .playerChromeBackground(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Mode switch

/// A segmented switch with its own font and white titles over the camera
/// (Capture's Auto / Manual); its chosen segment can fill with the accent
/// (dark text on lime). It stays a system segmented control, so VoiceOver and Voice Control
/// read it as one.
struct AccentSegmentedControl: UIViewRepresentable {
    let titles: [String]
    @Binding var selectedIndex: Int
    /// Fill the chosen segment with the accent.
    var accentsSelection: Bool
    var identifier: String
    var font: UIFont = .preferredFont(forTextStyle: .callout)

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.accessibilityIdentifier = identifier
        control.addAction(UIAction { [binding = $selectedIndex] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            binding.wrappedValue = control.selectedSegmentIndex
        }, for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        for (index, title) in titles.enumerated() where control.titleForSegment(at: index) != title {
            control.setTitle(title, forSegmentAt: index)
        }
        if control.selectedSegmentIndex != selectedIndex {
            control.selectedSegmentIndex = selectedIndex
        }
        let chosen = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        control.selectedSegmentTintColor = accentsSelection ? UIColor(Color.accentLime) : nil
        control.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.white], for: .normal)
        control.setTitleTextAttributes([.font: chosen,
                                        .foregroundColor: accentsSelection ? UIColor.black : UIColor.white],
                                       for: .selected)
    }
}

// MARK: - Position tags

/// A swing position named in a list or a heading, e.g. "P5": a neutral
/// capsule, never a level's colour, so it does not read as a level.
struct PositionTag: View {
    let position: Int

    var body: some View {
        Text("P\(position)")
            .font(.appCaptionLabel.monospacedDigit())
            .foregroundStyle(Color.helpText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}

// MARK: - Low confidence

/// The one mark for a position the model was unsure of: a dashed circle
/// with a question mark, echoing the strip's dashed chip. It sits on the
/// dashed chip, beside "low confidence" by the time and in Swing Info's
/// Low tag, so the dashes mean the same thing wherever they appear.
enum LowConfidenceGlyph {
    static let symbol = "questionmark.circle.dashed"
    /// The glyph inline in text, at the text's size.
    static var image: Image { Image(systemName: symbol) }
    /// On a strip chip: a fixed size, so it never grows past its cell.
    static let chipSize: CGFloat = 10
    static let chipDisc: CGFloat = 14
}

/// A position the model was unsure of, as one reading with its
/// confidence: the low-confidence glyph, "Low" and the number ("Low ·
/// 50%"), all at the number's size and in the same ink, so the word reads
/// as part of the value rather than a smaller note beside it. The glyph
/// and the word carry it, without a colour that means nothing else.
struct LowConfidenceTag: View {
    /// The confidence as shown in the other rows ("50%").
    let value: String
    var font: Font = .appBody.monospacedDigit()

    var body: some View {
        Text("\(LowConfidenceGlyph.image) Low · \(value)")
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityLabel("\(SwingPosition.lowConfidenceWords), \(value)")
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
