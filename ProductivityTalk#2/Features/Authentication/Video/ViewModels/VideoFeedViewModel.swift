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
            LoggingService.error("🚫 Fetch already in progress", component: "Feed")
            return
        }
        
        isFetching = true
        isLoading = true
        error = nil
        
        LoggingService.video("🎥 Initiating video feed fetch", component: "Feed")
        
        do {
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            LoggingService.debug("📄 Retrieved \(snapshot.documents.count) documents", component: "Feed")
            
            var fetchedVideos: [Video] = []
            
            for document in snapshot.documents {
                LoggingService.debug("🔍 Processing document: \(document.documentID)", component: "Feed")
                if let video = Video(document: document),
                   video.processingStatus == .ready,
                   !video.videoURL.isEmpty {
                    LoggingService.debug("✅ Adding ready video: \(video.id) to feed", component: "Feed")
                    fetchedVideos.append(video)
                    subscribeToUpdates(for: video)
                    
                    if playerViewModels[video.id] == nil {
                        LoggingService.debug("🎮 Creating new player view model for video \(video.id)", component: "Feed")
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                } else {
                    LoggingService.debug("⏳ Skipping video \(document.documentID) - Status: \(Video(document: document)?.processingStatus.rawValue ?? "unknown")", component: "Feed")
                }
            }
            
            LoggingService.success("✨ Successfully fetched \(fetchedVideos.count) ready videos", component: "Feed")
            self.videos = fetchedVideos
            self.lastDocument = snapshot.documents.last
            
            // Preload optimization
            if !fetchedVideos.isEmpty {
                LoggingService.debug("🔄 Starting preload for initial videos", component: "Feed")
                await preloadVideo(at: 0)
                if fetchedVideos.count > 1 {
                    await preloadVideo(at: 1)
                }
            }
            
        } catch {
            LoggingService.error("❌ Failed to fetch videos: \(error)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
        isLoading = false
    }
    
    func fetchNextBatch() async {
        guard !isFetching, let lastDoc = lastDocument else { return }
        isFetching = true
        
        do {
            LoggingService.video("Fetching next batch of \(batchSize) videos", component: "Feed")
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: batchSize)
            
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
    }
    
    private func subscribeToUpdates(for video: Video) {
        if videoListeners[video.id] != nil {
            LoggingService.debug("🔄 Listener already exists for video \(video.id)", component: "Feed")
            return
        }
        
        LoggingService.debug("👂 Setting up new listener for video \(video.id)", component: "Feed")
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
    
    func preloadVideo(at index: Int) async {
        guard index >= 0 && index < videos.count else {
            LoggingService.error("Invalid index \(index) for preloading", component: "Feed")
            return
        }
        
        let video = videos[index]
        
        // Cancel any existing preload task for this video
        preloadTasks[video.id]?.cancel()
        
        // Create a new background task for preloading
        let preloadTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // Get the player view model for this video
            guard let playerViewModel = await MainActor.run(body: { self.playerViewModels[video.id] }) else {
                return
            }
            
            // Preload the video in the background
            await playerViewModel.preloadVideo(video)
            
            LoggingService.success("Successfully preloaded video at index \(index)", component: "Feed")
        }
        
        preloadTasks[video.id] = preloadTask
    }
    
    func preloadAdjacentVideos(currentIndex: Int) async {
        LoggingService.debug("Preloading adjacent videos for index \(currentIndex)", component: "Feed")
        
        // Preload next videos
        for offset in 1...preloadWindow {
            let nextIndex = currentIndex + offset
            if nextIndex < videos.count {
                await preloadVideo(at: nextIndex)
            }
        }
        
        // Preload previous videos
        for offset in 1...preloadWindow {
            let prevIndex = currentIndex - offset
            if prevIndex >= 0 {
                await preloadVideo(at: prevIndex)
            }
        }
    }
    
    // MARK: - Audio Control
    /// Pauses all VideoPlayerViewModel instances except for the one whose video id matches currentVideoId.
    /// This ensures that only one video plays audio at a time.
    func pauseAllExcept(videoId: String) async {
        LoggingService.debug("Pausing all players except video \(videoId)", component: "FeedVM")
        for (id, playerVM) in playerViewModels {
            if id != videoId {
                await playerVM.pausePlayback()
                LoggingService.debug("Paused player for video \(id)", component: "FeedVM")
            }
        }
    }
} 