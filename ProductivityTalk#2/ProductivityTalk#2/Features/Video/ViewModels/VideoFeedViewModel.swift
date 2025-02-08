import Foundation
import FirebaseFirestore
import AVFoundation

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
        print("🎬 VideoFeed: Initialized with preload window of \(preloadWindow)")
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
                .whereField("processingStatus", isEqualTo: VideoProcessingStatus.ready.rawValue)
                .order(by: "hotScore", descending: true)
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
        guard !isFetching,
              let lastDocument = lastDocument else {
            print("⚠️ VideoFeed: Cannot fetch next batch - already fetching or no last document")
            return
        }
        
        isFetching = true
        print("🔍 VideoFeed: Fetching next batch of videos")
        
        do {
            let query = firestore.collection("videos")
                .whereField("processingStatus", isEqualTo: VideoProcessingStatus.ready.rawValue)
                .order(by: "hotScore", descending: true)
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDocument)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            
            let fetchedVideos = snapshot.documents.compactMap { document -> Video? in
                print("📄 VideoFeed: Processing document with ID: \(document.documentID)")
                return Video(document: document)
            }
            
            print("✅ VideoFeed: Fetched \(fetchedVideos.count) new videos")
            
            if !fetchedVideos.isEmpty {
                let nextIndex = self.videos.count
                self.videos.append(contentsOf: fetchedVideos)
                self.lastDocument = snapshot.documents.last
                
                // Create player view models for new videos
                for video in fetchedVideos {
                    if playerViewModels[video.id] == nil {
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                }
                
                // Preload the first video in the new batch
                preloadVideo(at: nextIndex)
            }
            
        } catch {
            print("❌ VideoFeed: Error fetching next batch: \(error)")
            self.error = error
        }
        
        isFetching = false
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
        
        // Create new preload task
        let preloadTask = Task {
            // Create asset with custom loading options
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetPreferPreciseDurationAndTimingKey": true,
                "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
            ])
            
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            
            // Enhanced buffer configuration
            playerItem.preferredForwardBufferDuration = 4.0
            playerItem.preferredMaximumResolution = .init(width: 1080, height: 1920)
            
            // Store the preloaded player
            preloadedPlayers[video.id] = player
            
            do {
                // Load essential properties asynchronously
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let duration = try await asset.load(.duration)
                        print("📊 VideoFeed: Loaded duration for video \(video.id): \(duration.seconds) seconds")
                    }
                    group.addTask {
                        let tracks = try await asset.load(.tracks)
                        print("📊 VideoFeed: Loaded \(tracks.count) tracks for video \(video.id)")
                    }
                    
                    try await group.waitForAll()
                }
                
                // Monitor playback buffer with improved logic
                let stream = AsyncStream<Bool> { continuation in
                    let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
                        if playerItem.isPlaybackLikelyToKeepUp && 
                           playerItem.status == .readyToPlay {
                            continuation.yield(true)
                            continuation.finish()
                        }
                    }
                    
                    continuation.onTermination = { @Sendable _ in
                        player.removeTimeObserver(observer)
                    }
                }
                
                for await isReady in stream {
                    if isReady {
                        print("✅ VideoFeed: Successfully preloaded video: \(video.id)")
                        break
                    }
                }
                
            } catch {
                print("❌ VideoFeed: Error preloading video: \(error)")
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
            preloadedPlayers.removeValue(forKey: videoId)
            preloadTasks[videoId]?.cancel()
            preloadTasks.removeValue(forKey: videoId)
            print("🧹 VideoFeed: Cleaned up preloaded video: \(videoId)")
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
} 