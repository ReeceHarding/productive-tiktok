import Foundation
import FirebaseFirestore
import FirebaseStorage
import SwiftUI

@MainActor
class VideoManagementViewModel: ObservableObject {
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
            LoggingService.error("No authenticated user", component: "Management")
            error = "No authenticated user"
            return
        }
        
        isLoading = true
        LoggingService.video("Loading videos for user \(userId)", component: "Management")
        
        do {
            // Get user's video references
            let userVideosSnapshot = try await firestore
                .collection("users")
                .document(userId)
                .collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            LoggingService.debug("Found \(userVideosSnapshot.documents.count) video references", component: "Management")
            
            // Remove existing listeners
            videoListeners.values.forEach { $0.remove() }
            videoListeners.removeAll()
            
            // Fetch each video document and set up listeners
            var loadedVideos: [Video] = []
            for document in userVideosSnapshot.documents {
                guard let videoId = document.data()["videoId"] as? String else { continue }
                
                // Get the video document
                let videoDoc = try await firestore.collection("videos").document(videoId).getDocument()
                if let video = Video(document: videoDoc) {
                    loadedVideos.append(video)
                    setupVideoListener(videoId: videoId)
                }
            }
            
            LoggingService.success("Loaded \(loadedVideos.count) videos", component: "Management")
            
            // Update videos and calculate statistics
            self.videos = loadedVideos
            updateStatistics()
            
        } catch {
            LoggingService.error("Failed to load videos: \(error.localizedDescription)", component: "Management")
            self.error = "Failed to load videos: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func setupVideoListener(videoId: String) {
        LoggingService.debug("Setting up listener for video \(videoId)", component: "Management")
        
        let listener = firestore.collection("videos").document(videoId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    LoggingService.error("Video listener error: \(error.localizedDescription)", component: "Management")
                    return
                }
                
                guard let snapshot = snapshot,
                      let updatedVideo = Video(document: snapshot) else {
                    LoggingService.error("Invalid video snapshot for \(videoId)", component: "Management")
                    return
                }
                
                // Update video in array
                if let index = self.videos.firstIndex(where: { $0.id == videoId }) {
                    LoggingService.debug("Updating video \(videoId) - Status: \(updatedVideo.processingStatus.rawValue)", component: "Management")
                    self.videos[index] = updatedVideo
                    self.updateStatistics()
                }
            }
        
        videoListeners[videoId] = listener
    }
    
    private func updateStatistics() {
        var stats = VideoStatistics()
        
        for video in videos {
            stats.totalVideos += 1
            stats.totalViews += video.viewCount
            stats.totalLikes += video.likeCount
            stats.totalComments += video.commentCount
            stats.totalSaves += video.saveCount
        }
        
        // Calculate engagement rate
        if stats.totalViews > 0 {
            let totalEngagements = Double(stats.totalLikes + stats.totalComments + stats.totalSaves)
            stats.engagementRate = totalEngagements / Double(stats.totalViews)
        }
        
        LoggingService.debug("""
            Updated statistics:
            - Total Videos: \(stats.totalVideos)
            - Total Views: \(stats.totalViews)
            - Total Likes: \(stats.totalLikes)
            - Total Comments: \(stats.totalComments)
            - Total Saves: \(stats.totalSaves)
            - Engagement Rate: \(String(format: "%.2f%%", stats.engagementRate * 100))
            """, component: "Management")
        
        self.statistics = stats
    }
    
    func deleteVideo(_ video: Video) async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("No authenticated user", component: "Management")
            error = "No authenticated user"
            return
        }
        
        LoggingService.video("Deleting video \(video.id)", component: "Management")
        
        do {
            // Remove from Firestore
            try await firestore.collection("videos").document(video.id).delete()
            try await firestore
                .collection("users")
                .document(userId)
                .collection("videos")
                .document(video.id)
                .delete()
            
            // Remove from Storage if URL exists
            if !video.videoURL.isEmpty {
                let storage = Storage.storage()
                if let url = URL(string: video.videoURL),
                   let path = url.path.components(separatedBy: "/o/").last?.removingPercentEncoding {
                    try await storage.reference().child(path).delete()
                }
            }
            
            // Remove listener
            videoListeners[video.id]?.remove()
            videoListeners.removeValue(forKey: video.id)
            
            // Update local state
            videos.removeAll { $0.id == video.id }
            updateStatistics()
            
            LoggingService.success("Successfully deleted video \(video.id)", component: "Management")
        } catch {
            LoggingService.error("Failed to delete video: \(error.localizedDescription)", component: "Management")
            self.error = "Failed to delete video: \(error.localizedDescription)"
        }
    }
} 