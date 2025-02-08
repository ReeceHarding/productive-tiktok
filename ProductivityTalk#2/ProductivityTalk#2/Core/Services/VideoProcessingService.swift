import Foundation
import AVFoundation
import UIKit
import FirebaseStorage

actor VideoProcessingService {
    static let shared = VideoProcessingService()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Video Processing Pipeline
    func processAndUploadVideo(sourceURL: URL) async throws -> (videoURL: String, thumbnailURL: String) {
        print("🎥 Starting video processing pipeline")
        
        // Step 1: Process video (crop and compress)
        print("✂️ Starting video cropping and compression")
        let processedVideoURL = try await cropAndCompressVideo(sourceURL: sourceURL)
        print("✅ Video processing completed: \(processedVideoURL.path)")
        
        // Step 2: Generate thumbnail
        print("🖼️ Generating thumbnail")
        let thumbnailURL = try await generateThumbnail(from: processedVideoURL)
        print("✅ Thumbnail generated: \(thumbnailURL.path)")
        
        // Step 3: Upload to Firebase
        print("☁️ Starting Firebase upload")
        let (videoDownloadURL, thumbnailDownloadURL) = try await uploadToFirebase(
            videoURL: processedVideoURL,
            thumbnailURL: thumbnailURL
        )
        print("✅ Upload completed")
        
        // Step 4: Cleanup temporary files
        try? FileManager.default.removeItem(at: processedVideoURL)
        try? FileManager.default.removeItem(at: thumbnailURL)
        
        return (videoDownloadURL, thumbnailDownloadURL)
    }
    
    // MARK: - Video Processing
    private func cropAndCompressVideo(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        
        // Get video dimensions
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else {
            throw NSError(domain: "VideoProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get video dimensions"])
        }
        
        print("📐 Original video dimensions: \(size)")
        
        // Calculate 9:16 crop rect
        let targetAspectRatio: CGFloat = 9.0 / 16.0
        let cropRect: CGRect
        
        if size.width / size.height > targetAspectRatio {
            // Video is too wide - crop sides
            let newWidth = size.height * targetAspectRatio
            let x = (size.width - newWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: newWidth, height: size.height)
        } else {
            // Video is too tall - crop top/bottom
            let newHeight = size.width / targetAspectRatio
            let y = (size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: size.width, height: newHeight)
        }
        
        print("✂️ Applying crop rect: \(cropRect)")
        
        // Create composition
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            let transform = CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
            let transformedImage = source.transformed(by: transform)
            let croppedImage = transformedImage.cropped(to: CGRect(origin: .zero, size: cropRect.size))
            request.finish(with: croppedImage, context: nil)
        }
        
        // Setup export session
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        )
        
        guard let exportSession = exportSession else {
            throw NSError(domain: "VideoProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }
        
        // Configure export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = composition
        
        // Export with progress logging
        print("🔄 Starting video export")
        
        // Use the new async/await API for export
        try await exportSession.export(to: outputURL, as: .mp4)
        print("✅ Video export completed")
        
        return outputURL
    }
    
    // MARK: - Thumbnail Generation
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Generate thumbnail from first frame
        let cgImage = try await imageGenerator.image(at: .zero).image
        
        // Convert to JPEG data
        guard let thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "VideoProcessing", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not generate thumbnail"])
        }
        
        // Save to temporary file
        let thumbnailURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        
        try thumbnailData.write(to: thumbnailURL)
        return thumbnailURL
    }
    
    // MARK: - Firebase Upload
    private func uploadToFirebase(videoURL: URL, thumbnailURL: URL) async throws -> (String, String) {
        async let videoTask = uploadFile(videoURL, to: "videos")
        async let thumbnailTask = uploadFile(thumbnailURL, to: "thumbnails")
        
        return try await (videoTask, thumbnailTask)
    }
    
    private func uploadFile(_ fileURL: URL, to path: String) async throws -> String {
        let filename = "\(UUID().uuidString)_\(fileURL.lastPathComponent)"
        let storageRef = storage.reference().child("\(path)/\(filename)")
        
        print("📤 Starting upload to Firebase: \(filename)")
        
        let metadata = StorageMetadata()
        metadata.contentType = path == "videos" ? "video/mp4" : "image/jpeg"
        
        _ = try await storageRef.putFileAsync(from: fileURL, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        print("✅ Upload completed: \(downloadURL.absoluteString)")
        return downloadURL.absoluteString
    }
} 