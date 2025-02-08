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
    
    struct UploadState {
        var progress: Double
        var isComplete: Bool
        var thumbnailImage: UIImage?
    }
    
    func loadVideos() async {
        print("📹 Video: Starting to load selected videos")
        
        for item in selectedItems {
            let id = UUID().uuidString
            
            do {
                // Load video data
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                print("✅ Video: Successfully loaded video data for \(id): \(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))")
                
                // Create temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).mov")
                try videoData.write(to: tempURL)
                print("✅ Video: Saved video to temporary file: \(tempURL.path)")
                
                // Generate thumbnail
                let asset = AVURLAsset(url: tempURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                
                let time = CMTime(seconds: 0, preferredTimescale: 1)
                
                // Use async thumbnail generation
                let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                    generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let cgImage = cgImage {
                            continuation.resume(returning: cgImage)
                        } else {
                            continuation.resume(throwing: NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"]))
                        }
                    }
                }
                
                let thumbnailImage = UIImage(cgImage: cgImage)
                guard let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.7) else {
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress thumbnail"])
                }
                print("✅ Video: Generated thumbnail image for \(id)")
                
                // Store data and update UI
                self.videoData[id] = (videoData, thumbnailData)
                self.uploadStates[id] = UploadState(progress: 0, isComplete: false, thumbnailImage: thumbnailImage)
                
                // Clean up temp file
                try FileManager.default.removeItem(at: tempURL)
                
            } catch {
                print("❌ Video: Failed to load video: \(error.localizedDescription)")
                self.uploadStates[id] = UploadState(progress: 0, isComplete: false, thumbnailImage: nil)
            }
        }
        
        // Start uploading all videos
        await uploadVideos()
    }
    
    private func uploadVideos() async {
        print("📤 Video: Starting upload process for \(videoData.count) videos")
        
        for (id, data) in videoData {
            do {
                // Create Firestore document first with initial state
                let video = Video(
                    id: id,
                    ownerId: AuthenticationManager.shared.currentUser?.uid ?? "",
                    videoURL: "", // Will be updated after upload
                    thumbnailURL: "", // Will be updated after upload
                    title: "Processing...",
                    tags: [],
                    description: "Processing...",
                    ownerUsername: AuthenticationManager.shared.appUser?.username ?? "Unknown"
                )
                
                try await firestore.collection("videos").document(id).setData(video.toFirestoreData())
                print("✅ Video: Created initial video document in Firestore for \(id)")
                
                // Upload video
                let videoRef = storage.reference().child("videos/\(id).mp4")
                print("📤 Video: Uploading video to path: videos/\(id).mp4")
                
                let videoMetadata = StorageMetadata()
                videoMetadata.contentType = "video/mp4"
                
                let _ = try await videoRef.putDataAsync(
                    data.data,
                    metadata: videoMetadata,
                    onProgress: { [weak self] progress in
                        guard let progress = progress else { return }
                        let percentage = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        print("📊 Video: Upload progress for \(id): \(Int(percentage * 100))%")
                        self?.uploadStates[id]?.progress = percentage
                    }
                )
                
                // Get video download URL
                let videoURL = try await videoRef.downloadURL()
                print("✅ Video: Video uploaded successfully. URL: \(videoURL.absoluteString)")
                
                // Upload thumbnail
                print("📤 Video: Uploading thumbnail for \(id)")
                let thumbnailRef = storage.reference().child("thumbnails/\(id).jpg")
                
                let thumbnailMetadata = StorageMetadata()
                thumbnailMetadata.contentType = "image/jpeg"
                
                let _ = try await thumbnailRef.putDataAsync(data.thumbnail, metadata: thumbnailMetadata)
                let thumbnailURL = try await thumbnailRef.downloadURL()
                print("✅ Video: Thumbnail uploaded successfully for \(id)")
                
                // Update Firestore document with URLs
                let updateData: [String: Any] = [
                    "videoURL": videoURL.absoluteString,
                    "thumbnailURL": thumbnailURL.absoluteString,
                    "processingStatus": VideoProcessingStatus.ready.rawValue
                ] as [String: Any]
                
                try await firestore.collection("videos").document(id).updateData(updateData)
                print("✅ Video: Updated video URLs in Firestore for \(id)")
                
                // Mark as complete
                self.uploadStates[id]?.isComplete = true
                
            } catch {
                print("❌ Video: Upload failed for \(id): \(error.localizedDescription)")
                self.uploadStates[id]?.progress = 0
                showError = true
                errorMessage = "Failed to upload video: \(error.localizedDescription)"
                
                // Clean up Firestore document if it exists
                try? await firestore.collection("videos").document(id).delete()
            }
        }
        
        // Clear data after all uploads
        videoData.removeAll()
        selectedItems.removeAll()
    }
} 