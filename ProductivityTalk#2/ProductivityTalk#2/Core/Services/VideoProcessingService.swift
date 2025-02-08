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
        LoggingService.video("Starting video processing pipeline", component: "Processing")
        
        // Generate a unique ID for the video
        let videoId = UUID().uuidString
        LoggingService.debug("Generated video ID: \(videoId)", component: "Processing")
        
        // Create initial Firestore document
        guard let userId = await AuthenticationManager.shared.currentUser?.uid,
              let username = await AuthenticationManager.shared.appUser?.username else {
            LoggingService.error("User not authenticated", component: "Processing")
            throw NSError(domain: "VideoProcessing", 
                         code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
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
        try await firestore
            .collection("videos")
            .document(videoId)
            .setData(initialVideo.toFirestoreData())  // This will automatically set status to .uploading
        
        LoggingService.success("Created initial video document with uploading status", component: "Processing")
        
        do {
            // Step 1: Upload to Firebase with progress monitoring
            LoggingService.storage("Starting Firebase upload", component: "Upload")
            let videoDownloadURL = try await uploadToFirebase(
                fileURL: sourceURL,
                path: "videos",
                filename: "\(videoId).mp4"
            )
            LoggingService.success("Upload completed", component: "Upload")
            
            // Step 2: Update Firestore document with URL and ready status
            try await firestore
                .collection("videos")
                .document(videoId)
                .updateData([
                    "videoURL": videoDownloadURL,
                    "thumbnailURL": "",  // No thumbnail needed
                    "processingStatus": VideoProcessingStatus.ready.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            
            LoggingService.success("Updated video document with URL and ready status", component: "Processing")
            
            return (videoDownloadURL, "")
        } catch {
            // Update status to error on failure
            try? await firestore
                .collection("videos")
                .document(videoId)
                .updateData([
                    "processingStatus": VideoProcessingStatus.error.rawValue,
                    "processingError": error.localizedDescription
                ])
            
            LoggingService.error("Processing failed: \(error.localizedDescription)", component: "Processing")
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
        let actualFilename = filename ?? "\(UUID().uuidString)_\(fileURL.lastPathComponent)"
        let storageRef = storage.reference().child("\(path)/\(actualFilename)")
        
        let metadata = StorageMetadata()
        metadata.contentType = path == "videos" ? "video/mp4" : "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putFile(from: fileURL, metadata: metadata)
            var lastReportedProgress: Int = -1
            
            // Monitor progress
            uploadTask.observe(.progress) { snapshot in
                let percentComplete = Int(100.0 * Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1))
                if percentComplete % 10 == 0 && percentComplete != lastReportedProgress {
                    let fileType = path == "videos" ? "Video" : "Thumbnail"
                    LoggingService.progress("\(fileType) upload", progress: Double(percentComplete) / 100.0, id: actualFilename)
                    lastReportedProgress = percentComplete
                }
            }
            
            // Monitor completion
            uploadTask.observe(.success) { _ in
                // Use a detached task to avoid actor reentrancy
                Task.detached {
                    do {
                        let downloadURL = try await storageRef.downloadURL()
                        continuation.resume(returning: downloadURL.absoluteString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Monitor failure
            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
} 