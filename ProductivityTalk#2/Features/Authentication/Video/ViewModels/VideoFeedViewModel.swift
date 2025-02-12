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
    private let preloadWindow = 3 // Increased from 2 to 3 for smoother scrolling
    private var preloadQueue = OperationQueue()
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private var loadingStates: [String: Bool] = [:]
    
    // Dictionary to hold snapshot listeners for each video document
    private var videoListeners: [String: ListenerRegistration] = [:]
    
    public init() {
        preloadQueue.maxConcurrentOperationCount = 3 // Increased from 2 to 3
        LoggingService.video("Initialized with preload window of \(preloadWindow)", component: "Feed")
    }
    
    deinit {
        // Remove all snapshot listeners when the feed view model is deallocated
        for (videoId, listener) in videoListeners {
            LoggingService.debug("Removing video listener for video \(videoId)", component: "Feed")
            listener.remove()
        }
    }
    
    public func fetchVideos() async {
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
            
            // Pre-create all player view models in parallel
            await withTaskGroup(of: Void.self) { group in
                for document in snapshot.documents {
                    group.addTask {
                        if let video = Video(document: document),
                           video.processingStatus == .ready,
                           !video.videoURL.isEmpty {
                            await MainActor.run {
                                if self.playerViewModels[video.id] == nil {
                                    self.playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                                    self.loadingStates[video.id] = true
                                }
                                fetchedVideos.append(video)
                            }
                        }
                    }
                }
            }
            
            LoggingService.success("Fetched \(fetchedVideos.count) ready videos", component: "Feed")
            self.videos = fetchedVideos
            self.lastDocument = snapshot.documents.last
            
            // Preload first three videos immediately
            if !fetchedVideos.isEmpty {
                for i in 0..<min(3, fetchedVideos.count) {
                    await preloadVideo(at: i)
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
                    let documentData = document.data()
                    LoggingService.debug("Document data: \(documentData)", component: "Feed")
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
            
            guard let snapshot = snapshot else {
                LoggingService.error("No snapshot received for video \(video.id)", component: "Feed")
                return
            }
            
            guard snapshot.exists else {
                LoggingService.error("Document does not exist for video \(video.id)", component: "Feed")
                return
            }
            
            guard let updatedVideo = Video(document: snapshot) else {
                LoggingService.error("Could not parse video document for \(video.id)", component: "Feed")
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
        LoggingService.debug("Starting preload for video \(video.id) at index \(index)", component: "Feed")
        
        // Cancel any existing preload task for this video
        preloadTasks[video.id]?.cancel()
        
        // Create a new background task for preloading
        let preloadTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else {
                LoggingService.error("Self reference lost during preload of video \(video.id)", component: "Feed")
                return
            }
            
            // Get the player view model for this video
            guard let playerViewModel = await MainActor.run(body: { self.playerViewModels[video.id] }) else {
                LoggingService.error("No player view model found for video \(video.id)", component: "Feed")
                return
            }
            
            do {
                // Preload the video in the background
                try await playerViewModel.preloadVideo(video)
                LoggingService.success("Successfully preloaded video \(video.id) at index \(index)", component: "Feed")
            } catch {
                LoggingService.error("Failed to preload video \(video.id): \(error)", component: "Feed")
            }
        }
        
        preloadTasks[video.id] = preloadTask
    }
    
    func preloadAdjacentVideos(currentIndex: Int) async {
        LoggingService.debug("Preloading adjacent videos for index \(currentIndex)", component: "Feed")
        
        // Preload next videos
        for offset in 1...preloadWindow {
            let nextIndex = currentIndex + offset
            if nextIndex < videos.count {
                LoggingService.debug("Preloading next video at index \(nextIndex)", component: "Feed")
                await preloadVideo(at: nextIndex)
            }
        }
        
        // Preload previous videos
        for offset in 1...preloadWindow {
            let prevIndex = currentIndex - offset
            if prevIndex >= 0 {
                LoggingService.debug("Preloading previous video at index \(prevIndex)", component: "Feed")
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