import Foundation
import FirebaseFirestore
import AVFoundation

enum VideoPlayerError: Error {
    case assetNotPlayable
}

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var playerViewModels: [String: VideoPlayerViewModel] = [:]
    
    private let firestore = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private var isFetching = false
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private let batchSize = 5
    private let preloadWindow = 2 // Number of videos to preload ahead and behind
    private var preloadQueue = OperationQueue()
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    
    init() {
        preloadQueue.maxConcurrentOperationCount = 2
        LoggingService.video("Initialized with preload window of \(preloadWindow)", component: "Feed")
    }
    
    func fetchVideos() async {
        guard !isFetching else {
            print("⚠️ VideoFeed: Already fetching videos")
            return
        }
        
        isFetching = true
        print("🔍 VideoFeed: Fetching initial batch of videos")
        
        do {
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            
            let fetchedVideos = snapshot.documents.compactMap { document -> Video? in
                print("📄 VideoFeed: Processing document with ID: \(document.documentID)")
                return Video(document: document)
            }
            
            print("✅ VideoFeed: Fetched \(fetchedVideos.count) videos")
            self.videos = fetchedVideos
            self.lastDocument = snapshot.documents.last
            
            // Create player view models for each video
            for video in fetchedVideos {
                if playerViewModels[video.id] == nil {
                    playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                }
            }
            
            // Preload the first two videos
            if !fetchedVideos.isEmpty {
                preloadVideo(at: 0)
                if fetchedVideos.count > 1 {
                    preloadVideo(at: 1)
                }
            }
            
        } catch {
            print("❌ VideoFeed: Error fetching videos: \(error)")
            self.error = error
        }
        
        isFetching = false
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
            let newVideos = snapshot.documents.compactMap { Video(document: $0) }
            
            if !newVideos.isEmpty {
                videos.append(contentsOf: newVideos)
                lastDocument = snapshot.documents.last
                LoggingService.success("Fetched \(newVideos.count) new videos", component: "Feed")
                
                // Preload videos within the window
                for video in newVideos {
                    preloadVideo(for: video)
                }
            } else {
                LoggingService.info("No more videos to fetch", component: "Feed")
            }
        } catch {
            LoggingService.error("Failed to fetch videos: \(error.localizedDescription)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
        isLoading = false
    }
    
    private func preloadVideo(for video: Video) {
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("Invalid video URL for \(video.id)", component: "Feed")
            return
        }
        
        let preloadTask = Task<Void, Never> {
            // Create asset with optimized loading options
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
                "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
                "AVURLAssetHTTPHeaderFieldsKey": ["Range": "bytes=0-"],
                "AVAssetPreferredForwardBufferDurationKey": 2.0
            ])
            
            // Configure asset for optimal loading using the shared delegate
            asset.resourceLoader.setDelegate(VideoResourceLoaderDelegate.shared, queue: .global(qos: .userInitiated))
            
            // Create optimized player item with resource conservation
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            playerItem.preferredPeakBitRate = 3_000_000 // 3 Mbps for good quality while maintaining speed
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = 0
            player.isMuted = true
            player.appliesMediaSelectionCriteriaAutomatically = false
            
            // Store the preloaded player
            preloadedPlayers[video.id] = player
            
            do {
                // Load essential properties asynchronously with timeout
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask(priority: .userInitiated) {
                        try await self.withTimeout(seconds: 5.0) { () -> Void in
                            let isPlayable = try await asset.load(.isPlayable)
                            guard isPlayable else {
                                throw VideoPlayerError.assetNotPlayable
                            }
                        }
                    }
                    
                    try await group.waitForAll()
                }
                
                // Start minimal buffering
                player.play()
                try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
                player.pause()
                
                LoggingService.debug("✅ Successfully preloaded video \(video.id)", component: "Feed")
            } catch {
                LoggingService.error("Failed to preload video \(video.id): \(error.localizedDescription)", component: "Feed")
                preloadedPlayers.removeValue(forKey: video.id)
            }
        }
        
        preloadTasks[video.id] = preloadTask
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try await operation()
            }
            
            group.addTask(priority: .userInitiated) {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            guard let result = try await group.next() else {
                throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation completed with no result"])
            }
            group.cancelAll()
            return result
        }
    }
    
    func preloadVideo(at index: Int) {
        guard index >= 0 && index < videos.count else {
            print("⚠️ VideoFeed: Invalid index for preloading")
            return
        }
        
        let video = videos[index]
        
        // Check if already preloaded
        if preloadedPlayers[video.id] != nil {
            print("ℹ️ VideoFeed: Video already preloaded: \(video.id)")
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            print("❌ VideoFeed: Invalid URL for video: \(video.id)")
            return
        }
        
        print("⏳ VideoFeed: Preloading video: \(video.id)")
        
        // Cancel any existing preload task for this video
        preloadTasks[video.id]?.cancel()
        
        // Create new preload task with high priority
        let preloadTask = Task<Void, Never>(priority: .userInitiated) {
            // Create asset with optimized loading options
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
                "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
                "AVURLAssetHTTPHeaderFieldsKey": ["Range": "bytes=0-"],
                "AVAssetPreferredForwardBufferDurationKey": 2.0
            ])
            
            // Configure asset for optimal loading using the shared delegate
            asset.resourceLoader.setDelegate(VideoResourceLoaderDelegate.shared, queue: .global(qos: .userInitiated))
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            playerItem.preferredPeakBitRate = 3_000_000
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
            
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = 0
            player.isMuted = true
            
            // Store the preloaded player immediately
            preloadedPlayers[video.id] = player
            
            do {
                // Load minimal required properties
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    throw VideoPlayerError.assetNotPlayable
                }
                
                // Start buffering immediately
                player.play()
                player.pause()
                
                LoggingService.debug("✅ Successfully preloaded video \(video.id)", component: "Feed")
            } catch {
                LoggingService.error("Failed to preload video \(video.id): \(error.localizedDescription)", component: "Feed")
                preloadedPlayers.removeValue(forKey: video.id)
            }
        }
        
        preloadTasks[video.id] = preloadTask
        
        // Cleanup old preloaded videos
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
                // Ensure proper cleanup sequence
                player.pause()
                player.currentItem?.asset.cancelLoading()
                player.replaceCurrentItem(with: nil)
            }
            preloadedPlayers.removeValue(forKey: videoId)
            preloadTasks[videoId]?.cancel()
            preloadTasks.removeValue(forKey: videoId)
            LoggingService.debug("Cleaned up preloaded video: \(videoId)", component: "Feed")
        }
        
        // Check memory pressure
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            // Reduce preload window temporarily
            let reducedWindow = max(1, preloadWindow - 1)
            let extraVideosToRemove = Set(preloadedPlayers.keys).filter { videoId in
                guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return true }
                return abs(index - currentIndex) > reducedWindow
            }
            
            for videoId in extraVideosToRemove {
                if let player = preloadedPlayers[videoId] {
                    player.pause()
                    player.currentItem?.asset.cancelLoading()
                    player.replaceCurrentItem(with: nil)
                }
                preloadedPlayers.removeValue(forKey: videoId)
                preloadTasks[videoId]?.cancel()
                preloadTasks.removeValue(forKey: videoId)
                LoggingService.debug("Cleaned up extra video due to memory pressure: \(videoId)", component: "Feed")
            }
        }
    }
    
    func preloadAdjacentVideos(currentIndex: Int) {
        print("🔄 VideoFeed: Preloading adjacent videos for index \(currentIndex)")
        
        // Preload next videos
        for offset in 1...preloadWindow {
            let nextIndex = currentIndex + offset
            if nextIndex < videos.count {
                preloadVideo(at: nextIndex)
            }
        }
        
        // Preload previous videos
        for offset in 1...preloadWindow {
            let prevIndex = currentIndex - offset
            if prevIndex >= 0 {
                preloadVideo(at: prevIndex)
            }
        }
    }
    
    func getPreloadedPlayer(for videoId: String) -> AVPlayer? {
        return preloadedPlayers[videoId]
    }
    
    func cancelPreload(for videoId: String) {
        preloadTasks[videoId]?.cancel()
        if let player = preloadedPlayers[videoId] {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        preloadTasks.removeValue(forKey: videoId)
        preloadedPlayers.removeValue(forKey: videoId)
        LoggingService.debug("Cancelled preload for video \(videoId)", component: "Feed")
    }
} 