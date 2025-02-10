import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI

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
    
    private var observers: [NSKeyValueObservation] = []
    private var timeObserverToken: Any?
    private var deinitHandler: (() -> Void)?
    private let firestore = Firestore.firestore()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var bufferingObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    
    // Used to ensure we don't double fade
    private var fadeTask: Task<Void, Never>?
    private var fadeInTask: Task<Void, Never>?
    
    // Additional concurrency
    private var isCleaningUp = false
    private var retryCount = 0
    private let maxRetries = 3
    
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
    private func cleanup() {
        if isCleaningUp {
            return
        }
        isCleaningUp = true
        
        // Invalidate observers - this is thread-safe
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        bufferingObserver?.invalidate()
        bufferingObserver = nil
        
        loadingObserver?.invalidate()
        loadingObserver = nil
        
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
        // Since we're in deinit, we need to be careful about actor isolation
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let videoId = self.video.id
            await self.deinitHandler?()
            self.cleanup() // Call cleanup on MainActor
            LoggingService.debug("VideoPlayerViewModel deinit for video \(videoId)", component: "Player")
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
            setupPlayer(preloadedPlayer)
            preloadedPlayers.removeValue(forKey: video.id)
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
            
            await MainActor.run {
                setupPlayer(player)
            }
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            throw error
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
        
        // Observe buffering state
        bufferingObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in
                self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        
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
                        if try await player.preroll(atRate: 1.0) {
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
            guard let self = self else { return }
            Task { @MainActor in
                await self.updateWatchTime()
            }
        }
        timeObserverToken = token
    }
    
    private func updateWatchTime() async {
        guard !isCleaningUp else { return }
        // Removed watchTime logging as it was too verbose
        // We still keep the method for future use if needed
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
        
        let wasInSecondBrain = isInSecondBrain
        
        do {
            // Get reference to the user's second brain collection
            let secondBrainRef = firestore.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(video.id)
            
            // Get reference to the video document
            let videoRef = firestore.collection("videos").document(video.id)
            
            let _ = try await firestore.runTransaction { [weak self] (transaction, errorPointer) -> Any? in
                guard let self = self else { return nil }
                
                let secondBrainDoc: DocumentSnapshot
                
                do {
                    secondBrainDoc = try transaction.getDocument(secondBrainRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                // Update watch time
                transaction.updateData([
                    "watchTime": FieldValue.serverTimestamp()
                ], forDocument: videoRef)
                
                if secondBrainDoc.exists {
                    // Remove from second brain
                    transaction.deleteDocument(secondBrainRef)
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(-1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    Task { @MainActor in
                        self.isInSecondBrain = false
                        self.brainCount -= 1
                        self.showBrainAnimation = false
                    }
                    LoggingService.success("Removed video \(self.video.id) from second brain", component: "Player")
                } else {
                    // Add to second brain
                    transaction.setData([
                        "videoId": self.video.id,
                        "addedAt": FieldValue.serverTimestamp()
                    ], forDocument: secondBrainRef)
                    
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    Task { @MainActor in
                        self.isInSecondBrain = true
                        self.brainCount += 1
                        self.showBrainAnimation = true
                    }
                    LoggingService.success("Added video \(self.video.id) to second brain", component: "Player")
                }
                
                return nil
            }
        } catch {
            await MainActor.run {
                self.isInSecondBrain = wasInSecondBrain
            }
            LoggingService.error("Failed to toggle second brain for video \(video.id): \(error.localizedDescription)", component: "Player")
            throw error
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
            await loadVideo()
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
        
        // Increment view count
        do {
            try await firestore.collection("videos").document(video.id).updateData([
                "viewCount": FieldValue.increment(Int64(1))
            ])
            LoggingService.success("Incremented view count for video \(video.id)", component: "PlayerVM")
        } catch {
            LoggingService.error("Failed to increment view count: \(error)", component: "PlayerVM")
        }
        
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
                if try await player.preroll(atRate: 1.0) {
                    // Store in preloaded players
                    preloadedPlayers[video.id] = player
                    LoggingService.video("✅ Successfully preloaded video \(video.id)", component: "Player")
                } else {
                    LoggingService.error("Failed to preroll video \(video.id)", component: "Player")
                }
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
        
        // Implement manual volume fade
        let steps = 10
        let duration = 0.5
        let stepDuration = duration / Double(steps)
        
        player.volume = 0
        for i in 0...steps {
            if Task.isCancelled { return }
            player.volume = Float(i) / Float(steps)
            do {
                try await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            } catch {
                print("Error during volume fade sleep: \(error)")
            }
        }
    }
    
    @MainActor
    private func updateVideoStats(data: [String: Any]) async throws {
        let videoId = video.id // Capture video.id on main actor
        let dataCopy = data // Create an immutable copy
        try await firestore.collection("videos").document(videoId).updateData(dataCopy)
    }
    
    private func updateSecondBrainStatus() async throws {
        let data: [String: SendableValue] = [
            "isInSecondBrain": .bool(isInSecondBrain)
        ]
        try await firestore.collection("videos").document(video.id).updateData(data.asDictionary)
    }
    
    private func prerollIfNeeded() async {
        guard let player = player else { return }
        try? await player.preroll(atRate: 1.0)
        
        await MainActor.run {
            LoggingService.video("Preroll complete for \(video.id)", component: "Player")
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
    
    nonisolated private func updateVideoData(_ data: [String: Any]) async throws {
        let videoId = await video.id
        await MainActor.run {
            LoggingService.video("Updating video data for \(videoId)", component: "Player")
        }
        let firestore = Firestore.firestore()
        
        // Convert to Sendable dictionary type
        let sendableData = Dictionary(uniqueKeysWithValues: data.map { key, value in
            if let fieldValue = value as? FieldValue {
                return (key, fieldValue as Any)
            } else if let intValue = value as? Int {
                return (key, intValue as Any)
            } else if let doubleValue = value as? Double {
                return (key, doubleValue as Any)
            } else if let stringValue = value as? String {
                return (key, stringValue as Any)
            } else if let boolValue = value as? Bool {
                return (key, boolValue as Any)
            } else if let timestampValue = value as? Date {
                return (key, timestampValue as Any)
            } else {
                return (key, value)
            }
        })
        
        try await firestore.collection("videos").document(videoId).updateData(sendableData)
    }
    
    private func handlePlaybackError(_ error: Error) {
        LoggingService.error("Playback error for video \(video.id): \(error.localizedDescription)", component: "Player")
        self.error = error.localizedDescription
    }
} 