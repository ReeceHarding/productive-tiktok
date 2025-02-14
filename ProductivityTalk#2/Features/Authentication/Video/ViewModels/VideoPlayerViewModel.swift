import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI
import OSLog
import UserNotifications

// MARK: - Sendable Types
private enum SendableValue: Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    
    var value: Any {
        switch self {
            case .int(let value): return value
            case .double(let value): return value
            case .string(let value): return value
            case .bool(let value): return value
        }
    }
}

private extension Dictionary where Key == String, Value == SendableValue {
    var asDictionary: [String: Any] {
        mapValues { $0.value }
    }
}

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
    @Published public var isBuffering = false
    @Published public var loadingProgress: Double = 0
    @Published public var isSubscribedToNotifications = false
    @Published public var toastMessage: String?
    
    private var observers: Set<NSKeyValueObservation> = []
    private var timeObserverToken: Any?
    private var deinitHandler: (() async -> Void)?
    private let firestore = Firestore.firestore()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var bufferingObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private var notificationRequestIds: Set<String> = []
    
    // Used to ensure we don't double fade
    private var fadeTask: Task<Void, Never>?
    private var fadeInTask: Task<Void, Error>?
    
    // Additional concurrency
    private var isCleaningUp = false
    private var retryCount = 0
    private let maxRetries = 3
    
    private var subscriptionRequestId: String?
    private var notificationManager = NotificationManager.shared
    
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
    
    public func retryLoading() async {
        guard retryCount < maxRetries else {
            LoggingService.error("Max retries reached for video \(video.id)", component: "Player")
            error = "Unable to load video after multiple attempts"
            return
        }
        
        retryCount += 1
        LoggingService.debug("Retrying video load attempt \(retryCount) for \(video.id)", component: "Player")
        error = nil
        await loadVideo()
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
    
    @MainActor
    func cleanup() async {
        LoggingService.debug("🧹 Starting cleanup for video \(video.id)", component: "PlayerVM")
        if isCleaningUp {
            LoggingService.debug("Already cleaning up video \(video.id), skipping", component: "PlayerVM")
            return
        }
        isCleaningUp = true
        
        // First ensure playback is stopped
        if let player = player {
            LoggingService.debug("Stopping playback during cleanup for \(video.id)", component: "PlayerVM")
            player.pause()
            player.volume = 0 // Immediately silence
        }
        
        // Invalidate observers - this is thread-safe
        LoggingService.debug("Invalidating observers for video \(video.id)", component: "PlayerVM")
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        bufferingObserver?.invalidate()
        bufferingObserver = nil
        
        loadingObserver?.invalidate()
        loadingObserver = nil
        
        // Remove time observer
        if let token = timeObserverToken, let player = player {
            LoggingService.debug("Removing time observer for video \(video.id)", component: "PlayerVM")
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        // Clean up player
        if let player = player {
            LoggingService.debug("Final player cleanup for video \(video.id)", component: "PlayerVM")
            player.replaceCurrentItem(with: nil)
        }
        player = nil
        isPlaying = false
        
        // Clear static reference if this was the current player
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            LoggingService.debug("Clearing static reference to current player for \(video.id)", component: "PlayerVM")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        
        isCleaningUp = false
        LoggingService.debug("✅ Cleanup complete for video \(video.id)", component: "PlayerVM")
        
        // Small delay to ensure audio system is fully reset
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    deinit {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let videoId = self.video.id
            if let handler = self.deinitHandler {
                await handler()
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // Small delay to ensure cleanup completes
            do {
                await self.cleanup()
                LoggingService.debug("VideoPlayerViewModel deinit for video \(videoId)", component: "Player")
            } catch {
                LoggingService.error("Error during cleanup in deinit for video \(videoId): \(error)", component: "Player")
            }
        }
        // Remove any pending notifications when the view model is deallocated
        Task {
            await self.removeNotification()
        }
    }
    
    public func loadVideo() async {
        LoggingService.video("Starting loadVideo for \(video.id)", component: "Player")
        isLoading = true
        loadingProgress = 0
        error = nil
        
        // Check if we have a preloaded player first
        if let preloadedPlayer = preloadedPlayers[video.id] {
            LoggingService.video("✅ Using preloaded player for \(video.id)", component: "Player")
            do {
                try await setupPlayer(preloadedPlayer)
                preloadedPlayers.removeValue(forKey: video.id)
            } catch {
                LoggingService.error("Failed to setup preloaded player: \(error.localizedDescription)", component: "Player")
                self.error = "Failed to setup preloaded player: \(error.localizedDescription)"
                isLoading = false
            }
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for \(video.id)", component: "Player")
            error = "Invalid video URL"
            isLoading = false
            return
        }
        
        // Create asset with optimized loading options
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])
        
        do {
            try await setupNewPlayer(with: asset)
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            self.error = "Failed to load video: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func setupNewPlayer(with asset: AVAsset) async throws {
        LoggingService.video("Setting up new player for \(video.id)", component: "Player")
        
        do {
            // Load essential properties
            let playable = try await asset.load(.isPlayable)
            
            guard playable else {
                LoggingService.error("Asset not playable for \(video.id)", component: "Player")
                await MainActor.run { 
                    error = "Video format not supported"
                    isLoading = false 
                }
                return
            }
            
            // Load duration to update progress
            let duration = try await asset.load(.duration)
            let durationInSeconds = CMTimeGetSeconds(duration)
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 10
            
            // Observe loading progress
            loadingObserver = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
                guard let self = self else { return }
                let loadedRanges = item.loadedTimeRanges
                if let timeRange = loadedRanges.first?.timeRangeValue {
                    let loadedDuration = CMTimeGetSeconds(timeRange.duration)
                    let progress = loadedDuration / durationInSeconds
                    Task { @MainActor in
                        self.loadingProgress = max(0, min(1, progress))
                    }
                }
            }
            
            let player = AVPlayer(playerItem: playerItem)
            
            await Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.setupPlayer(player)
                } catch {
                    LoggingService.error("Failed to setup player: \(error)", component: "Player")
                }
            }.value
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    @MainActor
    private func setupPlayer(_ newPlayer: AVPlayer) async throws {
        LoggingService.video("🎥 Setting up player for \(video.id)", component: "Player")
        
        // Ensure we're not in cleanup
        guard !isCleaningUp else {
            throw NSError(domain: "com.producttalk.player", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player is being cleaned up"])
        }
        
        // Setup status observation and preroll
        return try await withCheckedThrowingContinuation { continuation in
            let observer = newPlayer.currentItem?.observe(\.status) { [weak self] item, _ in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            // Preroll the player
                            let success = try await newPlayer.preroll(atRate: 1.0)
                            if success {
                                LoggingService.video("✅ Successfully prerolled video \(self.video.id)", component: "Player")
                                self.player = newPlayer
                                self.isLoading = false
                                self.setupTimeObserver()
                                self.setupBufferingObserver()
                                continuation.resume()
                            } else {
                                let error = NSError(domain: "com.producttalk.player", code: -1, userInfo: [NSLocalizedDescriptionKey: "Preroll failed"])
                                continuation.resume(throwing: error)
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failed:
                    let error = item.error ?? NSError(domain: "com.producttalk.player", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown player error"])
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            
            if let observer = observer {
                observers.insert(observer)
            }
        }
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
                    if let success = try? await player.preroll(atRate: 1.0) {
                        if success {
                            LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                        } else {
                            LoggingService.error("Preroll failed for \(self.video.id)", component: "Player")
                        }
                    }
                default:
                    break
                }
            }
        }
        observers.insert(statusObserver)
    }
    
    @MainActor
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // Remove any existing time observer
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        // Add new time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            // Update any time-based UI here if needed
        }
    }
    
    @MainActor
    private func setupBufferingObserver() {
        guard let player = player else { return }
        
        // Remove any existing buffering observer
        bufferingObserver?.invalidate()
        
        // Setup new buffering observer
        bufferingObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                
                // If we're no longer buffering and should be playing, ensure playback continues
                if !self.isBuffering && self.isPlaying {
                    player.play()
                }
            }
        }
        
        // Configure playback settings
        player.automaticallyWaitsToMinimizeStalling = false
        if let currentItem = player.currentItem {
            currentItem.preferredForwardBufferDuration = 10
        }
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
            try? await fadeInAudio()
        }
    }
    
    public func addToSecondBrain() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("No user ID found when trying to add to second brain", component: "Player")
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        LoggingService.debug("🧠 Starting addToSecondBrain for video \(video.id)", component: "Player")
        LoggingService.debug("Current state - isInSecondBrain: \(isInSecondBrain), brainCount: \(brainCount)", component: "Player")
        
        let wasInSecondBrain = isInSecondBrain
        
        do {
            // Get reference to the user's second brain collection
            let secondBrainRef = firestore.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(video.id)
            
            // Get reference to the video document
            let videoRef = firestore.collection("videos").document(video.id)
            
            LoggingService.debug("🔄 Starting Firestore transaction", component: "Player")
            
            let transactionResult = try await firestore.runTransaction { (transaction, errorPointer) -> Any? in
                let secondBrainDoc: DocumentSnapshot
                let videoDoc: DocumentSnapshot
                
                do {
                    LoggingService.debug("📄 Fetching documents in transaction", component: "Player")
                    secondBrainDoc = try transaction.getDocument(secondBrainRef)
                    videoDoc = try transaction.getDocument(videoRef)
                    LoggingService.debug("✅ Successfully fetched documents", component: "Player")
                    LoggingService.debug("Second brain doc exists: \(secondBrainDoc.exists)", component: "Player")
                } catch let fetchError as NSError {
                    LoggingService.error("❌ Error fetching documents: \(fetchError.localizedDescription)", component: "Player")
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                // Update watch time
                transaction.updateData([
                    "watchTime": FieldValue.serverTimestamp()
                ], forDocument: videoRef)
                
                if secondBrainDoc.exists {
                    LoggingService.debug("🗑️ Removing from second brain", component: "Player")
                    // Remove from second brain
                    transaction.deleteDocument(secondBrainRef)
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(-1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    LoggingService.success("✅ Removed video \(self.video.id) from second brain", component: "Player")
                    return false as Any  // Return false for removal
                } else {
                    LoggingService.debug("➕ Adding to second brain", component: "Player")
                    // Extract fields from video document
                    let videoData = videoDoc.data() ?? [:]
                    let quotes = videoData["quotes"] as? [String] ?? []
                    let transcript = videoData["transcript"] as? String ?? ""
                    let category = (videoData["tags"] as? [String])?.first ?? "Uncategorized"
                    let title = videoData["title"] as? String ?? "No title"
                    let thumbURL = videoData["thumbnailURL"] as? String ?? ""
                    
                    // Add to second brain with all required fields
                    let secondBrainData: [String: Any] = [
                        "videoId": self.video.id,
                        "userId": userId,
                        "quotes": quotes,
                        "transcript": transcript,
                        "category": category,
                        "videoTitle": title,
                        "videoThumbnailURL": thumbURL,
                        "savedAt": FieldValue.serverTimestamp()
                    ]
                    
                    LoggingService.debug("📝 Adding video to second brain with data: \(secondBrainData)", component: "Player")
                    transaction.setData(secondBrainData, forDocument: secondBrainRef)
                    
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    LoggingService.success("✅ Added video \(self.video.id) to second brain with \(quotes.count) quotes", component: "Player")
                    return true as Any  // Return true for addition
                }
            }
            
            // Update UI state after transaction completes
            await MainActor.run {
                if let wasAdded = transactionResult as? Bool {
                    if wasAdded {
                        self.isInSecondBrain = true
                        self.brainCount += 1
                        self.showBrainAnimation = true
                        LoggingService.debug("🔄 UI updated after adding to second brain - new brainCount: \(self.brainCount)", component: "Player")
                        
                        // Show toast message
                        self.toastMessage = "Added to Second Brain"
                        
                        // Reset animation and toast state after delay
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                            self.showBrainAnimation = false
                            self.toastMessage = nil
                        }
                    } else {
                        self.isInSecondBrain = false
                        self.brainCount -= 1
                        self.showBrainAnimation = false
                        LoggingService.debug("🔄 UI updated after removing from second brain - new brainCount: \(self.brainCount)", component: "Player")
                        
                        // Show toast message
                        self.toastMessage = "Removed from Second Brain"
                        
                        // Reset toast state after delay
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                            self.toastMessage = nil
                        }
                    }
                } else {
                    LoggingService.error("❌ Transaction result was nil", component: "Player")
                }
            }
        } catch {
            await MainActor.run {
                self.isInSecondBrain = wasInSecondBrain
            }
            LoggingService.error("❌ Failed to toggle second brain for video \(video.id): \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    // MARK: - Enhanced Play Method
    @MainActor
    public func play() async {
        LoggingService.video("🎬 Starting play() for video \(video.id)", component: "PlayerVM")
        
        // If we don't have a player yet, load the video first
        if player == nil {
            LoggingService.debug("No player exists, loading video first", component: "PlayerVM")
            await loadVideo()
        }
        
        guard let player = player else {
            LoggingService.error("No player available for video \(video.id)", component: "PlayerVM")
            return
        }
        
        // Set initial volume
        LoggingService.debug("Setting initial volume to 1.0 for video \(video.id)", component: "PlayerVM")
        player.volume = 1.0
        
        // Start playback
        LoggingService.debug("🔊 Starting playback for video \(video.id)", component: "PlayerVM")
        
        // Cancel any existing fade tasks
        LoggingService.debug("Cancelling any existing fade tasks for video \(video.id)", component: "PlayerVM")
        fadeTask?.cancel()
        fadeTask = nil
        
        // Start audio fade in
        LoggingService.debug("Starting audio fade in for video \(video.id)", component: "PlayerVM")
        player.play()
        isPlaying = true
        
        // Store as currently playing video
        if VideoPlayerViewModel.currentlyPlayingViewModel !== self {
            await VideoPlayerViewModel.currentlyPlayingViewModel?.pausePlayback()
            VideoPlayerViewModel.currentlyPlayingViewModel = self
        }
        
        // Update video data
        Task {
            do {
                let data: [String: Any] = [
                    "lastWatched": FieldValue.serverTimestamp(),
                    "watchCount": FieldValue.increment(Int64(1))
                ]
                try await updateVideoData(videoId: video.id, data: data)
                LoggingService.debug("✅ Successfully updated video data for \(video.id)", component: "PlayerVM")
            } catch {
                LoggingService.error("Failed to update video data: \(error.localizedDescription)", component: "PlayerVM")
            }
        }
    }
    
    // MARK: - New Method: Pause Playback
    /// Immediately pauses the AVPlayer and updates the isPlaying flag.
    /// This method is used to ensure that offscreen players do not play audio.
    public func pausePlayback() async {
        LoggingService.debug("⏸️ pausePlayback() called for video \(video.id)", component: "PlayerVM")
        LoggingService.debug("Current volume: \(player?.volume ?? -1)", component: "PlayerVM")
        
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
            LoggingService.debug("Pausing player for video \(video.id)", component: "PlayerVM")
            player.pause()
        }
        isPlaying = false
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            LoggingService.debug("Clearing currently playing video reference", component: "PlayerVM")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        LoggingService.debug("✅ Player paused and isPlaying set to false for video \(video.id)", component: "PlayerVM")
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
    
    public func preloadVideo(_ video: Video) async {
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
                self.observers.insert(observer)
            }
            
            // Now that player is ready, attempt preroll
            do {
                let success = try await player.preroll(atRate: 1.0)
                if success {
                    LoggingService.video("✅ Successfully prerolled video \(video.id)", component: "Player")
                    preloadedPlayers[video.id] = player
                    LoggingService.video("✅ Stored preloaded player for video \(video.id)", component: "Player")
                } else {
                    LoggingService.error("Failed to preroll video \(video.id)", component: "Player")
                }
            } catch {
                LoggingService.error("Preroll error for \(video.id): \(error)", component: "Player")
            }
        } catch {
            LoggingService.error("Failed to preload video \(video.id): \(error.localizedDescription)", component: "Player")
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
    
    private func fadeInAudio() async throws {
        guard let player = player else { return }
        
        // Start with volume at 0
        player.volume = 0
        
        // Cancel any existing fade tasks
        cancelFades()
        
        // Create new fade in task
        fadeInTask = Task<Void, Error> {
            // Implement manual volume fade
            let steps = 10
            let duration = 0.5
            let stepDuration = duration / Double(steps)
            
            for i in 0...steps {
                if Task.isCancelled { return }
                player.volume = Float(i) / Float(steps)
                try await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
            
            // Ensure we end at full volume
            if !Task.isCancelled {
                player.volume = 1.0
            }
            
            LoggingService.debug("Audio fade complete for video \(video.id)", component: "Player")
        }
        
        // Wait for fade to complete
        try await fadeInTask?.value
    }
    
    @MainActor
    private func updateVideoStats(data: [String: Any]) async throws {
        let videoId = video.id
        try await updateVideoData(videoId: videoId, data: data)
    }
    
    nonisolated private func updateVideoData(videoId: String, data: [String: Any]) async throws {
        await MainActor.run {
            LoggingService.video("Updating video data for \(videoId)", component: "Player")
        }
        let firestore = Firestore.firestore()
        
        // Convert to Sendable dictionary type
        let sendableData = data.mapValues { value -> Any in
            if let value = value as? Date {
                return Timestamp(date: value)
            }
            return value
        }
        
        try await firestore.collection("videos").document(videoId).updateData(sendableData)
        await MainActor.run {
            LoggingService.video("Updated video data for \(videoId)", component: "Player")
        }
    }
    
    private func updateSecondBrainStatus() async throws {
        let data: [String: SendableValue] = [
            "isInSecondBrain": .bool(isInSecondBrain)
        ]
        try await firestore.collection("videos").document(video.id).updateData(data.asDictionary)
    }
    
    private func prerollIfNeeded() async throws {
        guard let player = player else { return }
        let success = try await player.preroll(atRate: 1.0)
        if success {
            LoggingService.video("Preroll complete for \(video.id)", component: "Player")
        } else {
            LoggingService.error("Preroll failed for \(video.id)", component: "Player")
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Preroll failed"])
        }
    }
    
    func toggleSecondBrain() async {
        let previousState = isInSecondBrain
        isInSecondBrain.toggle()
        do {
            try await updateSecondBrainStatus()
        } catch {
            isInSecondBrain = previousState // Revert on failure
            LoggingService.error("[PlayerVM] Failed to update second brain status: \(error.localizedDescription)", component: "Player")
        }
    }
    
    @MainActor
    private func handlePlaybackError(_ error: Error) {
        LoggingService.error("Playback error for video \(video.id): \(error.localizedDescription)", component: "Player")
        self.error = error.localizedDescription
    }
    
    private func incrementViewCount() async throws {
        let data: [String: Any] = [
            "viewCount": video.viewCount + 1
        ]
        try await updateVideoStats(data: data)
    }
    
    // MARK: - Notification Methods
    public func updateNotificationState(requestId: String?) {
        LoggingService.debug("Updating notification state for video \(video.id)", component: "Player")
        if let requestId = requestId {
            notificationRequestIds.insert(requestId)
            isSubscribedToNotifications = true
            LoggingService.debug("Added notification request ID: \(requestId)", component: "Player")
        }
    }
    
    public func removeNotification() async {
        LoggingService.debug("Removing notifications for video \(video.id)", component: "Player")
        // Remove all notification requests for this video
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(notificationRequestIds))
        notificationRequestIds.removeAll()
        isSubscribedToNotifications = false
        LoggingService.debug("Removed all notification requests", component: "Player")
    }
} 