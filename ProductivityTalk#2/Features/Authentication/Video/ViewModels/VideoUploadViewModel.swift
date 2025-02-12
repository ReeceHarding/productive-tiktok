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
        LoggingService.debug("VideoUploadViewModel init", component: "UploadVM")
    }
    
    struct UploadState {
        var progress: Double
        var isComplete: Bool
        var thumbnailImage: UIImage?
        var processingStatus: VideoProcessingStatus
        var transcript: String?
        var quotes: [String]?
        
        var statusMessage: String {
            // Provide more explicit stage-based messaging
            switch processingStatus {
            case .uploading:
                if progress == 0 {
                    return "Preparing upload..."
                } else if progress < 1.0 {
                    return "Uploading video... \(Int(progress * 100))%"
                } else {
                    return "Upload complete, preparing for processing..."
                }
            case .transcribing:
                return "Transcribing audio content..."
            case .extractingQuotes:
                return "Extracting meaningful quotes..."
            case .generatingMetadata:
                return "Generating metadata..."
            case .processing:
                // We no longer use "processing" from the function but let's keep it
                return "Processing..."
            case .ready:
                return "✅ Upload complete"
            case .error:
                return "❌ Upload failed"
            }
        }
    }

    func loadVideos() async {
        LoggingService.video("Starting to load selected videos (count: \(selectedItems.count))", component: "Upload")
        
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
                guard let vidData = try await item.loadTransferable(type: Data.self) else {
                    LoggingService.error("Failed to load video data for item \(id)", component: "Upload")
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                
                let fileSizeString = ByteCountFormatter.string(fromByteCount: Int64(vidData.count), countStyle: .file)
                LoggingService.success("Successfully loaded video data: \(fileSizeString)", component: "Upload")
                
                await MainActor.run {
                    self.uploadStates[id]?.progress = 0.05  // Start at 5% for data load
                }
                
                // Create temporary file
                tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).mov")
                guard let tempURL = tempURL else {
                    throw NSError(domain: "VideoUpload", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create tempURL"])
                }
                
                try vidData.write(to: tempURL)
                LoggingService.debug("Saved video to temporary file: \(tempURL.path)", component: "Upload")
                await MainActor.run {
                    self.uploadStates[id]?.progress = 0.1  // 10% for temp file creation
                }
                
                // Create Firestore doc references
                guard let userId = AuthenticationManager.shared.currentUser?.uid,
                      let username = AuthenticationManager.shared.appUser?.username else {
                    LoggingService.error("User not authenticated (userId or username missing)", component: "Upload")
                    throw NSError(domain: "VideoUpload", code: -2, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                LoggingService.debug("User info - ID: \(userId), Username: \(username)", component: "Upload")
                
                let video = Video(
                    id: id,
                    ownerId: userId,
                    videoURL: "",
                    thumbnailURL: "",
                    title: "Processing...",
                    tags: [],
                    description: "Processing...",
                    ownerUsername: username
                )
                
                // Firestore batch
                let batch = firestore.batch()
                LoggingService.debug("Starting Firestore batch write for video \(id)", component: "Upload")
                
                // main video doc
                let videoRef = firestore.collection("videos").document(id)
                batch.setData(video.toFirestoreData(), forDocument: videoRef)
                
                // user-videos reference
                let userVideoRef = firestore
                    .collection("users")
                    .document(userId)
                    .collection("videos")
                    .document(id)
                batch.setData([
                    "videoId": id,
                    "createdAt": Timestamp()
                ], forDocument: userVideoRef)
                
                try await batch.commit()
                LoggingService.success("Created initial video documents in Firestore", component: "Upload")
                
                // Use local VideoProcessingService to upload
                LoggingService.video("Starting video processing pipeline", component: "Upload")
                let (videoURL, thumbnailURL) = try await videoProcessor.processAndUploadVideo(
                    sourceURL: tempURL,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self = self else { return }
                            // Scale progress from 10% to 90% during upload
                            let scaledProgress = 0.1 + (progress * 0.8)
                            self.uploadStates[id]?.progress = scaledProgress
                            LoggingService.debug("Upload progress for \(id): \(Int(scaledProgress * 100))% (Firebase: \(Int(progress * 100))%)", component: "Upload")
                        }
                    }
                )
                LoggingService.success("Video processed successfully", component: "Upload")
                LoggingService.debug("Video URL: \(videoURL)", component: "Upload")
                LoggingService.debug("Thumbnail URL: \(thumbnailURL)", component: "Upload")
                
                // Mark complete
                await MainActor.run {
                    self.uploadStates[id]?.progress = 1.0
                    self.uploadStates[id]?.isComplete = true
                    self.uploadStates[id]?.processingStatus = .ready
                }
                
                // Add a listener to track the server function status changes
                listenToVideoDocument(id: id)
                
            } catch {
                LoggingService.error("Failed to process video: \(error.localizedDescription)", component: "Upload")
                await MainActor.run {
                    self.uploadStates[id]?.progress = 0
                    self.showError = true
                    self.errorMessage = "Failed to process video: \(error.localizedDescription)"
                    self.uploadStates[id]?.processingStatus = .error
                }
                // Clean up Firestore doc
                do {
                    try await firestore.collection("videos").document(id).delete()
                    try await firestore
                        .collection("users")
                        .document(AuthenticationManager.shared.currentUser?.uid ?? "")
                        .collection("videos")
                        .document(id)
                        .delete()
                } catch let cleanupError {
                    LoggingService.error("Failed to clean up Firestore docs: \(cleanupError)", component: "Upload")
                }
            }
            
            // Clean up local file
            if let tempURL = tempURL {
                do {
                    try FileManager.default.removeItem(at: tempURL)
                    LoggingService.debug("Cleaned up temporary file: \(tempURL.path)", component: "Upload")
                } catch {
                    LoggingService.error("Failed to remove temp file: \(error)", component: "Upload")
                }
            }
        }
        
        selectedItems.removeAll()
        LoggingService.debug("Cleared selected items after processing", component: "Upload")
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
                let oldStatus = self.uploadStates[id]?.processingStatus
                let newStatus = video.processingStatus
                let currentProgress = self.uploadStates[id]?.progress ?? 0
                
                LoggingService.debug("Video \(id) status changed from \(oldStatus?.rawValue ?? "nil") -> \(newStatus.rawValue) (current progress: \(Int(currentProgress * 100))%)", component: "Upload")

                // If status changed from oldStatus -> newStatus
                if oldStatus != newStatus {
                    LoggingService.video("Video \(id) status UI update: \(newStatus.rawValue)", component: "Upload")
                    self.uploadStates[id]?.processingStatus = newStatus
                    
                    switch newStatus {
                    case .uploading:
                        // Don't override progress during upload
                        break
                        
                    case .transcribing:
                        // Only update if we're past upload phase
                        if currentProgress >= 0.9 {
                            self.uploadStates[id]?.progress = 0.92
                            LoggingService.debug("Upload State: set progress to 0.92 for status transcribing", component: "Upload")
                        }
                        
                    case .extractingQuotes:
                        self.uploadStates[id]?.progress = 0.94
                        LoggingService.debug("Upload State: set progress to 0.94 for status extractingQuotes", component: "Upload")
                        
                    case .generatingMetadata:
                        self.uploadStates[id]?.progress = 0.96
                        LoggingService.debug("Upload State: set progress to 0.96 for status generatingMetadata", component: "Upload")
                        
                    case .processing:
                        self.uploadStates[id]?.progress = 0.98
                        LoggingService.debug("Upload State: set progress to 0.98 for status processing", component: "Upload")
                        
                    case .ready:
                        self.uploadStates[id]?.progress = 1.0
                        self.uploadStates[id]?.isComplete = true
                        LoggingService.success("Video \(id) is fully processed and ready", component: "Upload")
                        
                    case .error:
                        self.uploadStates[id]?.progress = 0
                        self.uploadStates[id]?.isComplete = false
                        LoggingService.error("Video \(id) is in error status", component: "Upload")
                    }
                }
                
                // Update transcript if it just arrived
                if let transcript = video.transcript {
                    let wasNull = self.uploadStates[id]?.transcript == nil
                    self.uploadStates[id]?.transcript = transcript
                    if wasNull {
                        LoggingService.debug("Received transcript for \(id): \"\(transcript.prefix(100))...\"", component: "Upload")
                    }
                }
                
                // Update quotes if we just got them
                if let quotes = video.quotes {
                    let wasNull = self.uploadStates[id]?.quotes == nil
                    self.uploadStates[id]?.quotes = quotes
                    if wasNull {
                        LoggingService.debug("Received quotes for \(id):", component: "Upload")
                        quotes.forEach { quote in
                            LoggingService.debug("  • \(quote)", component: "Upload")
                        }
                    }
                }
                
                // Update metadata if available
                if let autoTitle = video.autoTitle {
                    LoggingService.debug("Received auto-generated title for \(id): \"\(autoTitle)\"", component: "Upload")
                }
                
                if let autoDescription = video.autoDescription {
                    LoggingService.debug("Received auto-generated description for \(id): \"\(autoDescription)\"", component: "Upload")
                }
                
                if let autoTags = video.autoTags {
                    LoggingService.debug("Received auto-generated tags for \(id): \(autoTags.joined(separator: ", "))", component: "Upload")
                }
                
                // Update statistics
                LoggingService.debug("Video \(id) stats - Views: \(video.viewCount), Likes: \(video.likeCount), Comments: \(video.commentCount), Saves: \(video.saveCount)", component: "Upload")
                
                // If final or error, remove listener
                if video.processingStatus == .ready || video.processingStatus == .error {
                    self.documentListeners[id]?.remove()
                    self.documentListeners.removeValue(forKey: id)
                    LoggingService.debug("Removed listener for video \(id) - final status: \(video.processingStatus.rawValue)", component: "Upload")
                }
            }
        }
    }
    
    deinit {
        // remove doc listeners
        documentListeners.values.forEach { $0.remove() }
    }
}