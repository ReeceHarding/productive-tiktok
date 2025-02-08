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
        guard !isFetching,
              let lastDocument = lastDocument else {
            print("⚠️ VideoFeed: Cannot fetch next batch - already fetching or no last document")
            return
        }
        
        isFetching = true
        print("🔍 VideoFeed: Fetching next batch of videos")
        
        do {
            let query = firestore.collection("videos")
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
        
        // Use AVURLAsset instead of AVAsset(url:)
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Store the preloaded player
        preloadedPlayers[video.id] = player
        
        // Configure buffer size
        playerItem.preferredForwardBufferDuration = 3
        
        // Load asset asynchronously
        Task {
            do {
                // Load the asset's duration
                _ = try await asset.load(.duration)
                
                // Monitor playback buffer
                let stream = AsyncStream<Void> { continuation in
                    Task {
                        while !Task.isCancelled {
                            if playerItem.isPlaybackLikelyToKeepUp {
                                continuation.finish()
                                break
                            } else {
                                continuation.yield(())
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            }
                        }
                    }
                }
                
                for try await _ in stream {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                
                print("✅ VideoFeed: Successfully preloaded video: \(video.id)")
            } catch {
                print("❌ VideoFeed: Error preloading video: \(error)")
                preloadedPlayers.removeValue(forKey: video.id)
            }
        }
        
        // Clean up old preloaded videos if we have too many
        if preloadedPlayers.count > 3 {
            let oldestKeys = Array(preloadedPlayers.keys.prefix(preloadedPlayers.count - 3))
            for key in oldestKeys {
                preloadedPlayers.removeValue(forKey: key)
                print("🧹 VideoFeed: Cleaned up preloaded video: \(key)")
            }
        }
    }
    
    func getPreloadedPlayer(for videoId: String) -> AVPlayer? {
        return preloadedPlayers[videoId]
    }
} 