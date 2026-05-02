//
//  TrimVideoSource.swift
//  SwingCoach
//
//  Created by AI Assistant on 21/03/2026.
//

import AVFoundation
import Photos

struct TrimVideoSource: Identifiable {
    enum SourceError: Error, LocalizedError {
        case missingAsset

        var errorDescription: String? {
            switch self {
            case .missingAsset:
                return "The selected video is no longer available."
            }
        }
    }

    let cacheKey: String
    let durationHint: CMTime?
    let cleanupURL: URL?
    let existingPhotoAssetID: String?

    var id: String { cacheKey }

    private let previewAssetLoader: () async throws -> AVAsset
    private let exportAssetLoader: () async throws -> AVAsset

    init(
        cacheKey: String,
        durationHint: CMTime? = nil,
        cleanupURL: URL? = nil,
        existingPhotoAssetID: String? = nil,
        previewAssetLoader: @escaping () async throws -> AVAsset,
        exportAssetLoader: @escaping () async throws -> AVAsset
    ) {
        self.cacheKey = cacheKey
        self.durationHint = durationHint
        self.cleanupURL = cleanupURL
        self.existingPhotoAssetID = existingPhotoAssetID
        self.previewAssetLoader = previewAssetLoader
        self.exportAssetLoader = exportAssetLoader
    }

    func loadPreviewAsset() async throws -> AVAsset {
        try await previewAssetLoader()
    }

    func loadExportAsset() async throws -> AVAsset {
        try await exportAssetLoader()
    }

    static func localFile(url: URL) -> TrimVideoSource {
        let asset = AVURLAsset(url: url)
        return TrimVideoSource(
            cacheKey: url.path,
            cleanupURL: url,
            previewAssetLoader: { asset },
            exportAssetLoader: { asset }
        )
    }

    static func capturedFile(url: URL) -> TrimVideoSource {
        let asset = AVURLAsset(url: url)
        return TrimVideoSource(
            cacheKey: url.path,
            cleanupURL: url,
            previewAssetLoader: { asset },
            exportAssetLoader: { asset }
        )
    }

    static func externalFile(url: URL) -> TrimVideoSource {
        let asset = AVURLAsset(url: url)
        return TrimVideoSource(
            cacheKey: url.absoluteString,
            previewAssetLoader: { asset },
            exportAssetLoader: { asset }
        )
    }

    static func photoLibrary(assetIdentifier: String, durationSeconds: Double) -> TrimVideoSource {
        let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
        return TrimVideoSource(
            cacheKey: assetIdentifier,
            durationHint: duration,
            existingPhotoAssetID: assetIdentifier,
            previewAssetLoader: {
                try await requestAsset(
                    assetIdentifier: assetIdentifier,
                    deliveryMode: .fastFormat,
                    version: .current
                )
            },
            exportAssetLoader: {
                try await requestAsset(
                    assetIdentifier: assetIdentifier,
                    deliveryMode: .highQualityFormat,
                    version: .current
                )
            }
        )
    }

    private static func requestAsset(
        assetIdentifier: String,
        deliveryMode: PHVideoRequestOptionsDeliveryMode,
        version: PHVideoRequestOptionsVersion
    ) async throws -> AVAsset {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else {
            throw SourceError.missingAsset
        }

        let options = PHVideoRequestOptions()
        options.version = version
        options.deliveryMode = deliveryMode
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: SourceError.missingAsset)
                }
            }
        }
    }
}
