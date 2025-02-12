import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore
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
    @Published public var loadingState: LoadingState = .initial
    
    public enum LoadingState {
        case initial
        case loading
        case buffering
        case ready
        case error(String)
    }
    
    private var observers: Set<NSKeyValueObservation> = []
    private var timeObserverToken: Any?
    private var deinitHandler: (() async -> Void)?
    private let firestore = Firestore.firestore()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var bufferingObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private var notificationRequestIds: Set<String> = []
    
    // Cache for preloaded assets
    private static var assetCache = NSCache<NSString, AVURLAsset>()
    private static var thumbnailCache = NSCache<NSString, UIImage>()
    private static var playerCache = NSCache<NSString, AVPlayer>()
    
    // Configure cache limits
    private static let maxCacheSize = 100 * 1024 * 1024 // 100MB
    private static let maxCacheCount = 10
    
    private static let setupOnce: Void = {
        assetCache.totalCostLimit = maxCacheSize
        assetCache.countLimit = maxCacheCount
        playerCache.countLimit = maxCacheCount
        thumbnailCache.countLimit = maxCacheCount * 2
    }()
    
    // Used to ensure we don't double fade
    private var fadeTask: Task<Void, Never>?
    private var fadeInTask: Task<Void, Error>?
    
    // Additional concurrency
    private var isCleaningUp = false
    private var retryCount = 0
    private let maxRetries = 3
    
    private var subscriptionRequestId: String?
    private var notificationManager = NotificationManager.shared
    
    // Add at the top of the class with other properties
    private var isCheckingStatus = false
    private var lastCheckedVideoId: String?
    
    public init(video: Video) {
        self.video = video
        self.brainCount = video.brainCount
        
        // Configure caches once
        _ = VideoPlayerViewModel.setupOnce
        
        // Disable Firestore debug logging
        Firestore.enableLogging(false)
        
        // Check if video is in user's second brain
        Task {
            do {
                try await checkSecondBrainStatus()
            } catch {
                self.error = "Failed to check second brain status: \(error)"
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
        guard !isCheckingStatus else {
            LoggingService.debug("Status check already in progress for video \(video.id)", component: "Player")
            return
        }
        
        guard lastCheckedVideoId != video.id else {
            LoggingService.debug("Status already checked for video \(video.id)", component: "Player")
            return
        }
        
        isCheckingStatus = true
        defer { 
            isCheckingStatus = false 
            lastCheckedVideoId = video.id
        }
        
        guard let userId = Auth.auth().currentUser?.uid else { 
            LoggingService.debug("No authenticated user, setting isInSecondBrain to false", component: "Player")
            await MainActor.run {
                self.isInSecondBrain = false
                self.brainCount = self.video.brainCount // Ensure we sync with video document
            }
            return 
        }
        
        LoggingService.debug("Starting Second Brain status check for video \(video.id) - Current brainCount: \(brainCount)", component: "Player")
        
        let snapshot = try await firestore.collection("users")
            .document(userId)
            .collection("secondBrain")
            .whereField("videoId", isEqualTo: video.id)
            .limit(to: 1)
            .getDocuments()
        
        // Get the latest video document to ensure brain count is in sync
        let videoDoc = try await firestore.collection("videos").document(video.id).getDocument()
        let latestBrainCount = videoDoc.data()?["brainCount"] as? Int ?? self.video.brainCount
        
        // Update the video model with the latest brain count
        self.video.brainCount = latestBrainCount
        print("Second brain check complete - isInSecondBrain: \(isInSecondBrain), brainCount: \(latestBrainCount)")
        
        await MainActor.run {
            guard self.video.id == video.id else {
                LoggingService.debug("Video ID changed during status check, skipping update", component: "Player")
                return
            }
            
            let exists = !snapshot.documents.isEmpty
            
            LoggingService.debug("Second Brain check results - exists: \(exists), latestCount: \(latestBrainCount), currentCount: \(self.brainCount)", component: "Player")
            
            self.isInSecondBrain = exists
            self.brainCount = latestBrainCount
            
            LoggingService.debug("Updated Second Brain status - exists: \(exists), finalBrainCount: \(self.brainCount)", component: "Player")
        }
    }
    
    @MainActor
    private func cleanup() async {
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
            
            // Remove any pending notifications when the view model is deallocated
            await self.removeNotification()
        }
    }
    
    public func loadVideo() async {
        LoggingService.debug("Starting video load for \(video.id)", component: "Player")
        loadingState = .loading
        loadingProgress = 0
        error = nil
        
        // Check player cache first
        let videoId = video.id as NSString
        if let cachedPlayer = VideoPlayerViewModel.playerCache.object(forKey: videoId) {
            LoggingService.debug("Using cached player for \(video.id)", component: "Player")
            do {
                try await setupPlayer(cachedPlayer)
                return
            } catch {
                LoggingService.error("Failed to setup cached player: \(error)", component: "Player")
            }
        }
        
        // Check asset cache
        let videoUrlString = video.videoURL as NSString
        if let cachedAsset = VideoPlayerViewModel.assetCache.object(forKey: videoUrlString) {
            LoggingService.debug("Using cached asset for \(video.id)", component: "Player")
            do {
                let player = AVPlayer(playerItem: AVPlayerItem(asset: cachedAsset))
                try await setupPlayer(player)
                VideoPlayerViewModel.playerCache.setObject(player, forKey: videoId)
                return
            } catch {
                LoggingService.error("Failed to setup player with cached asset: \(error)", component: "Player")
            }
        }
        
        // Check if we have a preloaded player
        if let preloadedPlayer = preloadedPlayers[video.id] {
            LoggingService.debug("Using preloaded player for \(video.id)", component: "Player")
            do {
                try await setupPlayer(preloadedPlayer)
                preloadedPlayers.removeValue(forKey: video.id)
                VideoPlayerViewModel.playerCache.setObject(preloadedPlayer, forKey: videoId)
                return
            } catch {
                LoggingService.error("Failed to setup preloaded player: \(error)", component: "Player")
            }
        }
        
        // Normal loading path with optimizations
        do {
            guard let url = URL(string: video.videoURL) else {
                throw NSError(domain: "Invalid URL", code: -1)
            }
            
            // Create optimized asset
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetPreferPreciseDurationAndTimingKey": false,
                "AVURLAssetPreferredPeakBitRateKey": 2_000_000 // 2Mbps target bitrate
            ])
            
            // Start loading the asset
            let playableKey = "playable"
            try await asset.loadValues(forKeys: [playableKey])
            
            guard asset.isPlayable else {
                throw VideoPlayerError.assetNotPlayable
            }
            
            // Cache the asset
            VideoPlayerViewModel.assetCache.setObject(asset, forKey: videoUrlString)
            
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            try await setupPlayer(player)
            
            // Cache the player
            VideoPlayerViewModel.playerCache.setObject(player, forKey: videoId)
            
        } catch {
            LoggingService.error("Failed to load video: \(error)", component: "Player")
            self.error = error.localizedDescription
            loadingState = .error(error.localizedDescription)
        }
    }
    
    private func setupPlayer(_ player: AVPlayer) async throws {
        // Remove existing observers
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        // Configure player for optimal performance
        player.automaticallyWaitsToMinimizeStalling = false
        player.currentItem?.preferredForwardBufferDuration = 5 // 5 seconds buffer
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        self.player = player
        
        // Setup buffering observer
        let bufferingObserver = player.observe(\.currentItem?.isPlaybackBufferEmpty) { [weak self] player, _ in
            guard let self = self else { return }
            let isBuffering = player.currentItem?.isPlaybackBufferEmpty ?? false
            Task { @MainActor in
                self.isBuffering = isBuffering
                self.loadingState = isBuffering ? .buffering : .ready
            }
        }
        observers.insert(bufferingObserver)
        
        // Setup loading progress observer with optimized update frequency
        let loadingObserver = player.observe(\.currentItem?.loadedTimeRanges) { [weak self] player, _ in
            guard let self = self,
                  let timeRange = player.currentItem?.loadedTimeRanges.first?.timeRangeValue else { return }
            let duration = player.currentItem?.duration.seconds ?? 0
            let progress = duration > 0 ? timeRange.end.seconds / duration : 0
            if abs(progress - self.loadingProgress) > 0.05 { // Only update if change is significant
                Task { @MainActor in
                    self.loadingProgress = progress
                }
            }
        }
        observers.insert(loadingObserver)
        
        // Setup periodic time observer with optimized interval
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying = player.rate > 0
        }
        
        loadingState = .ready
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
                        let success = try await player.preroll(atRate: 1.0)
                        if success {
                            LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                        } else {
                            LoggingService.error("Preroll failed for \(self.video.id)", component: "Player")
                        }
                    } catch {
                        LoggingService.error("Preroll error for \(self.video.id): \(error)", component: "Player")
                    }
                default:
                    break
                }
            }
        }
        observers.insert(statusObserver)
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
        let previousBrainCount = brainCount
        
        LoggingService.debug("Starting Second Brain toggle for video \(video.id) - Current state: inBrain=\(wasInSecondBrain), count=\(previousBrainCount)", component: "Player")
        
        do {
            // Get reference to the user's second brain collection
            let secondBrainRef = firestore.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(video.id)
            
            // Get reference to the video document
            let videoRef = firestore.collection("videos").document(video.id)
            
            let transactionResult = try await firestore.runTransaction { transaction, errorPointer -> Bool in
                let secondBrainDoc: DocumentSnapshot
                let videoDoc: DocumentSnapshot
                
                do {
                    secondBrainDoc = try transaction.getDocument(secondBrainRef)
                    videoDoc = try transaction.getDocument(videoRef)
                    LoggingService.debug("Successfully fetched documents in transaction", component: "Player")
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return false
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
                    
                    LoggingService.success("Removed video \(self.video.id) from second brain", component: "Player")
                    return false
                } 
                
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
                
                LoggingService.debug("Adding video to second brain with data: \(secondBrainData)", component: "Player")
                transaction.setData(secondBrainData, forDocument: secondBrainRef)
                
                transaction.updateData([
                    "brainCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: videoRef)
                
                LoggingService.success("Added video \(self.video.id) to second brain with \(quotes.count) quotes", component: "Player")
                return true
            }
            
            // Update UI state after transaction completes
            await MainActor.run {
                let wasAdded = (transactionResult as? Bool) ?? false
                self.isInSecondBrain = wasAdded
                self.brainCount = wasAdded ? previousBrainCount + 1 : previousBrainCount - 1
                self.showBrainAnimation = wasAdded
                LoggingService.debug("UI updated after second brain toggle - inBrain=\(self.isInSecondBrain), newCount=\(self.brainCount)", component: "Player")
            }
        } catch {
            // Revert UI state on error
            await MainActor.run {
                self.isInSecondBrain = wasInSecondBrain
                self.brainCount = previousBrainCount
            }
            LoggingService.error("Failed to toggle second brain for video \(video.id): \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    // MARK: - New Method: Pause Playback
    /// Immediately pauses the AVPlayer and updates the isPlaying flag.
    /// This method is used to ensure that offscreen players do not play audio.
    public func pausePlayback() async {
        if let player = player {
            // Fade out audio
            let fadeTime = 0.3
            let steps = 5
            let volumeDecrement = player.volume / Float(steps)
            for step in 0...steps {
                try? await Task.sleep(nanoseconds: UInt64(fadeTime * 1_000_000_000 / Double(steps)))
                player.volume = player.volume - volumeDecrement
            }
            player.pause()
        }
        isPlaying = false
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
    }
    
    // MARK: - Enhanced Play Method
    public func play() async throws {
        LoggingService.debug("Play requested for video \(video.id)", component: "Player")
        
        // Initialize player if needed
        if player == nil || player?.currentItem == nil {
            LoggingService.debug("No player available for \(video.id), loading video", component: "Player")
            await loadVideo()
        }
        
        guard let player = player else {
            let error = NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not available"])
            LoggingService.error("Failed to get player for \(video.id): \(error)", component: "Player")
            throw error
        }
        
        // Ensure volume is set to 1.0 initially
        player.volume = 1.0
        
        // Start playback
        player.play()
        isPlaying = true
        VideoPlayerViewModel.currentlyPlayingViewModel = self
        LoggingService.debug("Started playback for \(video.id)", component: "Player")
        
        // Cancel any existing fade tasks
        cancelFades()
        
        // Fade in audio
        do {
            try await fadeInAudio()
            LoggingService.debug("Completed audio fade in for \(video.id)", component: "Player")
        } catch {
            LoggingService.error("Error during audio fade for \(video.id): \(error)", component: "Player")
            throw error
        }
        
        // Increment view count
        do {
            try await incrementViewCount()
            LoggingService.debug("Incremented view count for \(video.id)", component: "Player")
        } catch {
            LoggingService.error("Failed to increment view count for \(video.id): \(error)", component: "PlayerVM")
            // Don't throw here as view count failure shouldn't stop playback
        }
    }
    
    public func pause() async {
        player?.pause()
    }
    
    public func toggleControls() {
        showControls.toggle()
    }
    
    public func preloadVideo(_ video: Video) async throws {
        LoggingService.debug("Preloading video \(video.id)", component: "Player")
        
        guard let url = URL(string: video.videoURL) else {
            throw NSError(domain: "Invalid URL", code: -1)
        }
        
        let asset = AVURLAsset(url: url)
        
        // Start loading the asset
        try await asset.load(.isPlayable)
        
        guard asset.isPlayable else {
            throw VideoPlayerError.assetNotPlayable
        }
        
        // Cache the asset
        VideoPlayerViewModel.assetCache.setObject(asset, forKey: video.videoURL as NSString)
        
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        preloadedPlayers[video.id] = player
        
        LoggingService.debug("Successfully preloaded video \(video.id)", component: "Player")
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
        let firestore = Firestore.firestore()
        
        // Convert to Sendable dictionary type
        let sendableData = data.mapValues { value -> Any in
            if let value = value as? Date {
                return Timestamp(date: value)
            }
            if let value = value as? String? {
                return value ?? ""  // Provide a default empty string for nil values
            }
            return value
        }
        
        try await firestore.collection("videos").document(videoId).updateData(sendableData)
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
        if let requestId = requestId {
            notificationRequestIds.insert(requestId)
            isSubscribedToNotifications = true
        }
    }
    
    public func removeNotification() async {
        // Remove all notification requests for this video
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(notificationRequestIds))
        notificationRequestIds.removeAll()
        isSubscribedToNotifications = false
    }
} 