import Foundation
import AVFoundation
import UIKit
import FirebaseStorage
import FirebaseFirestore

actor VideoProcessingService {
    static let shared = VideoProcessingService()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Video Processing Pipeline
    func processAndUploadVideo(
        sourceURL: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (videoURL: String, thumbnailURL: String) {
        LoggingService.video("🎬 Starting video processing pipeline", component: "Processing")
        LoggingService.debug("Source URL: \(sourceURL.path)", component: "Processing")
        
        // Get file size safely with proper optional handling
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            fileSize = Int64(attributes[.size] as? UInt64 ?? 0)
        } catch {
            fileSize = 0
            LoggingService.error("Failed to get file size: \(error.localizedDescription)", component: "Processing")
        }
        LoggingService.debug("File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))", component: "Processing")
        
        // Generate a unique ID for the video
        let videoId = UUID().uuidString
        LoggingService.debug("🆔 Generated video ID: \(videoId)", component: "Processing")
        
        // Create initial Firestore document
        guard let userId = await AuthenticationManager.shared.currentUser?.uid,
              let username = await AuthenticationManager.shared.appUser?.username else {
            LoggingService.error("❌ User not authenticated", component: "Processing")
            throw NSError(domain: "VideoProcessing", 
                         code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        LoggingService.debug("👤 User info - ID: \(userId), Username: \(username)", component: "Processing")
        
        let initialVideo = Video(
            id: videoId,
            ownerId: userId,
            videoURL: "",  // Will be updated after upload
            thumbnailURL: "", // Will be updated after upload
            title: "Processing...",
            tags: [],
            description: "Processing...",
            ownerUsername: username
        )
        
        let firestore = Firestore.firestore()
        
        // Create the document first with uploading status
        do {
            try await firestore
                .collection("videos")
                .document(videoId)
                .setData(initialVideo.toFirestoreData())  // This will automatically set status to .uploading
            LoggingService.success("📝 Created initial video document with uploading status", component: "Processing")
        } catch {
            LoggingService.error("❌ Failed to create initial video document: \(error)", component: "Processing")
            throw error
        }
        
        do {
            // Step 1: Upload to Firebase with progress monitoring
            LoggingService.storage("📤 Starting Firebase upload", component: "Upload")
            let videoDownloadURL = try await uploadToFirebase(
                fileURL: sourceURL,
                path: "videos",
                filename: "\(videoId).mp4",  // Always use .mp4 extension for consistency
                onProgress: onProgress
            )
            LoggingService.success("✅ Upload completed successfully", component: "Upload")
            LoggingService.debug("📍 Video URL: \(videoDownloadURL)", component: "Upload")
            
            // Step 2: Update Firestore document with URL and ready status
            do {
                try await firestore
                    .collection("videos")
                    .document(videoId)
                    .updateData([
                        "videoURL": videoDownloadURL,
                        "thumbnailURL": "",  // No thumbnail needed
                        "updatedAt": FieldValue.serverTimestamp()
                    ] as [String: Any])
                
                LoggingService.success("✅ Updated video document with URL (waiting for Cloud Function processing)", component: "Processing")
            } catch {
                LoggingService.error("❌ Failed to update video document: \(error)", component: "Processing")
                throw error
            }
            
            return (videoDownloadURL, "")
        } catch {
            // Update status to error on failure
            do {
                try await firestore
                    .collection("videos")
                    .document(videoId)
                    .updateData([
                        "processingStatus": VideoProcessingStatus.error.rawValue,
                        "processingError": error.localizedDescription
                    ] as [String: Any])
                
                LoggingService.debug("📝 Updated video status to error", component: "Processing")
            } catch let updateError {
                LoggingService.error("❌ Failed to update error status: \(updateError)", component: "Processing")
            }
            
            LoggingService.error("❌ Processing failed: \(error.localizedDescription)", component: "Processing")
            throw error
        }
    }
    
    // MARK: - Thumbnail Generation
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Configure for high quality
        imageGenerator.maximumSize = CGSize(width: 1080, height: 1920)
        
        // Get thumbnail from first frame
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: NSError(domain: "VideoProcessing", 
                                                        code: -1, 
                                                        userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"]))
                }
            }
        }
        
        // Convert to JPEG
        let uiImage = UIImage(cgImage: cgImage)
        let thumbnailData = uiImage.jpegData(compressionQuality: 0.8)
        
        // Save to temp file
        let thumbnailURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        
        try thumbnailData?.write(to: thumbnailURL)
        LoggingService.success("Generated thumbnail at: \(thumbnailURL.path)", component: "Processing")
        
        return thumbnailURL
    }
    
    // MARK: - Firebase Upload
    private func uploadToFirebase(
        fileURL: URL,
        path: String,
        filename: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        let actualFilename = filename ?? "\(UUID().uuidString).mp4"  // Always use .mp4 extension
        let storageRef = storage.reference().child("\(path)/\(actualFilename)")
        
        LoggingService.storage("📤 Starting upload to path: \(path)/\(actualFilename)", component: "Storage")
        
        // Get file size safely with proper optional handling
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = Int64(attributes[.size] as? UInt64 ?? 0)
        } catch {
            fileSize = 0
            LoggingService.error("Failed to get file size: \(error.localizedDescription)", component: "Storage")
        }
        LoggingService.debug("File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))", component: "Storage")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"  // Always use MP4 content type for videos
        
        // Create upload task
        let uploadTask = storageRef.putFile(from: fileURL, metadata: metadata)
        
        // Setup progress monitoring
        setupUploadProgressMonitoring(uploadTask: uploadTask, filename: actualFilename, onProgress: onProgress)
        
        // Return continuation
        return try await withCheckedThrowingContinuation { continuation in
            uploadTask.observe(.success) { _ in
                Task {
                    do {
                        let downloadURL = try await storageRef.downloadURL()
                        continuation.resume(returning: downloadURL.absoluteString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            uploadTask.observe(.failure) { snapshot in
                continuation.resume(throwing: snapshot.error ?? NSError(domain: "VideoProcessingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))
            }
        }
    }
    
    private func setupUploadProgressMonitoring(
        uploadTask: StorageUploadTask,
        filename: String,
        onProgress: ((Double) -> Void)? = nil
    ) {
        var lastReportedProgress: Int = -1
        
        uploadTask.observe(.progress) { snapshot in
            guard let progress = snapshot.progress else { return }
            
            // Calculate progress
            let completed = Double(progress.completedUnitCount)
            let total = Double(progress.totalUnitCount)
            let percentComplete = Int(100.0 * completed / total)
            
            // Only report if progress has changed
            if percentComplete != lastReportedProgress {
                LoggingService.progress("Video upload", progress: Double(percentComplete) / 100.0, component: filename)
                
                // Format byte counts
                let completedStr = ByteCountFormatter.string(
                    fromByteCount: progress.completedUnitCount,
                    countStyle: .file
                )
                let totalStr = ByteCountFormatter.string(
                    fromByteCount: progress.totalUnitCount,
                    countStyle: .file
                )
                
                LoggingService.debug(
                    "📊 Upload progress: \(percentComplete)% (\(completedStr) / \(totalStr))",
                    component: "Storage"
                )
                
                // Call progress callback
                onProgress?(Double(percentComplete) / 100.0)
                
                lastReportedProgress = percentComplete
            }
        }
    }
} 