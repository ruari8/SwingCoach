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
}
