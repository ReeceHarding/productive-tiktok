import Foundation
import FirebaseFirestore
import SwiftUI

@MainActor
final class VideoManagementViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    
    // MARK: - Statistics
    @Published private(set) var statistics = VideoStatistics()
    
    // MARK: - Private Properties
    private let firestore = Firestore.firestore()
    private var videoListeners: [String: ListenerRegistration] = [:]
    
    struct VideoStatistics {
        var totalVideos: Int = 0
        var totalViews: Int = 0
        var totalLikes: Int = 0
        var totalComments: Int = 0
        var totalSaves: Int = 0
        var engagementRate: Double = 0.0
    }
    
    // MARK: - Initialization
    init() {
        LoggingService.video("Initializing VideoManagementViewModel", component: "Management")
    }
    
    deinit {
        // Clean up listeners
        for (_, listener) in videoListeners {
            listener.remove()
        }
    }
    
    // MARK: - Public Methods
    func loadVideos() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("No authenticated user found", component: "Management")
            error = "Please sign in to view your videos"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            LoggingService.video("Loading videos for user: \(userId)", component: "Management")
            
            // Query user's videos collection
            let userVideosRef = firestore.collection("users")
                .document(userId)
                .collection("videos")
                .order(by: "createdAt", descending: true)
            
            let userVideosSnapshot = try await userVideosRef.getDocuments()
            let videoIds = userVideosSnapshot.documents.compactMap { doc -> String? in
                return doc.data()["videoId"] as? String
            }
            
            LoggingService.debug("Found \(videoIds.count) video references", component: "Management")
            
            // Fetch actual video documents
            var fetchedVideos: [Video] = []
            for videoId in videoIds {
                let videoDoc = try await firestore.collection("videos")
                    .document(videoId)
                    .getDocument()
                
                if let video = Video(document: videoDoc) {
                    fetchedVideos.append(video)
                    subscribeToUpdates(for: video)
                }
            }
            
            LoggingService.success("Successfully loaded \(fetchedVideos.count) videos", component: "Management")
            
            // Update videos and calculate statistics
            self.videos = fetchedVideos
            updateStatistics()
            
        } catch {
            LoggingService.error("Failed to load videos: \(error)", component: "Management")
            self.error = "Failed to load videos: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func deleteVideo(_ video: Video) async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("No authenticated user found", component: "Management")
            error = "Please sign in to delete videos"
            return
        }
        
        do {
            LoggingService.video("Deleting video: \(video.id)", component: "Management")
            
            // Start a batch write
            let batch = firestore.batch()
            
            // Delete video document
            let videoRef = firestore.collection("videos").document(video.id)
            batch.deleteDocument(videoRef)
            
            // Delete user-video relationship
            let userVideoRef = firestore.collection("users")
                .document(userId)
                .collection("videos")
                .document(video.id)
            batch.deleteDocument(userVideoRef)
            
            // Commit the batch
            try await batch.commit()
            
            // Update local state
            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos.remove(at: index)
                updateStatistics()
            }
            
            LoggingService.success("Successfully deleted video: \(video.id)", component: "Management")
            
        } catch {
            LoggingService.error("Failed to delete video: \(error)", component: "Management")
            self.error = "Failed to delete video: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func subscribeToUpdates(for video: Video) {
        // Remove existing listener if any
        videoListeners[video.id]?.remove()
        
        let listener = firestore.collection("videos")
            .document(video.id)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    LoggingService.error("Error listening to video updates: \(error)", component: "Management")
                    return
                }
                
                guard let snapshot = snapshot,
                      snapshot.exists,
                      let updatedVideo = Video(document: snapshot) else {
                    return
                }
                
                if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                    self.videos[index] = updatedVideo
                    self.updateStatistics()
                }
            }
        
        videoListeners[video.id] = listener
        LoggingService.debug("Subscribed to updates for video: \(video.id)", component: "Management")
    }
    
    private func updateStatistics() {
        var stats = VideoStatistics()
        
        stats.totalVideos = videos.count
        stats.totalViews = videos.reduce(0) { $0 + $1.viewCount }
        stats.totalLikes = videos.reduce(0) { $0 + $1.likeCount }
        stats.totalComments = videos.reduce(0) { $0 + $1.commentCount }
        stats.totalSaves = videos.reduce(0) { $0 + $1.saveCount }
        
        // Calculate engagement rate
        if stats.totalViews > 0 {
            let totalEngagements = Double(stats.totalLikes + stats.totalComments + stats.totalSaves)
            stats.engagementRate = totalEngagements / Double(stats.totalViews)
        }
        
        statistics = stats
        LoggingService.debug("Updated video statistics", component: "Management")
    }
} 