import AVFoundation
import Photos
import UIKit

/// A swing's square picture, cut from one frame of its clip: the small
/// placeholder every swing carries (`SavedSwing.thumbnail`) and the
/// sharper one a library tile loads when it comes on screen
/// (`LibraryTilePictures`). Both use the same frame
/// (`SwingLibrary.posterTime`) and the same crop.
nonisolated enum SwingPoster {
    /// A side of the placeholder, in pixels: about 100 KB decoded, so one
    /// for every swing in a large library stays cheap.
    static let placeholderSide: CGFloat = 160

    /// What Photos is asked for when it supplies the placeholder.
    static var placeholderRequestSize: CGSize {
        CGSize(width: placeholderSide, height: placeholderSide)
    }

    /// The square cut from a whole frame, `side` pixels a side and never
    /// scaled up. A landscape frame is cut from its middle; a portrait one
    /// nearer its top (`LibraryGrid.thumbnailFocus`), so the golfer's head
    /// and body show rather than the feet and the mat.
    static func cropped(_ image: UIImage, side: CGFloat) -> UIImage {
        let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard source.width > 0, source.height > 0, side > 0 else { return image }
        let crop = cropRect(in: source)
        let factor = min(1, side / crop.width)
        let output = CGSize(width: (crop.width * factor).rounded(), height: (crop.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * factor, y: -crop.minY * factor,
                                  width: source.width * factor, height: source.height * factor))
        }
    }

    /// The square `cropped` keeps of a frame of `source` pixels.
    static func cropRect(in source: CGSize) -> CGRect {
        let side = min(source.width, source.height)
        if source.width > source.height {
            return CGRect(x: (source.width - side) / 2, y: 0, width: side, height: side)
        }
        return CGRect(x: 0, y: (source.height - side) * LibraryGrid.thumbnailFocus, width: side, height: side)
    }

    /// `cropped`, off the caller's actor.
    @concurrent
    static func croppedOffMain(_ image: UIImage, side: CGFloat) async -> UIImage {
        cropped(image, side: side)
    }

    /// The picture from a clip file, read and cropped off the caller's
    /// actor. The frame is decoded just big enough that a 16:9 clip either
    /// way up still covers the square.
    @concurrent
    static func picture(fromClipAt url: URL, time: Double, side: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let longSide = (side * 16 / 9).rounded(.up)
        generator.maximumSize = CGSize(width: longSide, height: longSide)
        let frameTime = CMTime(seconds: time, preferredTimescale: 600)
        guard let frame = try? await generator.image(at: frameTime) else { return nil }
        return cropped(UIImage(cgImage: frame.image), side: side)
    }

    /// The picture from Photos, for a swing with no copy of its own. Nil
    /// without Photos access; it never asks for it.
    @concurrent
    static func picture(fromPhotosAsset assetID: String, side: CGFloat) async -> UIImage? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard !assetID.isEmpty, status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
        else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One answer, at the size asked for.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return image.map { cropped($0, side: side) }
    }
}

/// The library tiles' pictures: made when a tile comes on screen, at the
/// size the tile is drawn, and kept in a cache with a byte limit, so a
/// large library holds a few screens of them rather than one for every
/// swing. A tile shows the swing's placeholder until its picture arrives.
///
/// The class and its cache entries are nonisolated, with the main actor
/// on the members that need it: the cache frees entries on whatever
/// thread it evicts them, so their deinit must not hop to an actor.
nonisolated final class LibraryTilePictures {
    @MainActor static let shared = LibraryTilePictures()

    /// The most the cached pictures may take, decoded.
    static let byteLimit = 64 * 1024 * 1024

    private nonisolated final class Entry {
        let image: UIImage
        /// The side the picture was made for; the image is smaller when
        /// its clip is.
        let side: CGFloat

        init(image: UIImage, side: CGFloat) {
            self.image = image
            self.side = side
        }
    }

    private nonisolated struct Load {
        let id = UUID()
        let side: CGFloat
        let task: Task<UIImage?, Never>
    }

    private let cache = NSCache<NSString, Entry>()
    /// The cache key last used for each swing, so `forget` finds it.
    @MainActor private var keys: [UUID: NSString] = [:]
    @MainActor private var loads: [NSString: Load] = [:]

    init(byteLimit: Int = LibraryTilePictures.byteLimit) {
        cache.totalCostLimit = byteLimit
    }

    /// A tile's side in pixels: its width at the screen's scale, never
    /// above the largest tile's.
    static func pixelSide(points: CGFloat, scale: CGFloat) -> CGFloat {
        (min(points, LibraryGrid.largestTile) * max(scale, 1)).rounded(.up)
    }

    /// The swing and the frame its picture is read at: a swing whose
    /// positions arrive gets a new key, and so a new picture.
    @MainActor
    static func key(for swing: SavedSwing) -> String {
        "\(swing.id.uuidString)@\(SwingLibrary.posterTime(for: swing))"
    }

    /// The picture already made for this swing, at whatever size.
    @MainActor
    func cached(for swing: SavedSwing) -> UIImage? {
        cache.object(forKey: Self.key(for: swing) as NSString)?.image
    }

    /// The swing's picture at `pixelSide`: the cached one when it is big
    /// enough, else read from the app's copy of the clip, or from Photos
    /// for a swing with no copy. Tiles asking for the same picture share
    /// one read.
    @MainActor
    func picture(for swing: SavedSwing, pixelSide: CGFloat) async -> UIImage? {
        let key = Self.key(for: swing) as NSString
        if let entry = cache.object(forKey: key), entry.side >= pixelSide { return entry.image }
        if let running = loads[key], running.side >= pixelSide { return await running.task.value }

        let time = SwingLibrary.posterTime(for: swing)
        let localURL = SwingLibrary.shared.localVideoURL(for: swing)
        let assetID = swing.photoAssetID
        let load = Load(side: pixelSide, task: Task {
            if let localURL {
                return await SwingPoster.picture(fromClipAt: localURL, time: time, side: pixelSide)
            }
            return await SwingPoster.picture(fromPhotosAsset: assetID, side: pixelSide)
        })
        loads[key] = load
        let image = await load.task.value
        // Forgotten or overtaken by a bigger request while it was read.
        guard loads[key]?.id == load.id else { return nil }
        loads[key] = nil
        guard let image else { return nil }
        store(image, side: pixelSide, for: swing)
        return image
    }

    @MainActor
    func store(_ image: UIImage, side: CGFloat, for swing: SavedSwing) {
        let key = Self.key(for: swing) as NSString
        keys[swing.id] = key
        cache.setObject(Entry(image: image, side: side), forKey: key, cost: Self.bytes(of: image))
    }

    /// Drops a swing's picture: it was deleted, or its poster frame moved.
    @MainActor
    func forget(_ id: UUID) {
        let prefix = id.uuidString
        for key in loads.keys where key.hasPrefix(prefix) {
            loads[key]?.task.cancel()
            loads[key] = nil
        }
        if let key = keys.removeValue(forKey: id) {
            cache.removeObject(forKey: key)
        }
    }

    static func bytes(of image: UIImage) -> Int {
        if let cgImage = image.cgImage { return cgImage.bytesPerRow * cgImage.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }
}
