import AVFoundation
import CoreGraphics

enum VideoDisplayGeometry {
    static func aspectRatio(for asset: AVAsset) async throws -> Double? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displayed = CGRect(origin: .zero, size: size).applying(transform)
        let width = abs(displayed.width)
        let height = abs(displayed.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return Double(width / height)
    }

    static func contentRect(in size: CGSize, aspectRatio: Double) -> CGRect {
        let aspect = CGFloat(aspectRatio)
        if size.width / max(size.height, 1) > aspect {
            let width = size.height * aspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / aspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    /// How far the video rises at a walkthrough stop so the part that
    /// matters clears the panel under it. `wanted` is the rise that clears
    /// the panel; `focusTop` (the part's top) and `topRowBottom` are
    /// heights on screen before the rise; `blackBand` is the black between
    /// the safe area's top and a letterboxed clip. The part keeps
    /// `stopHeadroom` under the top row. A clip with black above it may
    /// give that headroom up, by no more than the band, since the band
    /// goes under the row before any picture does. The part's top never
    /// goes under the row, and the rise never passes `most`.
    static func stopLift(wanted: CGFloat, focusTop: CGFloat, topRowBottom: CGFloat,
                         blackBand: CGFloat, most: CGFloat) -> CGFloat {
        let toRow = max(0, focusTop - topRowBottom)
        let withHeadroom = max(0, toRow - stopHeadroom)
        return max(0, min(wanted, max(withHeadroom, min(blackBand, toRow)), most))
    }

    /// Kept between the top row and the part that matters at a stop.
    static let stopHeadroom: CGFloat = 36
}
