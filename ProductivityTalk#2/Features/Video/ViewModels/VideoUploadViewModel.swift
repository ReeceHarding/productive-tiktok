import SwiftUI
import PhotosUI
import AVFoundation
import FirebaseStorage
import FirebaseFirestore

@MainActor
class VideoUploadViewModel: ObservableObject {
    // UI State
    @Published var selectedItem: PhotosPickerItem?
    @Published var thumbnailImage: UIImage?
    @Published var title = ""
    @Published var tagsInput = ""
    @Published var description = ""
    
    // Upload State
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0
    @Published var showError = false
    @Published var errorMessage: String?
    
    // Video Data
    private var videoURL: URL?
    private var videoData: Data?
    private var thumbnailData: Data?
    
    // Firebase References
    private let storage = Storage.storage()
    private let firestore = Firestore.firestore()
    
    var canUpload: Bool {
        selectedItem != nil && !title.isEmpty && !tagsInput.isEmpty && !description.isEmpty
    }
    
    func loadVideo() async {
        print("📹 Video: Starting to load selected video")
        guard let item = selectedItem else {
            print("❌ Video: No video selected")
            return
        }
        
        do {
            // Load video data
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
            }
            self.videoData = videoData
            print("✅ Video: Successfully loaded video data: \(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))")
            
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try videoData.write(to: tempURL)
            self.videoURL = tempURL
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
            
            thumbnailImage = UIImage(cgImage: cgImage)
            thumbnailData = thumbnailImage?.jpegData(compressionQuality: 0.7)
            print("✅ Video: Generated thumbnail image")
            
        } catch {
            print("❌ Video: Failed to load video: \(error.localizedDescription)")
            showError = true
            errorMessage = "Failed to load video: \(error.localizedDescription)"
            selectedItem = nil
        }
    }
    
    func uploadVideo() async {
        guard let videoData = videoData, let thumbnailData = thumbnailData else {
            print("❌ Video: Missing video or thumbnail data")
            showError = true
            errorMessage = "Video data not ready. Please try again."
            return
        }
        
        isUploading = true
        uploadProgress = 0
        print("📤 Video: Starting upload process")
        
        do {
            // Generate IDs
            let videoId = UUID().uuidString
            print("📝 Video: Generated video ID: \(videoId)")
            
            // Upload video
            let videoRef = storage.reference().child("videos/\(videoId).mp4")
            print("📤 Video: Uploading video to path: videos/\(videoId).mp4")
            
            let videoMetadata = StorageMetadata()
            videoMetadata.contentType = "video/mp4"
            
            let _ = try await videoRef.putDataAsync(
                videoData,
                metadata: videoMetadata,
                onProgress: { [weak self] progress in
                    guard let progress = progress else { return }
                    let percentage = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    print("📊 Video: Upload progress: \(Int(percentage * 100))%")
                    self?.uploadProgress = percentage
                }
            )
            
            // Get video download URL
            let videoURL = try await videoRef.downloadURL()
            print("✅ Video: Video uploaded successfully. URL: \(videoURL.absoluteString)")
            
            // Upload thumbnail with async/await
            print("📤 Video: Uploading thumbnail")
            let thumbnailRef = storage.reference().child("thumbnails/\(videoId).jpg")
            
            let thumbnailMetadata = StorageMetadata()
            thumbnailMetadata.contentType = "image/jpeg"
            
            let _ = try await thumbnailRef.putDataAsync(thumbnailData, metadata: thumbnailMetadata)
            let thumbnailURL = try await thumbnailRef.downloadURL()
            print("✅ Video: Thumbnail uploaded successfully")
            
            // Save to Firestore
            let video = Video(
                id: videoId,
                ownerId: AuthenticationManager.shared.currentUser?.uid ?? "",
                videoURL: videoURL.absoluteString,
                thumbnailURL: thumbnailURL.absoluteString,
                title: title,
                tags: tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                description: description,
                ownerUsername: AuthenticationManager.shared.appUser?.username ?? "Unknown"
            )
            
            try await firestore.collection("videos").document(videoId).setData(video.toFirestoreData())
            print("✅ Video: Saved video metadata to Firestore")
            
            // Clean up
            if let tempURL = self.videoURL {
                try FileManager.default.removeItem(at: tempURL)
                print("✅ Video: Cleaned up temporary file")
            }
            
            resetForm()
            print("✅ Video: Upload process completed successfully")
            
        } catch {
            print("❌ Video: Upload failed: \(error.localizedDescription)")
            showError = true
            errorMessage = "Failed to upload video: \(error.localizedDescription)"
        }
        
        isUploading = false
    }
    
    private func resetForm() {
        selectedItem = nil
        thumbnailImage = nil
        title = ""
        tagsInput = ""
        description = ""
        videoURL = nil
        videoData = nil
        thumbnailData = nil
        uploadProgress = 0
    }
} 