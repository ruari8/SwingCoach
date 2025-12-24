//
//  SwingCoachAPI.swift
//  SwingCoach
//
//  Created by AI Assistant on 24/12/2024.
//

import Foundation
import AVFoundation
import Photos

/// API client for SwingCoach backend
actor SwingCoachAPI {
    
    // MARK: - Configuration
    
    // TODO: Update this to your deployed backend URL
    #if DEBUG
    static let baseURL = "http://192.168.86.21:8000"
    #else
    static let baseURL = "https://your-production-url.com"
    #endif
    
    static let shared = SwingCoachAPI()
    
    private init() {}
    
    // MARK: - API Errors
    
    enum APIError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case serverError(Int, String)
        case decodingError(Error)
        case uploadFailed(String)
        case videoExportFailed(String)
        case noVideoAsset
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            case .uploadFailed(let reason):
                return "Upload failed: \(reason)"
            case .videoExportFailed(let reason):
                return "Video export failed: \(reason)"
            case .noVideoAsset:
                return "Could not load video from Photos library"
            }
        }
    }
    
    // MARK: - Response Models
    
    struct UploadURLResponse: Codable {
        let uploadUrl: String
        let videoKey: String
        
        enum CodingKeys: String, CodingKey {
            case uploadUrl = "upload_url"
            case videoKey = "video_key"
        }
    }
    
    struct AnalyzeRequest: Codable {
        let videoKey: String
        let vantage: String
        
        enum CodingKeys: String, CodingKey {
            case videoKey = "video_key"
            case vantage
        }
    }
    
    struct DrillLinkResponse: Codable {
        let title: String
        let url: String
        let platform: String
    }
    
    struct AnalysisResponse: Codable {
        let summary: String
        let metrics: [String: String]
        let drillLinks: [DrillLinkResponse]
        let rawResponse: String?
        
        enum CodingKeys: String, CodingKey {
            case summary
            case metrics
            case drillLinks = "drill_links"
            case rawResponse = "raw_response"
        }
    }
    
    struct HealthResponse: Codable {
        let status: String
        let r2Configured: Bool
        
        enum CodingKeys: String, CodingKey {
            case status
            case r2Configured = "r2_configured"
        }
    }
    
    // MARK: - API Methods
    
    /// Check if the backend is healthy
    func healthCheck() async throws -> HealthResponse {
        let url = URL(string: "\(Self.baseURL)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "SwingCoach", code: -1))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, "Health check failed")
        }
        
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }
    
    /// Get a pre-signed URL for uploading a video
    func getUploadURL() async throws -> UploadURLResponse {
        let url = URL(string: "\(Self.baseURL)/upload-url")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "SwingCoach", code: -1))
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        return try JSONDecoder().decode(UploadURLResponse.self, from: data)
    }
    
    /// Upload video data to the pre-signed URL
    func uploadVideo(to uploadURL: String, videoData: Data) async throws {
        guard let url = URL(string: uploadURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("\(videoData.count)", forHTTPHeaderField: "Content-Length")
        
        let (_, response) = try await URLSession.shared.upload(for: request, from: videoData)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "SwingCoach", code: -1))
        }
        
        // R2 returns 200 on successful PUT
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.uploadFailed("HTTP \(httpResponse.statusCode)")
        }
    }
    
    /// Request analysis of an uploaded video
    func analyzeSwing(videoKey: String, vantage: Vantage) async throws -> AnalysisResponse {
        let url = URL(string: "\(Self.baseURL)/analyze")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let vantageString = vantage == .dtl ? "DTL" : "FO"
        let requestBody = AnalyzeRequest(videoKey: videoKey, vantage: vantageString)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "SwingCoach", code: -1))
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }
    
    // MARK: - Full Analysis Flow
    
    /// Complete flow: export video → get upload URL → upload → analyze
    /// - Parameters:
    ///   - swing: The saved swing to analyze
    ///   - onProgress: Progress callback with stage description and optional progress (0-1)
    /// - Returns: Analysis result
    func analyzeSwing(
        _ swing: SavedSwing,
        onProgress: @escaping (String, Float?) -> Void
    ) async throws -> AnalysisResponse {
        
        // 1. Export video from Photos to temp MP4
        onProgress("Preparing video...", nil)
        let videoData = try await exportVideoToMP4(photoAssetID: swing.photoAssetID)
        
        // 2. Get upload URL
        onProgress("Connecting to server...", nil)
        let uploadInfo = try await getUploadURL()
        
        // 3. Upload to R2
        onProgress("Uploading video...", 0.0)
        try await uploadVideo(to: uploadInfo.uploadUrl, videoData: videoData)
        onProgress("Uploading video...", 1.0)
        
        // 4. Request analysis
        onProgress("Analyzing swing...", nil)
        let result = try await analyzeSwing(videoKey: uploadInfo.videoKey, vantage: swing.vantage)
        
        return result
    }
    
    // MARK: - Video Export
    
    /// Export a video from Photos library to MP4 data
    private func exportVideoToMP4(photoAssetID: String) async throws -> Data {
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photoAssetID], options: nil)
        
        guard let asset = fetchResult.firstObject else {
            throw APIError.noVideoAsset
        }
        
        // Get AVAsset from PHAsset
        let avAsset = try await getAVAsset(from: asset)
        
        // Export to temp file as MP4
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: avAsset,
            presetName: AVAssetExportPresetMediumQuality  // Good balance of quality/size for upload
        ) else {
            throw APIError.videoExportFailed("Could not create export session")
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Export
        await exportSession.export()
        
        if let error = exportSession.error {
            throw APIError.videoExportFailed(error.localizedDescription)
        }
        
        guard exportSession.status == .completed else {
            throw APIError.videoExportFailed("Export did not complete")
        }
        
        // Read exported file into Data
        let videoData = try Data(contentsOf: tempURL)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        
        return videoData
    }
    
    /// Get AVAsset from PHAsset
    private func getAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // Allow iCloud downloads
            
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: APIError.videoExportFailed(error.localizedDescription))
                } else if let avAsset = avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: APIError.noVideoAsset)
                }
            }
        }
    }
}
