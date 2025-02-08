import Foundation
import FirebaseFirestore
import AVFoundation

public enum VideoPlayerError: Error {
    case assetNotPlayable
}

@MainActor
public class VideoFeedViewModel: ObservableObject {
    @Published public private(set) var videos: [Video] = []
    @Published public private(set) var isLoading = false
    @Published public var error: Error?
    @Published public var playerViewModels: [String: VideoPlayerViewModel] = [:]
    
    private let firestore = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private var isFetching = false
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private let batchSize = 5
    private let preloadWindow = 2 // Number of videos to preload ahead and behind
    private var preloadQueue = OperationQueue()
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    
    // Dictionary to hold snapshot listeners for each video document
    private var videoListeners: [String: ListenerRegistration] = [:]
    
    public init() {
        preloadQueue.maxConcurrentOperationCount = 2
        LoggingService.video("Initialized with preload window of \(preloadWindow)", component: "Feed")
    }
    
    deinit {
        // Remove all snapshot listeners when the feed view model is deallocated
        for (videoId, listener) in videoListeners {
            LoggingService.debug("Removing video listener for video \(videoId)", component: "Feed")
            listener.remove()
        }
    }
    
    func fetchVideos() async {
        guard !isFetching else {
            LoggingService.error("Already fetching videos", component: "Feed")
            return
        }
        
        isFetching = true
        isLoading = true
        error = nil
        
        LoggingService.video("Fetching initial batch of videos", component: "Feed")
        
        do {
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            var fetchedVideos: [Video] = []
            
            for document in snapshot.documents {
                LoggingService.debug("Processing document with ID: \(document.documentID)", component: "Feed")
                if let video = Video(document: document),
                   video.processingStatus == .ready,
                   !video.videoURL.isEmpty {
                    LoggingService.debug("Adding ready video: \(video.id)", component: "Feed")
                    fetchedVideos.append(video)
                    subscribeToUpdates(for: video)
                    // Create player view model if not already created
                    if playerViewModels[video.id] == nil {
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                } else {
                    LoggingService.debug("Skipping video \(document.documentID) - Not ready or no URL", component: "Feed")
                }
            }
            
            LoggingService.success("Fetched \(fetchedVideos.count) ready videos", component: "Feed")
            self.videos = fetchedVideos
            self.lastDocument = snapshot.documents.last
            
            // Preload the first two videos if available
            if !fetchedVideos.isEmpty {
                preloadVideo(at: 0)
                if fetchedVideos.count > 1 {
                    preloadVideo(at: 1)
                }
            }
            
        } catch {
            LoggingService.error("Error fetching videos: \(error)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
        isLoading = false
    }
    
    func fetchNextBatch() async {
        guard !isFetching else { return }
        isFetching = true
        isLoading = true
        
        do {
            LoggingService.video("Fetching next batch of \(batchSize) videos", component: "Feed")
            var query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: batchSize)
            
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            var newVideos: [Video] = []
            
            for document in snapshot.documents {
                if let video = Video(document: document),
                   video.processingStatus == .ready,
                   !video.videoURL.isEmpty {
                    LoggingService.debug("Adding ready video: \(video.id)", component: "Feed")
                    newVideos.append(video)
                    subscribeToUpdates(for: video)
                    // Create player view model if necessary
                    if playerViewModels[video.id] == nil {
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                } else {
                    LoggingService.debug("Skipping video \(document.documentID) - Not ready or no URL", component: "Feed")
                }
            }
            
            if !newVideos.isEmpty {
                LoggingService.success("Fetched \(newVideos.count) new ready videos", component: "Feed")
                self.videos.append(contentsOf: newVideos)
                self.lastDocument = snapshot.documents.last
            } else {
                LoggingService.info("No more ready videos to fetch", component: "Feed")
            }
        } catch {
            LoggingService.error("Failed to fetch videos: \(error.localizedDescription)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
        isLoading = false
    }
    
    private func subscribeToUpdates(for video: Video) {
        // Avoid duplicate listener for the same video
        if videoListeners[video.id] != nil {
            LoggingService.debug("Listener already exists for video \(video.id)", component: "Feed")
            return
        }
        
        let docRef = firestore.collection("videos").document(video.id)
        let listener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                LoggingService.error("Error listening to video \(video.id) updates: \(error.localizedDescription)", component: "Feed")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists,
                  let updatedVideo = Video(document: snapshot) else {
                LoggingService.error("No valid snapshot for video \(video.id)", component: "Feed")
                return
            }
            
            // Update the video in the local array if it has changed
            if let index = self.videos.firstIndex(where: { $0.id == updatedVideo.id }) {
                // Only update if there is a change in critical fields
                if self.videos[index].processingStatus != updatedVideo.processingStatus ||
                    self.videos[index].videoURL != updatedVideo.videoURL {
                    LoggingService.video("Updating video \(updatedVideo.id) in feed (status: \(updatedVideo.processingStatus.rawValue))", component: "Feed")
                    Task { @MainActor in
                        self.videos[index] = updatedVideo
                        // Update player view model if it exists
                        if let playerViewModel = self.playerViewModels[updatedVideo.id] {
                            playerViewModel.video = updatedVideo
                        }
                    }
                }
            }
        }
        
        videoListeners[video.id] = listener
        LoggingService.debug("Subscribed to updates for video \(video.id)", component: "Feed")
    }
    
    func preloadVideo(at index: Int) {
        guard index >= 0 && index < videos.count else {
            LoggingService.error("Invalid index for preloading", component: "Feed")
            return
        }
        
        let video = videos[index]
        
        // Only check if videoURL is empty
        if video.videoURL.isEmpty {
            LoggingService.debug("Skipping preload for video \(video.id) at index \(index) because videoURL is empty", component: "Feed")
            return
        }
        
        if preloadedPlayers[video.id] != nil {
            LoggingService.debug("Video already preloaded: \(video.id)", component: "Feed")
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("Invalid URL for video: \(video.id)", component: "Feed")
            return
        }
        
        LoggingService.debug("Preloading video at index \(index): \(video.id)", component: "Feed")
        
        preloadTasks[video.id]?.cancel()
        
        let preloadTask = Task<Void, Never>(priority: .userInitiated) {
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
                "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
                "AVAssetPreferredForwardBufferDurationKey": 2.0
            ])
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            playerItem.preferredPeakBitRate = 3_000_000
            
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = 0
            preloadedPlayers[video.id] = player
            
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    throw VideoPlayerError.assetNotPlayable
                }
                player.play()
                player.pause()
                LoggingService.success("Successfully preloaded video \(video.id) at index \(index)", component: "Feed")
            } catch {
                LoggingService.error("Failed to preload video \(video.id) at index \(index): \(error.localizedDescription)", component: "Feed")
                preloadedPlayers.removeValue(forKey: video.id)
            }
        }
        
        preloadTasks[video.id] = preloadTask
        cleanupPreloadedVideos(currentIndex: index)
    }
    
    private func cleanupPreloadedVideos(currentIndex: Int) {
        let validIndices = Set((currentIndex - preloadWindow)...(currentIndex + preloadWindow))
        let videosToKeep = validIndices.compactMap { index -> String? in
            guard index >= 0 && index < videos.count else { return nil }
            return videos[index].id
        }
        
        let videosToRemove = Set(preloadedPlayers.keys).subtracting(videosToKeep)
        
        for videoId in videosToRemove {
            if let player = preloadedPlayers[videoId] {
                player.pause()
                player.currentItem?.asset.cancelLoading()
                player.replaceCurrentItem(with: nil)
            }
            preloadedPlayers.removeValue(forKey: videoId)
            preloadTasks[videoId]?.cancel()
            preloadTasks.removeValue(forKey: videoId)
            LoggingService.debug("Cleaned up preloaded video: \(videoId)", component: "Feed")
        }
    }
} 