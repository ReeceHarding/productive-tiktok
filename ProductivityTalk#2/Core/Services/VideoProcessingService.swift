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
    ) async throws -> String {  // Now only returns the video ID
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
        
        // Verify user authentication
        guard let userId = await AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("❌ User not authenticated", component: "Processing")
            throw NSError(domain: "VideoProcessing", 
                         code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        LoggingService.debug("👤 User ID: \(userId)", component: "Processing")
        
        do {
            // Upload to Firebase Storage
            LoggingService.storage("📤 Starting Firebase upload", component: "Upload")
            _ = try await uploadToFirebase(
                fileURL: sourceURL,
                path: "videos",
                filename: "\(videoId).mp4",  // Always use .mp4 extension for consistency
                onProgress: onProgress
            )
            LoggingService.success("✅ Upload completed successfully", component: "Upload")
            
            return videoId  // Return the video ID for tracking
            
        } catch {
            LoggingService.error("❌ Processing failed: \(error.localizedDescription)", component: "Processing")
            throw error
        }
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
        
        // Add user ID to metadata for cloud function
        guard let userId = await AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "VideoProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        metadata.customMetadata = ["userId": userId]
        LoggingService.debug("Added userId \(userId) to storage metadata", component: "Storage")
        
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