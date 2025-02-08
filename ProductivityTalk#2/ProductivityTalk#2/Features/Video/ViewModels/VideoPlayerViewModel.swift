import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation

@MainActor
class VideoPlayerViewModel: NSObject, ObservableObject {
    // Static property to track currently playing video
    private static var currentlyPlayingViewModel: VideoPlayerViewModel?
    
    @Published var video: Video
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var isLiked = false
    @Published var isSaved = false
    @Published var playerError: String?
    @Published var isInSecondBrain = false
    @Published private(set) var saveCount: Int
    @Published var isProcessing: Bool
    
    @Published private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private let firestore = Firestore.firestore()
    private var cleanupTask: Task<Void, Never>?
    private var processingStatusListener: ListenerRegistration?
    
    init(video: Video) {
        self.video = video
        self.saveCount = video.saveCount
        self.isProcessing = video.processingStatus != .ready
        super.init()
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
        setupProcessingStatusListener()
        
        // Handle async setup in a Task
        Task {
            await setupPlayer()
        }
        
        checkInteractionStatus()
    }
    
    deinit {
        // Use a weak reference to self in the cleanup task
        cleanupTask = Task { [weak self] in
            await self?.cleanup()
        }
        processingStatusListener?.remove()
    }
    
    private func setupProcessingStatusListener() {
        LoggingService.video("Setting up processing status listener for video \(video.id)", component: "Player")
        LoggingService.debug("Initial processing status: \(video.processingStatus.rawValue)", component: "Player")
        LoggingService.debug("Initial isProcessing value: \(isProcessing)", component: "Player")
        LoggingService.debug("Initial player state: \(String(describing: player))", component: "Player")
        
        processingStatusListener = firestore.collection("videos")
            .document(self.video.id)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else {
                    LoggingService.error("Self was deallocated in status listener", component: "Player")
                    return
                }
                
                if let error = error {
                    LoggingService.error("Error listening to processing status: \(error.localizedDescription)", component: "Player")
                    return
                }
                
                guard let document = documentSnapshot else {
                    LoggingService.error("No document snapshot in status listener", component: "Player")
                    return
                }
                
                LoggingService.debug("Received document update for video \(self.video.id)", component: "Player")
                LoggingService.debug("Document exists: \(document.exists)", component: "Player")
                
                guard let data = document.data(),
                      let statusRaw = data["processingStatus"] as? String,
                      let status = VideoProcessingStatus(rawValue: statusRaw) else {
                    LoggingService.error("Invalid processing status data for video \(self.video.id)", component: "Player")
                    LoggingService.debug("Document data: \(String(describing: document.data()))", component: "Player")
                    return
                }
                
                Task { @MainActor in
                    let wasProcessing = self.isProcessing
                    let oldStatus = self.video.processingStatus
                    
                    // Update video object with new status
                    self.video.processingStatus = status
                    
                    // Update isProcessing based on status
                    self.isProcessing = status != .ready
                    
                    LoggingService.video("Processing status changed for video \(self.video.id)", component: "Player")
                    LoggingService.debug("- Old status: \(oldStatus.rawValue)", component: "Player")
                    LoggingService.debug("- New status: \(status.rawValue)", component: "Player")
                    LoggingService.debug("- Was processing: \(wasProcessing)", component: "Player")
                    LoggingService.debug("- Is processing: \(self.isProcessing)", component: "Player")
                    
                    // If transitioning from processing to ready, ensure player is set up
                    if wasProcessing && !self.isProcessing {
                        LoggingService.video("🎬 Video ready - setting up player", component: "Player")
                        await self.setupPlayer()
                    }
                }
            }
    }
    
    private func setupPlayer() async {
        LoggingService.video("🎬 Starting player setup for video \(video.id)", component: "Player")
        LoggingService.debug("Video URL: \(video.videoURL)", component: "Player")
        LoggingService.debug("Processing status: \(video.processingStatus.rawValue)", component: "Player")
        LoggingService.debug("Thermal state before setup: \(ProcessInfo.processInfo.thermalState)", component: "Player")
        
        // Ensure cleanup is complete before setting up
        await cleanup()
        
        // Add a small delay after cleanup for audio session stability
        try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
        LoggingService.debug("⏱️ Post-cleanup delay completed for video \(video.id)", component: "Player")
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            LoggingService.debug("🔊 Audio session configured and activated for video \(video.id)", component: "Player")
        } catch {
            LoggingService.error("❌ Failed to configure audio session for video \(video.id): \(error)", component: "Player")
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for video \(video.id): \(video.videoURL)", component: "Player")
            return
        }
        
        LoggingService.debug("🔍 Creating AVPlayer with URL: \(url.absoluteString)", component: "Player")
        
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
            "AVAssetPreferredForwardBufferDurationKey": 2.0,
            "AVURLAssetHTTPHeaderFieldsKey": ["Range": "bytes=0-"]
        ])
        
        asset.resourceLoader.setDelegate(VideoResourceLoaderDelegate.shared, queue: DispatchQueue.global(qos: .userInitiated))
        
        let playerItem = AVPlayerItem(asset: asset)
        
        // Optimize playback settings
        playerItem.preferredForwardBufferDuration = 2.0
        playerItem.preferredPeakBitRate = 3_000_000 // 3 Mbps for good quality while maintaining speed
        playerItem.automaticallyPreservesTimeOffsetFromLive = false
        
        // Add performance optimization hints
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for optimal performance
        player.automaticallyWaitsToMinimizeStalling = false // We handle preloading ourselves
        player.volume = 0 // Start with volume at 0 to prevent audio bleed
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.preventsDisplaySleepDuringVideoPlayback = true
        
        // Set video gravity for better performance
        if let playerLayer = player.currentItem?.asset as? AVPlayerLayer {
            playerLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        }
        
        LoggingService.debug("⚙️ Player configured for video \(video.id) with initial volume 0", component: "Player")
        
        // Set up observers
        setupTimeObserver(for: player)
        setupStatusObserver(for: playerItem)
        setupNotificationObservers()
        
        // Add buffer monitoring
        setupBufferMonitoring(for: playerItem)
        
        LoggingService.debug("👀 Observers set up for video \(video.id)", component: "Player")
        
        // Update state
        self.player = player
        isPlaying = true
        
        LoggingService.video("✅ Player setup completed for video \(video.id)", component: "Player")
    }
    
    private func setupBufferMonitoring(for playerItem: AVPlayerItem) {
        // Monitor playback buffer
        let timeRangeObserver = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
            if let self {
                if let timeRange = item.loadedTimeRanges.first?.timeRangeValue {
                    let bufferedDuration = timeRange.duration.seconds
                    let bufferedStart = timeRange.start.seconds
                    LoggingService.debug("Buffer status - Duration: \(bufferedDuration)s, Start: \(bufferedStart)s", component: "Player")
                }
            }
        }
        
        // Store observer to prevent it from being deallocated
        statusObserver = timeRangeObserver
    }
    
    func cleanup() async {
        LoggingService.video("🔄 Starting cleanup for video \(video.id)", component: "Player")
        LoggingService.debug("Player state: \(String(describing: player))", component: "Player")
        LoggingService.debug("Is playing: \(isPlaying)", component: "Player")
        LoggingService.debug("Thermal state before cleanup: \(ProcessInfo.processInfo.thermalState)", component: "Player")
        
        // Remove observers first
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
            LoggingService.debug("📍 Removed time observer for video \(video.id)", component: "Player")
        }
        
        statusObserver?.invalidate()
        statusObserver = nil
        LoggingService.debug("📍 Removed status observer for video \(video.id)", component: "Player")
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
        LoggingService.debug("📍 Removed notification observers for video \(video.id)", component: "Player")
        
        // Clear currently playing reference if this is the current player
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            LoggingService.debug("📍 Clearing current player reference for video \(video.id)", component: "Player")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        
        // Ensure proper cleanup sequence
        if let player = player {
            LoggingService.debug("📍 Starting player cleanup sequence for video \(video.id)", component: "Player")
            LoggingService.debug("Current player volume: \(player.volume)", component: "Player")
            
            // Fade out audio first
            let fadeTime = 0.3
            let steps = 5
            let volumeDecrement = player.volume / Float(steps)
            
            for step in 0...steps {
                try? await Task.sleep(nanoseconds: UInt64(fadeTime * 1_000_000_000 / Double(steps)))
                player.volume = player.volume - volumeDecrement
                LoggingService.debug("📍 Fading volume: \(player.volume) for video \(video.id) (step \(step)/\(steps))", component: "Player")
            }
            
            player.pause()
            player.replaceCurrentItem(with: nil)
            LoggingService.debug("📍 Player paused and item removed for video \(video.id)", component: "Player")
            
            // Ensure audio session is properly handled
            do {
                let session = AVAudioSession.sharedInstance()
                if !session.isOtherAudioPlaying {
                    try session.setActive(false, options: [.notifyOthersOnDeactivation])
                    LoggingService.debug("📍 Audio session deactivated for video \(video.id)", component: "Player")
                }
            } catch {
                LoggingService.error("❌ Failed to deactivate audio session for video \(video.id): \(error)", component: "Player")
            }
            
            // Clear player reference
            self.player = nil
            self.isPlaying = false
            
            LoggingService.debug("📍 Completed player cleanup sequence for video \(video.id)", component: "Player")
            LoggingService.debug("Thermal state after cleanup: \(ProcessInfo.processInfo.thermalState)", component: "Player")
        } else {
            // If no player, just deactivate audio session
            do {
                let session = AVAudioSession.sharedInstance()
                if !session.isOtherAudioPlaying {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                    LoggingService.debug("📍 Audio session deactivated (no player) for video \(video.id)", component: "Player")
                }
            } catch {
                LoggingService.error("❌ Failed to deactivate audio session (no player) for video \(video.id): \(error)", component: "Player")
            }
        }
        
        LoggingService.video("✅ Completed cleanup for video \(video.id)", component: "Player")
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        LoggingService.debug("Setting up time observer for video \(video.id)", component: "Player")
        
        // Remove any existing time observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Add new time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            LoggingService.debug("Time update: \(time.seconds)", component: "Player")
        }
    }
    
    private func setupStatusObserver(for playerItem: AVPlayerItem) {
        LoggingService.debug("Setting up status observer for video \(video.id)", component: "Player")
        
        // Remove any existing status observer
        statusObserver?.invalidate()
        statusObserver = nil
        
        // Add new status observer using modern KVO
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    LoggingService.debug("Player item ready to play for video \(self.video.id)", component: "Player")
                case .failed:
                    if let error = item.error {
                        LoggingService.error("Player item failed for video \(self.video.id): \(error.localizedDescription)", component: "Player")
                        self.playerError = error.localizedDescription
                    }
                case .unknown:
                    LoggingService.debug("Player item status unknown for video \(self.video.id)", component: "Player")
                @unknown default:
                    LoggingService.debug("Player item status unknown (default) for video \(self.video.id)", component: "Player")
                }
            }
        }
    }
    
    private func setupNotificationObservers() {
        LoggingService.debug("Setting up notification observers for video \(video.id)", component: "Player")
        
        // Remove any existing observers first
        NotificationCenter.default.removeObserver(self)
        
        // Add observer for when item reaches end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
    }
    
    @objc private func playerItemDidReachEnd() {
        LoggingService.debug("🔄 Video reached end, initiating loop", component: "Player")
        LoggingService.debug("🔊 Audio State before loop - Volume: \(player?.volume ?? 0), Muted: \(isMuted)", component: "Player")
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
        
        // Reapply audio fade-in if not muted
        if !isMuted {
            // Create a Task to handle the async fadeInAudio call
            Task { @MainActor in
                await fadeInAudio()
            }
            LoggingService.debug("🔊 Re-applying audio fade in on loop", component: "Player")
        }
        
        LoggingService.debug("🔄 Playback restarted with audio state - Volume: \(player?.volume ?? 0), Muted: \(isMuted)", component: "Player")
    }
    
    func togglePlayback() {
        LoggingService.debug("Toggling playback for video \(video.id)", component: "Player")
        if isPlaying {
            player?.pause()
            isPlaying = false
            LoggingService.debug("Paused playback", component: "Player")
        } else {
            // Stop any currently playing video before playing this one
            if let currentlyPlaying = VideoPlayerViewModel.currentlyPlayingViewModel,
               currentlyPlaying !== self {
                LoggingService.debug("Stopping currently playing video before starting new one", component: "Player")
                // Ensure proper cleanup of previous video
                Task { @MainActor in
                    await currentlyPlaying.cleanup()
                    
                    // Wait for cleanup to complete before starting new video
                    guard let player = self.player else { return }
                    player.volume = 0 // Start with volume at 0
                    player.play()
                    VideoPlayerViewModel.currentlyPlayingViewModel = self
                    self.isPlaying = true
                    // Fade in audio
                    await fadeInAudio()
                    LoggingService.debug("Started playback after cleanup with fade-in", component: "Player")
                }
            } else {
                player?.volume = 0 // Start with volume at 0
                player?.play()
                VideoPlayerViewModel.currentlyPlayingViewModel = self
                isPlaying = true
                // Fade in audio
                Task { @MainActor in
                    await fadeInAudio()
                }
                LoggingService.debug("Started playback with fade-in", component: "Player")
            }
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : 1
        LoggingService.debug("Audio \(isMuted ? "muted" : "unmuted")", component: "Player")
    }
    
    func checkInteractionStatus() {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ VideoPlayer: No authenticated user")
            return
        }
        
        print("🔍 VideoPlayer: Checking interaction status for user: \(userId)")
        
        // Check if liked
        Task {
            do {
                let likeDoc = try await firestore
                    .collection("videos")
                    .document(video.id)
                    .collection("likes")
                    .document(userId)
                    .getDocument()
                
                isLiked = likeDoc.exists
                print("✅ VideoPlayer: Like status checked - isLiked: \(isLiked)")
            } catch {
                print("❌ VideoPlayer: Error checking like status: \(error.localizedDescription)")
            }
        }
        
        // Check if saved
        Task {
            do {
                let saveDoc = try await firestore
                    .collection("users")
                    .document(userId)
                    .collection("savedVideos")
                    .document(video.id)
                    .getDocument()
                
                isSaved = saveDoc.exists
                print("✅ VideoPlayer: Save status checked - isSaved: \(isSaved)")
            } catch {
                print("❌ VideoPlayer: Error checking save status: \(error.localizedDescription)")
            }
        }
        
        // Check Second Brain status
        checkSecondBrainStatus()
    }
    
    private func checkSecondBrainStatus() {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("No authenticated user", component: "Player")
            return
        }
        
        Task {
            do {
                let secondBrainQuery = try await firestore.collection("users")
                    .document(userId)
                    .collection("secondBrain")
                    .whereField("videoId", isEqualTo: video.id)
                    .limit(to: 1)
                    .getDocuments()
                
                await MainActor.run {
                    self.isInSecondBrain = !secondBrainQuery.documents.isEmpty
                }
                LoggingService.debug("Second Brain status checked - isInSecondBrain: \(self.isInSecondBrain)", component: "Player")
            } catch {
                LoggingService.error("Error checking Second Brain status: \(error.localizedDescription)", component: "Player")
            }
        }
    }
    
    func toggleLike() async {
        do {
            isLiked.toggle()
            let newLikeCount = isLiked ? video.likeCount + 1 : video.likeCount - 1
            
            // Create a Sendable dictionary
            let updateData: [String: Any] = ["likeCount": newLikeCount]
            
            try await firestore.collection("videos").document(video.id).updateData(updateData)
            
            video.likeCount = newLikeCount
            LoggingService.success("Updated like status for video \(video.id)", component: "Player")
        } catch {
            isLiked.toggle() // Revert on failure
            LoggingService.error("Failed to toggle like: \(error.localizedDescription)", component: "Player")
        }
    }
    
    func toggleSave() async {
        do {
            isSaved.toggle()
            let newSaveCount = isSaved ? video.saveCount + 1 : video.saveCount - 1
            
            // Create a Sendable dictionary
            let updateData: [String: Any] = ["saveCount": newSaveCount]
            
            try await firestore.collection("videos").document(video.id).updateData(updateData)
            
            video.saveCount = newSaveCount
            LoggingService.success("Updated save status for video \(video.id)", component: "Player")
        } catch {
            isSaved.toggle() // Revert on failure
            LoggingService.error("Failed to toggle save: \(error.localizedDescription)", component: "Player")
        }
    }
    
    func saveToSecondBrain() async throws {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        LoggingService.video("Saving video to Second Brain", component: "Player")
        
        let secondBrainRef = firestore.collection("users")
            .document(userId)
            .collection("secondBrain")
            .document()
        
        let data: [String: Any] = [
            "videoId": video.id,
            "title": video.title,
            "description": video.description,
            "thumbnailURL": video.thumbnailURL ?? "",
            "videoURL": video.videoURL,
            "transcript": video.transcript as Any? ?? "",
            "extractedQuotes": video.extractedQuotes ?? [],
            "createdAt": Timestamp(),
            "tags": video.tags
        ]
        
        do {
            // First, check if the video document exists
            let videoDoc = try await firestore.collection("videos").document(video.id).getDocument()
            
            if !videoDoc.exists {
                LoggingService.error("Video document does not exist: \(video.id)", component: "Player")
                throw NSError(domain: "VideoPlayer", 
                            code: -2, 
                            userInfo: [NSLocalizedDescriptionKey: "Video no longer exists"])
            }
            
            // Start a batch write to ensure atomicity
            let batch = firestore.batch()
            
            // Add to Second Brain
            batch.setData(data, forDocument: secondBrainRef)
            
            // Update video save count
            batch.updateData([
                "saveCount": FieldValue.increment(Int64(1))
            ], forDocument: firestore.collection("videos").document(video.id))
            
            // Commit the batch
            try await batch.commit()
            
            await MainActor.run {
                self.isInSecondBrain = true
                self.video.saveCount += 1
            }
            
            LoggingService.success("Successfully saved video to Second Brain", component: "Player")
        } catch {
            LoggingService.error("Failed to save to Second Brain: \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    @MainActor
    func shareVideo() {
        print("📤 VideoPlayer: Sharing video with ID: \(video.id)")
        guard let url = URL(string: video.videoURL) else {
            print("❌ VideoPlayer: Invalid video URL for sharing")
            return
        }
        
        let activityItems: [Any] = [
            "Check out this video!",
            url
        ]
        
        Task { @MainActor in
            let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(activityVC, animated: true)
            }
        }
    }
    
    func updateSaveCount(increment: Bool) {
        if increment {
            saveCount += 1
            isInSecondBrain = true
        } else {
            saveCount -= 1
            isInSecondBrain = false
        }
        video.saveCount = saveCount
    }
    
    private func fadeInAudio() async {
        guard let player = player, !isMuted else { return }
        
        LoggingService.debug("🔊 Starting audio fade in for video \(video.id)", component: "Player")
        let fadeTime = 0.3
        let steps = 5
        let targetVolume: Float = 1.0
        let startVolume: Float = 0.0
        
        for i in 0...steps {
            let delay = fadeTime * Double(i) / Double(steps)
            let volume = startVolume + (targetVolume - startVolume) * Float(i) / Float(steps)
            
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            player.volume = volume
            
            if i == steps {
                LoggingService.debug("🔊 Audio fade in completed for video \(video.id)", component: "Player")
            }
        }
    }
} 