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
    func processAndUploadVideo(sourceURL: URL) async throws -> (videoURL: String, thumbnailURL: String) {
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
                filename: "\(videoId).mp4"  // Always use .mp4 extension for consistency
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
                        "processingStatus": VideoProcessingStatus.ready.rawValue,
                        "updatedAt": FieldValue.serverTimestamp()
                    ] as [String: Any])
                
                LoggingService.success("✅ Updated video document with URL and ready status", component: "Processing")
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
    private func uploadToFirebase(fileURL: URL, path: String, filename: String? = nil) async throws -> String {
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
        
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putFile(from: fileURL, metadata: metadata)
            var lastReportedProgress: Int = -1
            
            // Monitor progress more frequently
            uploadTask.observe(.progress) { snapshot in
                let percentComplete = Int(100.0 * Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1))
                if percentComplete != lastReportedProgress {  // Report every change
                    LoggingService.progress("Video upload", progress: Double(percentComplete) / 100.0, id: actualFilename)
                    LoggingService.debug("📊 Upload progress: \(percentComplete)% (\(ByteCountFormatter.string(fromByteCount: snapshot.progress?.completedUnitCount ?? 0, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: snapshot.progress?.totalUnitCount ?? 1, countStyle: .file)))", component: "Storage")
                    lastReportedProgress = percentComplete
                }
            }
            
            // Monitor completion
            uploadTask.observe(.success) { _ in
                LoggingService.success("✅ Upload completed successfully", component: "Storage")
                // Use a detached task to avoid actor reentrancy
                Task.detached {
                    do {
                        let downloadURL = try await storageRef.downloadURL()
                        LoggingService.debug("📍 Download URL: \(downloadURL.absoluteString)", component: "Storage")
                        continuation.resume(returning: downloadURL.absoluteString)
                    } catch {
                        LoggingService.error("❌ Failed to get download URL: \(error)", component: "Storage")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Monitor failure
            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error {
                    LoggingService.error("❌ Upload failed: \(error)", component: "Storage")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
} 