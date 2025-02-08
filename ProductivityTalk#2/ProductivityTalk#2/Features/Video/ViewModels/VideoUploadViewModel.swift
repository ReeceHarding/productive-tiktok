import Foundation
import PhotosUI
import AVFoundation
import FirebaseStorage
import FirebaseFirestore
import SwiftUI

@MainActor
class VideoUploadViewModel: ObservableObject {
    // UI State
    @Published var selectedItems: [PhotosPickerItem] = []
    
    // Upload State
    @Published private(set) var uploadStates: [String: UploadState] = [:]
    @Published var showError = false
    @Published var errorMessage: String?
    
    // Video Data
    private var videoData: [String: (data: Data, thumbnail: Data)] = [:]
    
    // Firebase References
    private let storage = Storage.storage()
    private let firestore = Firestore.firestore()
    private let videoProcessor = VideoProcessingService.shared
    
    struct UploadState {
        var progress: Double
        var isComplete: Bool
        var thumbnailImage: UIImage?
    }
    
    func loadVideos() async {
        LoggingService.video("Starting to load selected videos", component: "Upload")
        
        for item in selectedItems {
            let id = UUID().uuidString
            
            do {
                // Load video data
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    LoggingService.error("Failed to load video data", component: "Upload")
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                LoggingService.success("Successfully loaded video data for \(id): \(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))", component: "Upload")
                
                // Create temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).mov")
                try videoData.write(to: tempURL)
                LoggingService.debug("Saved video to temporary file: \(tempURL.path)", component: "Upload")
                
                // Create initial Firestore document
                guard let userId = AuthenticationManager.shared.currentUser?.uid,
                      let username = AuthenticationManager.shared.appUser?.username else {
                    throw NSError(domain: "VideoUpload", 
                                code: -2, 
                                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                let video = Video(
                    id: id,
                    ownerId: userId,
                    videoURL: "",  // Will be updated after processing
                    thumbnailURL: "", // Will be updated after processing
                    title: "Processing...",
                    tags: [],
                    description: "Processing...",
                    ownerUsername: username
                )
                
                // Start a batch write
                let batch = firestore.batch()
                
                // Create the video document
                let videoRef = firestore.collection("videos").document(id)
                batch.setData(video.toFirestoreData(), forDocument: videoRef)
                
                // Create user-videos relationship
                let userVideoRef = firestore.collection("users")
                    .document(userId)
                    .collection("videos")
                    .document(id)
                batch.setData([
                    "videoId": id,
                    "createdAt": Timestamp()
                ], forDocument: userVideoRef)
                
                // Commit the batch
                try await batch.commit()
                LoggingService.success("Created initial video documents", component: "Upload")
                
                // Process and upload video
                LoggingService.video("Starting video processing", component: "Upload")
                let (_, _) = try await videoProcessor.processAndUploadVideo(sourceURL: tempURL)
                LoggingService.success("Video processed and uploaded successfully", component: "Upload")
                
                // Update UI state
                await MainActor.run {
                    self.uploadStates[id] = UploadState(progress: 1.0, isComplete: true, thumbnailImage: nil)
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                LoggingService.debug("Cleaned up temporary file", component: "Upload")
                
            } catch {
                LoggingService.error("Failed to process video: \(error.localizedDescription)", component: "Upload")
                
                // Update UI state
                await MainActor.run {
                    self.uploadStates[id] = UploadState(progress: 0, isComplete: false, thumbnailImage: nil)
                    self.showError = true
                    self.errorMessage = "Failed to process video: \(error.localizedDescription)"
                }
                
                // Clean up Firestore document if it exists
                try? await firestore.collection("videos").document(id).delete()
                try? await firestore.collection("users")
                    .document(AuthenticationManager.shared.currentUser?.uid ?? "")
                    .collection("videos")
                    .document(id)
                    .delete()
            }
        }
        
        // Clear selection after processing
        selectedItems.removeAll()
    }
    
    private func uploadVideos() async {
        LoggingService.video("Starting upload process for \(videoData.count) videos", component: "Upload")
        
        for (id, data) in videoData {
            do {
                // Create Firestore document first with initial state
                let video = Video(
                    id: id,
                    ownerId: AuthenticationManager.shared.currentUser?.uid ?? "",
                    videoURL: "",
                    thumbnailURL: "",
                    title: "Processing...",
                    tags: [],
                    description: "Processing...",
                    ownerUsername: AuthenticationManager.shared.appUser?.username ?? "Unknown"
                )
                
                try await firestore.collection("videos").document(id).setData(video.toFirestoreData())
                LoggingService.success("Created initial video document in Firestore for \(id)", component: "Upload")
                
                // Upload video
                let videoRef = storage.reference().child("videos/\(id).mp4")
                LoggingService.storage("Uploading video to path: videos/\(id).mp4", component: "Upload")
                
                let videoMetadata = StorageMetadata()
                videoMetadata.contentType = "video/mp4"
                
                let _ = try await videoRef.putDataAsync(
                    data.data,
                    metadata: videoMetadata,
                    onProgress: { [weak self] progress in
                        guard let progress = progress else { return }
                        let percentage = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        LoggingService.progress("Video upload", progress: percentage, id: id)
                        self?.uploadStates[id]?.progress = percentage
                    }
                )
                
                // Get video download URL
                let videoURL = try await videoRef.downloadURL()
                LoggingService.success("Video uploaded successfully. URL: \(videoURL.absoluteString)", component: "Upload")
                
                // Update Firestore document with URL and ready status
                let updateData: [String: Any] = [
                    "videoURL": videoURL.absoluteString,
                    "processingStatus": VideoProcessingStatus.ready.rawValue
                ]
                
                try await firestore.collection("videos").document(id).updateData(updateData)
                LoggingService.success("Updated video URL in Firestore for \(id)", component: "Upload")
                
                // Mark as complete
                self.uploadStates[id]?.isComplete = true
                
            } catch {
                LoggingService.error("Upload failed for \(id): \(error.localizedDescription)", component: "Upload")
                self.uploadStates[id]?.progress = 0
                showError = true
                errorMessage = "Failed to upload video: \(error.localizedDescription)"
                
                // Update status to error
                let updateData: [String: String] = [
                    "processingStatus": VideoProcessingStatus.error.rawValue
                ]
                try? await firestore.collection("videos").document(id).updateData(updateData)
                
                // Clean up Firestore document if needed
                try? await firestore.collection("videos").document(id).delete()
            }
        }
        
        // Clear data after all uploads
        videoData.removeAll()
        selectedItems.removeAll()
    }
} 