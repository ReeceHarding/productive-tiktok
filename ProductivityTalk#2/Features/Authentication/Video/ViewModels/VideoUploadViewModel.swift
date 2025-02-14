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
    
    // Firebase References
    private let firestore = Firestore.firestore()
    private let videoProcessor = VideoProcessingService.shared
    
    // Add to class properties
    private var documentListeners: [String: ListenerRegistration] = [:]
    
    init() {
        LoggingService.debug("VideoUploadViewModel init", component: "UploadVM")
    }
    
    struct UploadState {
        var progress: Double
        var isComplete: Bool
        var processingStatus: VideoProcessingStatus
        var transcript: String?
        var quotes: [String]?
        var title: String
        var description: String
        
        var statusMessage: String {
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
        
        // Process each video
        for item in selectedItems {
            do {
                // Load video data
                guard let vidData = try await item.loadTransferable(type: Data.self) else {
                    LoggingService.error("Failed to load video data", component: "Upload")
                    throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                
                let fileSizeString = ByteCountFormatter.string(fromByteCount: Int64(vidData.count), countStyle: .file)
                LoggingService.success("Successfully loaded video data: \(fileSizeString)", component: "Upload")
                
                // Create temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try vidData.write(to: tempURL)
                LoggingService.debug("Saved video to temporary file: \(tempURL.path)", component: "Upload")
                
                // Create a temporary ID for tracking this upload
                let tempId = UUID().uuidString
                LoggingService.debug("Created temporary ID for tracking: \(tempId)", component: "Upload")
                
                // Initialize upload state
                self.uploadStates[tempId] = UploadState(
                    progress: 0.0,
                    isComplete: false,
                    processingStatus: .uploading,
                    transcript: nil,
                    quotes: nil,
                    title: "Processing...",
                    description: "Processing..."
                )
                
                // Upload video and get ID
                let videoId = try await videoProcessor.processAndUploadVideo(
                    sourceURL: tempURL,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.uploadStates[tempId]?.progress = progress
                            self.uploadStates[tempId]?.isComplete = progress >= 1.0
                        }
                    }
                )
                
                // Update state with actual video ID
                if let state = uploadStates[tempId] {
                    uploadStates[videoId] = state
                    uploadStates.removeValue(forKey: tempId)
                }
                
                // Start listening for updates
                listenToVideoDocument(id: videoId)
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                LoggingService.debug("Cleaned up temporary file", component: "Upload")
                
            } catch {
                LoggingService.error("Failed to process video: \(error.localizedDescription)", component: "Upload")
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to process video: \(error.localizedDescription)"
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
                
                LoggingService.debug("Video \(id) status changed from \(oldStatus?.rawValue ?? "nil") -> \(newStatus.rawValue)", component: "Upload")
                
                // Update state based on video document
                self.uploadStates[id] = UploadState(
                    progress: newStatus == .ready ? 1.0 : (self.uploadStates[id]?.progress ?? 0),
                    isComplete: newStatus == .ready,
                    processingStatus: newStatus,
                    transcript: video.transcript,
                    quotes: video.quotes,
                    title: video.title,
                    description: video.description
                )
                
                // If video is ready or errored, we can remove the listener
                if newStatus == .ready || newStatus == .error {
                    self.documentListeners[id]?.remove()
                    self.documentListeners.removeValue(forKey: id)
                    LoggingService.debug("Removed listener for completed video \(id)", component: "Upload")
                }
            }
        }
    }
}