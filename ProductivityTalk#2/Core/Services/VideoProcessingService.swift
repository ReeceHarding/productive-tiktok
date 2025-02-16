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
    ) async throws -> (videoId: String, videoURL: String, thumbnailURL: String) {
        LoggingService.video("🎬 Starting video processing pipeline", component: "Processing")
        LoggingService.debug("📂 Source URL: \(sourceURL.path)", component: "Processing")
        
        // Get file size safely with proper optional handling
        let fileSize: Int64
        do {
            LoggingService.debug("📊 Checking file size...", component: "Processing")
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            fileSize = Int64(attributes[.size] as? UInt64 ?? 0)
            LoggingService.success("✅ File size retrieved successfully", component: "Processing")
        } catch {
            fileSize = 0
            LoggingService.error("❌ Failed to get file size: \(error.localizedDescription)", component: "Processing")
        }
        LoggingService.debug("📊 File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))", component: "Processing")
        
        // Generate a unique ID for the video
        LoggingService.debug("🔑 Generating video ID from filename: \(sourceURL.lastPathComponent)", component: "Processing")
        let fileName = sourceURL.lastPathComponent
        let videoId = generateVideoId(fileName: fileName)
        LoggingService.success("✅ Generated videoId: \(videoId)", component: "Processing")
        
        // Get user authentication info
        LoggingService.debug("🔐 Checking user authentication...", component: "Processing")
        guard let userId = await AuthenticationManager.shared.currentUser?.uid,
              let username = await AuthenticationManager.shared.appUser?.username else {
            LoggingService.error("❌ User not authenticated - No valid user ID or username", component: "Processing")
            throw NSError(domain: "VideoProcessing", 
                         code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        LoggingService.success("✅ User authenticated - ID: \(userId), Username: \(username)", component: "Processing")
        
        // Create initial video object
        LoggingService.debug("📝 Creating initial video object...", component: "Processing")
        let initialVideo = Video(
            id: videoId,
            ownerId: userId,
            videoURL: "",  // Will be updated after upload
            thumbnailURL: "",  // Will be updated after upload
            title: "Processing...",
            tags: [],
            description: "Processing...",
            ownerUsername: username
        )
        LoggingService.debug("📄 Initial video object created with status: \(initialVideo.processingStatus.rawValue)", component: "Processing")
        
        // Initialize Firestore
        LoggingService.debug("🔥 Initializing Firestore connection...", component: "Processing")
        let firestore = Firestore.firestore()
        
        // Create initial document
        LoggingService.debug("📑 Creating initial Firestore document...", component: "Processing")
        do {
            let data = initialVideo.toFirestoreData()
            LoggingService.debug("📋 Document data prepared: \(data)", component: "Processing")
            
            try await firestore
                .collection("videos")
                .document(videoId)
                .setData(data)
            LoggingService.success("✅ Created initial video document with uploading status", component: "Processing")
        } catch {
            LoggingService.error("❌ Failed to create initial video document: \(error.localizedDescription)", component: "Processing")
            LoggingService.error("🔍 Error details: \(error)", component: "Processing")
            throw error
        }
        
        do {
            // Step 1: Upload to Firebase Storage
            LoggingService.debug("📤 Starting Firebase Storage upload process...", component: "Storage")
            let videoDownloadURL = try await uploadToFirebase(
                fileURL: sourceURL,
                path: "videos",
                filename: "\(videoId).mp4",
                onProgress: { progress in
                    LoggingService.progress("📊 Upload progress", progress: progress, component: "Storage")
                    onProgress?(progress)
                }
            )
            LoggingService.success("✅ Video upload completed successfully", component: "Storage")
            LoggingService.debug("🔗 Video URL: \(videoDownloadURL)", component: "Storage")
            
            // Step 2: Update Firestore document
            LoggingService.debug("📝 Updating Firestore document with video URL...", component: "Processing")
            do {
                try await firestore
                    .collection("videos")
                    .document(videoId)
                    .updateData([
                        "videoURL": videoDownloadURL,
                        "thumbnailURL": "",
                        "updatedAt": FieldValue.serverTimestamp()
                    ] as [String: Any])
                
                LoggingService.success("✅ Updated video document with URL", component: "Processing")
                LoggingService.debug("⏳ Waiting for Cloud Function processing...", component: "Processing")
            } catch {
                LoggingService.error("❌ Failed to update video document: \(error.localizedDescription)", component: "Processing")
                LoggingService.error("🔍 Error details: \(error)", component: "Processing")
                throw error
            }
            
            LoggingService.success("🎉 Video processing pipeline completed successfully", component: "Processing")
            return (videoId, videoDownloadURL, "")
        } catch {
            // Handle upload failure
            LoggingService.error("❌ Video processing failed: \(error.localizedDescription)", component: "Processing")
            
            // Update status to error
            do {
                LoggingService.debug("📝 Updating document status to error...", component: "Processing")
                try await firestore
                    .collection("videos")
                    .document(videoId)
                    .updateData([
                        "processingStatus": VideoProcessingStatus.error.rawValue,
                        "processingError": error.localizedDescription
                    ] as [String: Any])
                
                LoggingService.debug("✅ Updated video status to error", component: "Processing")
            } catch let updateError {
                LoggingService.error("❌ Failed to update error status: \(updateError.localizedDescription)", component: "Processing")
                LoggingService.error("🔍 Error details: \(updateError)", component: "Processing")
            }
            
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
        LoggingService.debug("📤 Starting Firebase upload process", component: "Storage")
        
        let actualFilename = filename ?? "\(UUID().uuidString).mp4"
        LoggingService.debug("📄 Using filename: \(actualFilename)", component: "Storage")
        
        let storageRef = storage.reference().child("\(path)/\(actualFilename)")
        LoggingService.debug("📁 Storage path: \(path)/\(actualFilename)", component: "Storage")
        
        // Get file size
        let fileSize: Int64
        do {
            LoggingService.debug("📊 Checking file size...", component: "Storage")
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = Int64(attributes[.size] as? UInt64 ?? 0)
            LoggingService.success("✅ File size retrieved: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))", component: "Storage")
        } catch {
            fileSize = 0
            LoggingService.error("❌ Failed to get file size: \(error.localizedDescription)", component: "Storage")
        }
        
        // Set up metadata
        LoggingService.debug("📋 Setting up upload metadata...", component: "Storage")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        // Create upload task
        LoggingService.debug("🚀 Creating upload task...", component: "Storage")
        let uploadTask = storageRef.putFile(from: fileURL, metadata: metadata)
        
        // Setup progress monitoring
        LoggingService.debug("📊 Setting up progress monitoring...", component: "Storage")
        setupUploadProgressMonitoring(uploadTask: uploadTask, filename: actualFilename, onProgress: onProgress)
        
        // Return continuation
        return try await withCheckedThrowingContinuation { continuation in
            LoggingService.debug("⏳ Waiting for upload completion...", component: "Storage")
            
            uploadTask.observe(.success) { _ in
                LoggingService.success("✅ Upload task completed successfully", component: "Storage")
                Task {
                    do {
                        LoggingService.debug("🔗 Getting download URL...", component: "Storage")
                        let downloadURL = try await storageRef.downloadURL()
                        LoggingService.success("✅ Got download URL: \(downloadURL.absoluteString)", component: "Storage")
                        continuation.resume(returning: downloadURL.absoluteString)
                    } catch {
                        LoggingService.error("❌ Failed to get download URL: \(error.localizedDescription)", component: "Storage")
                        LoggingService.error("🔍 Error details: \(error)", component: "Storage")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            uploadTask.observe(.failure) { snapshot in
                let error = snapshot.error ?? NSError(domain: "VideoProcessingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
                LoggingService.error("❌ Upload task failed: \(error.localizedDescription)", component: "Storage")
                LoggingService.error("🔍 Error details: \(error)", component: "Storage")
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func setupUploadProgressMonitoring(
        uploadTask: StorageUploadTask,
        filename: String,
        onProgress: ((Double) -> Void)? = nil
    ) {
        LoggingService.debug("📊 Setting up upload progress monitoring for \(filename)", component: "Storage")
        var lastReportedProgress: Int = -1
        
        uploadTask.observe(.progress) { snapshot in
            guard let progress = snapshot.progress else {
                LoggingService.error("❌ No progress data available", component: "Storage")
                return
            }
            
            // Calculate progress
            let completed = Double(progress.completedUnitCount)
            let total = Double(progress.totalUnitCount)
            let progressRatio = completed / total
            let percentComplete = Int(progressRatio * 100.0)
            
            // Only report if progress has changed
            if percentComplete != lastReportedProgress {
                // Format byte counts
                let completedStr = ByteCountFormatter.string(
                    fromByteCount: progress.completedUnitCount,
                    countStyle: .file
                )
                let totalStr = ByteCountFormatter.string(
                    fromByteCount: progress.totalUnitCount,
                    countStyle: .file
                )
                
                // Log progress with different emojis based on completion percentage
                let progressEmoji = percentComplete < 25 ? "🌱" :
                                  percentComplete < 50 ? "🌿" :
                                  percentComplete < 75 ? "🌳" :
                                  percentComplete < 100 ? "🎋" : "🎉"
                
                LoggingService.debug(
                    "\(progressEmoji) Upload progress: \(percentComplete)%",
                    component: "Storage"
                )
                LoggingService.debug(
                    "📈 Uploaded: \(completedStr) / \(totalStr)",
                    component: "Storage"
                )
                
                // Calculate and log transfer rate
                if progress.completedUnitCount > 0 {
                    if let throughput = progress.throughput {
                        let bytesPerSecond: Int64 = Int64(Double(progress.completedUnitCount) / Double(throughput))
                        let transferRate = ByteCountFormatter.string(
                            fromByteCount: bytesPerSecond,
                            countStyle: .file
                        ) + "/s"
                        LoggingService.debug("⚡️ Transfer rate: \(transferRate)", component: "Storage")
                    }
                }
                
                // Call progress callback
                LoggingService.progress("Video upload", progress: Double(percentComplete) / 100.0, component: filename)
                onProgress?(Double(percentComplete) / 100.0)
                
                lastReportedProgress = percentComplete
                
                // Log milestone messages
                if percentComplete == 25 {
                    LoggingService.debug("🎯 Upload is quarter way through!", component: "Storage")
                } else if percentComplete == 50 {
                    LoggingService.debug("🎯 Upload is halfway there!", component: "Storage")
                } else if percentComplete == 75 {
                    LoggingService.debug("🎯 Upload is three-quarters complete!", component: "Storage")
                } else if percentComplete == 100 {
                    LoggingService.success("🎉 Upload completed!", component: "Storage")
                }
            }
        }
        
        // Also observe state changes
        uploadTask.observe(.resume) { _ in
            LoggingService.debug("▶️ Upload resumed", component: "Storage")
        }
        
        uploadTask.observe(.pause) { _ in
            LoggingService.debug("⏸️ Upload paused", component: "Storage")
        }
        
        LoggingService.success("✅ Progress monitoring setup complete", component: "Storage")
    }
    
    private func generateVideoId(fileName: String) -> String {
        let timestamp = Date().timeIntervalSince1970
        let randomHex = UUID().uuidString.prefix(8)
        let sanitizedFilename = fileName.replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
        let uniqueId = "\(sanitizedFilename)_\(Int(timestamp))_\(randomHex)"
        LoggingService.debug("🔑 Generated unique video ID: \(uniqueId)", component: "Processing")
        return uniqueId
    }
} 