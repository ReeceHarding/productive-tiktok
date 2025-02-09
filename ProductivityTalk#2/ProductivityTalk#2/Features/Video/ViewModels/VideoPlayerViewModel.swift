import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI

@MainActor
public class VideoPlayerViewModel: ObservableObject {
    // Static property to track currently playing video
    private static var currentlyPlayingViewModel: VideoPlayerViewModel?
    
    @Published public var video: Video
    @Published public var player: AVPlayer?
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var showBrainAnimation = false
    @Published public var brainAnimationPosition: CGPoint = .zero
    @Published public var isInSecondBrain = false
    @Published public var brainCount: Int = 0
    @Published public var showControls = true
    @Published public var isPlaying = false
    
    // MARK: - Extended Playback & Loop
    /// Tracks cumulative watch time across loops. If a video is 30 seconds long and user loops once, watchTime can reach 60, etc.
    @Published public var watchTime: Double = 0.0
    
    /// The duration of the video as soon as the asset is loaded.
    /// Helps us track how many times the user has effectively gone beyond 100%.
    public var videoDuration: Double = 0.0
    
    private var observers: [NSKeyValueObservation] = []
    private var timeObserverToken: Any?
    private var deinitHandler: (() -> Void)?
    private let firestore = Firestore.firestore()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    
    // Used to ensure we don't double fade
    private var fadeTask: Task<Void, Never>?
    private var fadeInTask: Task<Void, Never>?
    
    // Additional concurrency
    private var isCleaningUp = false
    
    public init(video: Video) {
        self.video = video
        self.brainCount = video.brainCount
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
        
        // Check if video is in user's second brain
        Task {
            do {
                try await checkSecondBrainStatus()
            } catch {
                LoggingService.error("Failed to check second brain status: \(error)", component: "Player")
            }
        }
        
        // Capture the cleanup values in a closure that can be called from deinit
        let observersCopy = observers
        let playerCopy = player
        let timeObserverTokenCopy = timeObserverToken
        deinitHandler = { [observersCopy, playerCopy, timeObserverTokenCopy] in
            observersCopy.forEach { $0.invalidate() }
            if let token = timeObserverTokenCopy, let player = playerCopy {
                player.removeTimeObserver(token)
            }
            playerCopy?.pause()
            playerCopy?.replaceCurrentItem(with: nil)
        }
    }
    
    private func checkSecondBrainStatus() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { 
            await MainActor.run {
                self.isInSecondBrain = false
            }
            return 
        }
        
        let snapshot = try await firestore.collection("users")
            .document(userId)
            .collection("secondBrain")
            .whereField("videoId", isEqualTo: video.id)
            .limit(to: 1)
            .getDocuments()
        
