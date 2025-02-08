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
        setupPlayer()
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
                        self.setupPlayer()
                    }
                }
            }
    }
    
    func cleanup() {
        LoggingService.video("🎬 Starting cleanup for video \(video.id)", component: "Player")
        LoggingService.debug("🔊 Audio State - isPlaying: \(isPlaying), isMuted: \(isMuted)", component: "Player")
        
        // Remove observers first
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
            LoggingService.debug("🎵 Removed time observer", component: "Player")
        }
        
        statusObserver?.invalidate()
        statusObserver = nil
        LoggingService.debug("🎵 Removed status observer", component: "Player")
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
        LoggingService.debug("🎵 Removed notification observers", component: "Player")
        
        // Clear currently playing reference if this is the current player
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        
        // Fade out audio and stop player
        if let player = player {
            // Fade out audio first
            let fadeTime = 0.3
            let steps = 5
            let volumeDecrement = player.volume / Float(steps)
            
            for i in 0...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + fadeTime * Double(i) / Double(steps)) {
                    player.volume = player.volume - volumeDecrement
                }
            }
            
            // After fade out, stop player
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeTime) {
                player.pause()
                player.replaceCurrentItem(with: nil)
                LoggingService.debug("🔇 Player paused and item removed", component: "Player")
            }
        }
        
        player = nil
        isPlaying = false
        
        // Deactivate audio session if no other playback is active
        do {
            let session = AVAudioSession.sharedInstance()
            if !session.isOtherAudioPlaying {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                LoggingService.debug("🔇 Audio session deactivated", component: "Player")
            }
        } catch {
            LoggingService.error("🔇 Failed to deactivate audio session: \(error.localizedDescription)", component: "Player")
        }
        
        LoggingService.debug("🎬 Completed cleanup for video \(video.id)", component: "Player")
    }
    
    func setupPlayer() {
        // Skip setup if we have no URL
        if video.videoURL.isEmpty {
            LoggingService.debug("🔍 Skipping player setup - no URL available", component: "Player")
            return
        }
        
        LoggingService.video("🎬 Starting player setup for video \(video.id)", component: "Player")
        LoggingService.debug("Video URL: \(video.videoURL)", component: "Player")
        
        // Clean up old player first
        cleanup()
        
        // Configure audio session only if not already active
        do {
            let session = AVAudioSession.sharedInstance()
            if !session.isOtherAudioPlaying {
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                LoggingService.debug("🔊 Audio session activated for video playback", component: "Player")
            }
        } catch {
            LoggingService.error("🔇 Audio configuration failed: \(error.localizedDescription)", component: "Player")
        }

        guard let videoURL = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid video URL for \(video.id): \(video.videoURL)", component: "Player")
            return
        }
        
        // Create new player with the video asset
        let asset = AVURLAsset(url: videoURL)
        
        // Load asset keys asynchronously before creating player item
        Task {
            do {
                // Load essential properties
                try await asset.load(.isPlayable)
                
                guard asset.isPlayable else {
                    LoggingService.error("❌ Asset is not playable for video \(video.id)", component: "Player")
                    await MainActor.run {
                        self.playerError = "Video cannot be played"
                    }
                    return
                }
                
                await MainActor.run {
                    let playerItem = AVPlayerItem(asset: asset)
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    
                    // Start with audio muted but ready
                    newPlayer.volume = 0
                    newPlayer.isMuted = false  // Changed to false to allow volume control
                    
                    // Configure for looping
                    newPlayer.actionAtItemEnd = .none
                    
                    // Set new player
                    self.player = newPlayer
                    
                    // Add item status observer
                    self.statusObserver = playerItem.observe(\.status) { [weak self] item, _ in
                        guard let self = self else { return }
                        
                        Task { @MainActor in
                            switch item.status {
                            case .readyToPlay:
                                LoggingService.success("✅ PlayerItem ready to play", component: "Player")
                                if !self.isPlaying {
                                    // Only start playing if we're the current video
                                    if VideoPlayerViewModel.currentlyPlayingViewModel === self {
                                        self.player?.play()
                                        self.player?.rate = 1.0
                                        self.isPlaying = true
                                        
                                        // Always fade in audio when starting playback
                                        if !self.isMuted {
                                            self.fadeInAudio()
                                            LoggingService.debug("🔊 Fading in audio", component: "Player")
                                        }
                                        LoggingService.debug("Started playback", component: "Player")
                                    }
                                }
                            case .failed:
                                if let error = item.error {
                                    LoggingService.error("❌ PlayerItem failed: \(error.localizedDescription)", component: "Player")
                                    self.playerError = error.localizedDescription
                                }
                            case .unknown:
                                LoggingService.debug("⚠️ PlayerItem status unknown", component: "Player")
                            @unknown default:
                                break
                            }
                        }
                    }
                    
                    // Add notification observer for looping
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(self.playerItemDidReachEnd),
                        name: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem
                    )
                }
            } catch {
                LoggingService.error("❌ Failed to load asset: \(error.localizedDescription)", component: "Player")
                await MainActor.run {
                    self.playerError = error.localizedDescription
                }
            }
        }
    }
    
    private func setupRateObserver(for player: AVPlayer) {
        LoggingService.debug("Setting up rate observer for player", component: "Player")
        
        // Remove any existing rate observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Add new rate observer using modern KVO
        let rateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] player, change in
            guard let self = self,
                  let newRate = change.newValue,
                  let oldRate = change.oldValue else { return }
            
            Task { @MainActor in
                LoggingService.debug("🎮 Playback rate changed: \(oldRate) -> \(newRate)", component: "Player")
                
                if newRate == 0 && self.isPlaying {
                    LoggingService.debug("⚠️ Playback stopped unexpectedly, forcing resume", component: "Player")
                    player.play()
                    player.rate = 1.0
                }
            }
        }
        
        // Store the observer to prevent it from being deallocated
        statusObserver = rateObserver
    }
    
    @objc private func playerItemDidReachEnd() {
        LoggingService.debug("🔄 Video reached end, initiating loop", component: "Player")
        LoggingService.debug("🔊 Audio State before loop - Volume: \(player?.volume ?? 0), Muted: \(isMuted)", component: "Player")
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
        
        // Reapply audio fade-in if not muted
        if !isMuted {
            fadeInAudio()
            LoggingService.debug("🔊 Re-applying audio fade in on loop", component: "Player")
        }
        
        LoggingService.debug("🔊 Playback restarted with audio state - Volume: \(player?.volume ?? 0), Muted: \(isMuted)", component: "Player")
    }
    
    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            // Stop any currently playing video before playing this one
            if let currentlyPlaying = VideoPlayerViewModel.currentlyPlayingViewModel,
               currentlyPlaying !== self {
                currentlyPlaying.player?.pause()
                currentlyPlaying.isPlaying = false
            }
            player?.play()
            VideoPlayerViewModel.currentlyPlayingViewModel = self
        }
        isPlaying.toggle()
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
            "thumbnailURL": video.thumbnailURL,
            "videoURL": video.videoURL,
            "transcript": video.transcript ?? "",
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
    
    private func fadeInAudio() {
        guard let player = player else { return }
        
        // Start from current volume
        let startVolume = player.volume
        let targetVolume: Float = 1.0
        let steps = 10
        let fadeTime = 0.3 // Total fade duration in seconds
        
        LoggingService.debug("🔊 Starting audio fade in from \(startVolume) to \(targetVolume)", component: "Player")
        
        for i in 0...steps {
            let delay = fadeTime * Double(i) / Double(steps)
            let volume = startVolume + (targetVolume - startVolume) * Float(i) / Float(steps)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                player.volume = volume
                if i == steps {
                    LoggingService.debug("🔊 Audio fade in completed", component: "Player")
                }
            }
        }
    }
} 