import Foundation
import PhotosUI
import AVFoundation
import FirebaseStorage
import FirebaseFirestore
import SwiftUI

@MainActor
final class VideoUploadViewModel: ObservableObject {
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
    
    // Add to class properties
    private var documentListeners: [String: ListenerRegistration] = [:]
    
    init() {
        // Initialize with default values
    }
    
    struct UploadState {
        var progress: Double
        var isComplete: Bool
        var thumbnailImage: UIImage?
        var processingStatus: VideoProcessingStatus = .uploading
        var transcript: String?
        var quotes: [String]?
        
        var statusMessage: String {
            switch processingStatus {
            case .uploading:
                if progress == 0 {
                    return "Preparing upload..."
                } else if progress < 0.15 {
                    return "Starting upload..."
                } else if progress < 1 {
                    return "Uploading video... \(Int(progress * 100))%"
                } else {
                    return "Upload complete, preparing for processing..."
                }
            case .transcribing:
                return "Transcribing video content..."
            case .extractingQuotes:
                return "Extracting meaningful quotes..."
            case .generatingMetadata:
                return "Generating video metadata..."
            case .processing:
                return "Processing video..."
            case .ready:
                return "✅ Upload complete"
            case .error:
                return "❌ Upload failed"
            }
        }
    }
    
    func loadVideos() async {
        LoggingService.video("🎥 Starting to load selected videos (count: \(selectedItems.count))", component: "Upload")
        
        // Immediately create upload states for all selected items
        for _ in selectedItems {
            let id = UUID().uuidString
            await MainActor.run {
                LoggingService.debug("Creating initial upload state for video \(id)", component: "Upload")
                self.uploadStates[id] = UploadState(
                    progress: 0.0,
                    isComplete: false,
                    thumbnailImage: nil,
                    processingStatus: .uploading,
                    transcript: nil,
                    quotes: nil
                )
            }
        }
        
        // Process each video
        for (index, item) in selectedItems.enumerated() {
            let id = Array(uploadStates.keys)[index]
            var tempURL: URL?
            
            LoggingService.debug("Processing video item with generated ID: \(id)", component: "Upload")
            
            do {
                // Load video data
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    LoggingService.error("❌ Failed to load video data for item \(id)", component: "Upload")
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                
                let fileSize = ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file)
                LoggingService.success("📦 Successfully loaded video data: \(fileSize)", component: "Upload")
                
                await MainActor.run {
                    self.uploadStates[id]?.progress = 0.1 // Show initial progress
                }
                
                // Create temporary file
                tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).mov")
                guard let tempURL = tempURL else {
                    throw NSError(domain: "VideoUpload", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create temporary URL"])
                }
                
                try videoData.write(to: tempURL)
                LoggingService.debug("💾 Saved video to temporary file: \(tempURL.path)", component: "Upload")
                await MainActor.run {
                    self.uploadStates[id]?.progress = 0.15 // Show progress after saving temp file
                }
                
                // Create initial Firestore document
                guard let userId = AuthenticationManager.shared.currentUser?.uid,
                      let username = AuthenticationManager.shared.appUser?.username else {
                    LoggingService.error("❌ User not authenticated (userId: \(String(describing: AuthenticationManager.shared.currentUser?.uid)), username: \(String(describing: AuthenticationManager.shared.appUser?.username)))", component: "Upload")
                    throw NSError(domain: "VideoUpload", 
                                code: -2, 
                                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                LoggingService.debug("👤 User info - ID: \(userId), Username: \(username)", component: "Upload")
                
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
                LoggingService.debug("📝 Starting Firestore batch write for video \(id)", component: "Upload")
                
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
                LoggingService.success("✅ Created initial video documents in Firestore", component: "Upload")
                
                // Process and upload video with progress callback
                LoggingService.video("🔄 Starting video processing pipeline", component: "Upload")
                let (videoURL, thumbnailURL) = try await videoProcessor.processAndUploadVideo(
                    sourceURL: tempURL,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.uploadStates[id]?.progress = progress
                            if progress >= 1.0 {
                                self.uploadStates[id]?.processingStatus = .processing
                            }
                            LoggingService.debug("📊 Upload progress for \(id): \(Int(progress * 100))%", component: "Upload")
                        }
                    }
                )
                LoggingService.success("✅ Video processed successfully", component: "Upload")
                LoggingService.debug("📍 Video URL: \(videoURL)", component: "Upload")
                LoggingService.debug("📍 Thumbnail URL: \(thumbnailURL)", component: "Upload")
                
                // Update UI state
                await MainActor.run {
                    self.uploadStates[id] = UploadState(progress: 1.0, isComplete: true, thumbnailImage: nil)
                    self.uploadStates[id]?.processingStatus = .ready
                    LoggingService.debug("📊 Updated UI state - Progress: 100%, Complete: true", component: "Upload")
                }
                
                // Add listener after creating the document
                listenToVideoDocument(id: id)
                
            } catch {
                LoggingService.error("❌ Failed to process video: \(error.localizedDescription)", component: "Upload")
                LoggingService.error("Detailed error: \(error)", component: "Upload")
                
                // Update UI state
                await MainActor.run {
                    self.uploadStates[id] = UploadState(progress: 0, isComplete: false, thumbnailImage: nil)
                    self.showError = true
                    self.errorMessage = "Failed to process video: \(error.localizedDescription)"
                    self.uploadStates[id]?.processingStatus = .error
                    LoggingService.debug("📊 Updated UI state - Progress: 0%, Complete: false, Error shown", component: "Upload")
                }
                
                // Clean up Firestore document if it exists
                do {
                    try await firestore.collection("videos").document(id).delete()
                    try await firestore.collection("users")
                        .document(AuthenticationManager.shared.currentUser?.uid ?? "")
                        .collection("videos")
                        .document(id)
                        .delete()
                    LoggingService.debug("🧹 Cleaned up Firestore documents after error", component: "Upload")
                } catch let cleanupError {
                    LoggingService.error("Failed to clean up Firestore documents: \(cleanupError)", component: "Upload")
                }
            }
            
            // Clean up temp file only after everything is done
            if let tempURL = tempURL {
                do {
                    try FileManager.default.removeItem(at: tempURL)
                    LoggingService.debug("🧹 Cleaned up temporary file: \(tempURL.path)", component: "Upload")
                } catch {
                    LoggingService.error("Failed to clean up temporary file: \(error)", component: "Upload")
                }
            }
        }
        