        await MainActor.run {
            let exists = !snapshot.documents.isEmpty
            self.isInSecondBrain = exists
            LoggingService.debug("Second brain status checked for video \(self.video.id) - isInSecondBrain: \(exists)", component: "Player")
        }
    }
    
    private func cleanup() {
        if isCleaningUp {
            return
        }
        isCleaningUp = true
        
        // Invalidate observers - this is thread-safe
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        // Remove time observer
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        // Clean up player
        if let player = player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player = nil
        isPlaying = false
        
        isCleaningUp = false
        LoggingService.debug("Cleaned up player resources", component: "Player")
    }
    
    deinit {
        deinitHandler?() // Safe to call from deinit
    }
    
    public func loadVideo() {
        LoggingService.video("Starting loadVideo for \(video.id)", component: "Player")
        isLoading = true
        
        // Check if we have a preloaded player first
        if let preloadedPlayer = preloadedPlayers[video.id] {
            LoggingService.video("✅ Using preloaded player for \(video.id)", component: "Player")
            setupPlayer(preloadedPlayer)
            preloadedPlayers.removeValue(forKey: video.id)
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for \(video.id)", component: "Player")
            isLoading = false
            return
        }
        
        // Create asset with optimized loading options
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])
        
        Task {
            await setupNewPlayer(with: asset)
        }
    }
    
    private func setupNewPlayer(with asset: AVAsset) async {
        LoggingService.video("Setting up new player for \(video.id)", component: "Player")
        
        do {
            // Load essential properties
            let playable = try await asset.load(.isPlayable)
            
            guard playable else {
                LoggingService.error("Asset not playable for \(video.id)", component: "Player")
                await MainActor.run { isLoading = false }
                return
            }
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 10
            let player = AVPlayer(playerItem: playerItem)
            
            await MainActor.run {
                setupPlayer(player)
            }
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func setupPlayer(_ player: AVPlayer) {
        LoggingService.video("Setting up player for \(video.id)", component: "Player")
        
        // Clean up existing player first
        cleanup()
        
        self.player = player
        observePlayerStatus(player)
        
        // Configure playback settings
        player.automaticallyWaitsToMinimizeStalling = false
        player.currentItem?.preferredForwardBufferDuration = 10
        
        // Add time observer for watchTime
        addTimeObserver(to: player)
        
        // Add end of video observer for looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        LoggingService.video("✅ Player setup complete for \(video.id)", component: "Player")
        isLoading = false
    }
    
    private func observePlayerStatus(_ player: AVPlayer) {
        let statusObserver = player.observe(\.status) { [weak self] player, _ in
            guard let self = self else { return }
            Task { @MainActor in
                switch player.status {
                case .failed:
                    self.error = player.error?.localizedDescription
                    LoggingService.error("Player failed for \(self.video.id): \(player.error?.localizedDescription ?? "Unknown error")", component: "Player")
                case .readyToPlay:
                    LoggingService.video("Player ready for \(self.video.id)", component: "Player")
                    // Start buffering only when player is ready
                    do {
                        try await player.preroll(atRate: 1.0)
                        LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                    } catch {
                        LoggingService.error("Preroll failed for \(self.video.id): \(error.localizedDescription)", component: "Player")
                    }
                default:
                    break
                }
            }
        }
        observers.append(statusObserver)
    }
    
    private func addTimeObserver(to player: AVPlayer) {
        // Remove existing observer if any
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        // Create new observer that fires every 0.5 seconds
        let interval = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] currentTime in
            guard let self = self, !self.isCleaningUp else { return }
            
            // If playing, accumulate watchTime
            if self.isPlaying {
                self.watchTime += 0.5 // Add half a second since that's our interval
                LoggingService.debug("[PlayerVM] watchTime = \(self.watchTime) (video: \(self.video.id))", component: "Player")
            }
        }
        timeObserverToken = token
    }
    
    @objc private func playerItemDidReachEnd() {
        LoggingService.debug("🔄 Video reached end, initiating loop (video: \(video.id))", component: "Player")
        guard let player = player else { return }
        
        // Seek to start
        player.seek(to: .zero)
        player.play()
        isPlaying = true
        
        // Re-apply fade in if not muted
        Task { @MainActor in
            await fadeInAudio()
        }
    }
    
    public func addToSecondBrain() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("Cannot add to SecondBrain: No authenticated user", component: "SecondBrain")
            return
        }
        
        // Optimistic update
        let wasInSecondBrain = isInSecondBrain
        isInSecondBrain.toggle()
        brainCount += isInSecondBrain ? 1 : -1
        
        showBrainAnimation = true
        
        do {
            if !isInSecondBrain {
                // Remove from SecondBrain
                let snapshot = try await firestore.collection("users")
                    .document(userId)
                    .collection("secondBrain")
                    .whereField("videoId", isEqualTo: video.id)
                    .limit(to: 1)
                    .getDocuments()
                
                if let doc = snapshot.documents.first {
                    try await doc.reference.delete()
                }
                
                // Update video brain count
                try await firestore.collection("videos").document(video.id).updateData([
                    "brainCount": FieldValue.increment(Int64(-1))
                ])
                
                LoggingService.success("Removed from SecondBrain", component: "SecondBrain")
            } else {
                // Create a new SecondBrain entry
                let brainId = UUID().uuidString
                let secondBrain = SecondBrain(
                    id: brainId,
                    userId: userId,
                    videoId: video.id,
                    transcript: video.transcript ?? "",
                    quotes: video.quotes ?? [],
                    videoTitle: video.title,
                    videoThumbnailURL: video.thumbnailURL
                )
                
                try await firestore.collection("users")
                    .document(userId)
                    .collection("secondBrain")
                    .document(brainId)
                    .setData(secondBrain.toFirestoreData())
                
                // Update video brain count
                try await firestore.collection("videos").document(video.id).updateData([
                    "brainCount": FieldValue.increment(Int64(1))
                ])
                
                LoggingService.success("Added to SecondBrain: \(brainId)", component: "SecondBrain")
            }
        } catch {
            // Revert optimistic update on error
            isInSecondBrain.toggle()
            brainCount -= isInSecondBrain ? 1 : -1
            LoggingService.error("Failed to update SecondBrain: \(error.localizedDescription)", component: "SecondBrain")
        }
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            showBrainAnimation = false
        } catch {
            LoggingService.error("Error during animation delay: \(error)", component: "SecondBrain")
        }
    }
    
    // MARK: - New Method: Pause Playback
    /// Immediately pauses the AVPlayer and updates the isPlaying flag.
    /// This method is used to ensure that offscreen players do not play audio.
    public func pausePlayback() async {
        LoggingService.debug("pausePlayback() called for video \(video.id)", component: "PlayerVM")
        if let player = player {
            // Fade out audio
            let fadeTime = 0.3
            let steps = 5
            let volumeDecrement = player.volume / Float(steps)
            for step in 0...steps {
                try? await Task.sleep(nanoseconds: UInt64(fadeTime * 1_000_000_000 / Double(steps)))
                player.volume = player.volume - volumeDecrement
                LoggingService.debug("Fading out audio: step \(step) of \(steps), volume=\(player.volume)", component: "PlayerVM")
            }
            player.pause()
        }
        isPlaying = false
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        LoggingService.debug("Player paused and isPlaying set to false for video \(video.id)", component: "PlayerVM")
    }
    
    // MARK: - Enhanced Play Method
    public func play() async {
        LoggingService.debug("play() called for video \(video.id)", component: "PlayerVM")
        
        // If another video is currently playing, pause it first
        if let currentlyPlaying = VideoPlayerViewModel.currentlyPlayingViewModel, currentlyPlaying !== self {
            LoggingService.debug("Pausing currently playing video \(currentlyPlaying.video.id)", component: "PlayerVM")
            await currentlyPlaying.pausePlayback()
        }
        
        if player == nil {
            LoggingService.debug("Player was nil, loading video first", component: "PlayerVM")
            loadVideo()
        }
        
        guard let player = player else {
            LoggingService.error("Player still nil after loadVideo for \(video.id)", component: "PlayerVM")
            return
        }
        
        // Start with volume at 0 and fade in
        player.volume = 0
        player.play()
        isPlaying = true
        VideoPlayerViewModel.currentlyPlayingViewModel = self
        
        // Fade in audio
        let fadeTime = 0.3
        let steps = 5
        let targetVolume: Float = 1.0
        let volumeIncrement = targetVolume / Float(steps)
        
        for i in 0...steps {
            try? await Task.sleep(nanoseconds: UInt64(fadeTime * 1_000_000_000 / Double(steps)))
            player.volume = Float(i) * volumeIncrement
            LoggingService.debug("Fading in audio: step \(i) of \(steps), volume=\(player.volume)", component: "PlayerVM")
        }
        
        LoggingService.debug("✅ Play complete for video \(video.id)", component: "PlayerVM")
    }
    
    public func pause() async {
        LoggingService.video("⏸️ PAUSE requested for video \(video.id)", component: "Player")
        LoggingService.video("Current player status: \(player?.status.rawValue ?? -1)", component: "Player")
        LoggingService.video("Current time: \(player?.currentTime().seconds ?? 0)", component: "Player")
        LoggingService.video("Is playing: \(player?.rate != 0)", component: "Player")
        
        player?.pause()
        LoggingService.video("✅ PAUSE command issued for video \(video.id)", component: "Player")
    }
    
    public func toggleControls() {
        LoggingService.video("Toggling controls for \(video.id)", component: "Player")
        showControls.toggle()
    }
    
    public func preloadVideo(_ video: Video) {
        LoggingService.video("Preloading video \(video.id)", component: "Player")
        
        // Don't preload if we already have this video preloaded
        if preloadedPlayers[video.id] != nil {
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for preloading \(video.id)", component: "Player")
            return
        }
        
        // Create asset with optimized loading options
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])
        
        Task {
            do {
                let playable = try await asset.load(.isPlayable)
                
                guard playable else {
                    LoggingService.error("Preloaded asset not playable for \(video.id)", component: "Player")
                    return
                }
                
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 10
                let player = AVPlayer(playerItem: playerItem)
                
                // Configure playback settings
                player.automaticallyWaitsToMinimizeStalling = false
                
                // Wait for player to be ready before prerolling
                try await withCheckedThrowingContinuation { continuation in
                    let observer = player.observe(\.status) { player, _ in
                        if player.status == .readyToPlay {
                            continuation.resume()
                        } else if player.status == .failed {
                            continuation.resume(throwing: player.error ?? NSError(domain: "AVPlayer", code: -1))
                        }
                    }
                    self.observers.append(observer)
                }
                
                // Now that player is ready, attempt preroll
                try await player.preroll(atRate: 1.0)
                
                // Store in preloaded players
                preloadedPlayers[video.id] = player
                LoggingService.video("✅ Successfully preloaded video \(video.id)", component: "Player")
            } catch {
                LoggingService.error("Failed to preload video \(video.id): \(error.localizedDescription)", component: "Player")
            }
        }
    }
    
    // MARK: - Audio Fade
    private func cancelFades() {
        fadeTask?.cancel()
        fadeInTask?.cancel()
    }
    
    private func fadeOutAudio() async {
        guard let player = player else { return }
        cancelFades()
        let steps = 5
        let time = 0.3
        let chunk = player.volume / Float(steps)
        fadeTask = Task {
            for _ in 0..<steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(time*1_000_000_000 / Double(steps)))
                player.volume -= chunk
            }
        }
        await fadeTask?.value
    }
    
    private func fadeInAudio() async {
        guard let player = player else { return }
        cancelFades()
        let steps = 5
        let time = 0.3
        player.volume = 0
        fadeInTask = Task {
            for i in 0...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(time*1_000_000_000 / Double(steps)))
                player.volume = Float(i) * (1.0 / Float(steps))
                LoggingService.debug("Fading in audio: step \(i) of \(steps), volume=\(player.volume)", component: "PlayerVM")
            }
        }
        await fadeInTask?.value
    }
} 