        // Clear selection after processing
        selectedItems.removeAll()
        LoggingService.debug("🧹 Cleared selected items after processing", component: "Upload")
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
                        LoggingService.progress("Video upload", progress: percentage, component: id)
                        Task { @MainActor in
                            self?.uploadStates[id]?.progress = percentage
                            if percentage >= 1.0 {
                                self?.uploadStates[id]?.processingStatus = .processing
                            }
                        }
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
                await MainActor.run {
                    self.uploadStates[id]?.isComplete = true
                    self.uploadStates[id]?.processingStatus = .ready
                }
                
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
    
    func selectAndUploadVideo() async {
        // Implementation remains the same
    }
    
    private func handleVideoSelection(_ result: Result<[PHPickerResult], Error>) {
        // Implementation remains the same
    }
    
    private func uploadVideo(_ asset: PHAsset, id: String) async {
        // Implementation remains the same
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func listenToVideoDocument(id: String) {
        LoggingService.debug("Setting up listener for video \(id)", component: "Upload")
        let docRef = firestore.collection("videos").document(id)
        
        documentListeners[id] = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                LoggingService.error("Error listening to video \(id): \(error.localizedDescription)", component: "Upload")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists,
                  let video = Video(document: snapshot) else {
                LoggingService.error("No valid snapshot for video \(id)", component: "Upload")
                return
            }
            
            Task { @MainActor in
                // Update processing status with detailed logging
                let oldStatus = self.uploadStates[id]?.processingStatus
                self.uploadStates[id]?.processingStatus = video.processingStatus
                
                if oldStatus != video.processingStatus {
                    LoggingService.video("🔄 Video \(id) status changed: \(oldStatus?.rawValue ?? "none") -> \(video.processingStatus.rawValue)", component: "Upload")
                    
                    // Update progress based on status
                    switch video.processingStatus {
                    case .transcribing:
                        self.uploadStates[id]?.progress = 0.4
                        LoggingService.debug("📝 Starting transcription for \(id)", component: "Upload")
                    case .extractingQuotes:
                        self.uploadStates[id]?.progress = 0.6
                        LoggingService.debug("💭 Extracting quotes for \(id)", component: "Upload")
                    case .generatingMetadata:
                        self.uploadStates[id]?.progress = 0.8
                        LoggingService.debug("🏷️ Generating metadata for \(id)", component: "Upload")
                    case .processing:
                        self.uploadStates[id]?.progress = 0.9
                        LoggingService.debug("⚙️ Final processing for \(id)", component: "Upload")
                    case .ready:
                        self.uploadStates[id]?.progress = 1.0
                        self.uploadStates[id]?.isComplete = true
                        LoggingService.success("✅ Processing complete for \(id)", component: "Upload")
                    case .error:
                        self.uploadStates[id]?.progress = 0.0
                        self.uploadStates[id]?.isComplete = false
                        LoggingService.error("❌ Processing failed for \(id)", component: "Upload")
                    default:
                        break
                    }
                }
                
                // Update transcript with logging
                if let transcript = video.transcript {
                    let isNewTranscript = self.uploadStates[id]?.transcript == nil
                    self.uploadStates[id]?.transcript = transcript
                    if isNewTranscript {
                        LoggingService.debug("📝 Received transcript for \(id) (\(transcript.prefix(50))...)", component: "Upload")
                    }
                }
                
                // Update quotes with logging
                if let quotes = video.quotes {
                    let isNewQuotes = self.uploadStates[id]?.quotes == nil
                    self.uploadStates[id]?.quotes = quotes
                    if isNewQuotes {
                        LoggingService.debug("💭 Received \(quotes.count) quotes for \(id)", component: "Upload")
                    }
                }
                
                // Remove listener if processing is complete or failed
                if video.processingStatus == .ready || video.processingStatus == .error {
                    self.documentListeners[id]?.remove()
                    self.documentListeners.removeValue(forKey: id)
                    LoggingService.debug("🔄 Removed listener for video \(id) - Final status: \(video.processingStatus.rawValue)", component: "Upload")
                }
            }
        }
    }
    
    deinit {
        documentListeners.values.forEach { $0.remove() }
    }
} 