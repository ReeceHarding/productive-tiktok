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
public class VideoPlayerViewModel: ObservableObject, Hashable {
    // Static property to track currently playing video and prevent multiple instances
    private static var currentlyPlayingViewModel: VideoPlayerViewModel?
    private static var activeViewModels: Set<VideoPlayerViewModel> = []
    
    // MARK: - Hashable Conformance
    public static func == (lhs: VideoPlayerViewModel, rhs: VideoPlayerViewModel) -> Bool {
        // Two view models are equal if they represent the same video
        lhs.video.id == rhs.video.id
    }
    
    public func hash(into hasher: inout Hasher) {
        // Hash only the video ID since that's what we use for equality
        hasher.combine(video.id)
    }
    
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
    
    private var observers: Set<NSKeyValueObservation> = []
    private var timeObserverToken: Any?
    private var deinitHandler: (() -> Void)?
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
    
    private var documentListener: ListenerRegistration?
    
    private var hasIncrementedViewCount = false
    
    public init(video: Video) {
        self.video = video
        self.brainCount = video.brainCount
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
        
        // Add to active view models
        Self.activeViewModels.insert(self)
        
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            LoggingService.debug("Audio session configured successfully", component: "Player")
        } catch {
            LoggingService.error("Failed to configure audio session: \(error)", component: "Player")
        }
        
        setupDocumentListener()
        
        // Add cleanup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCleanupNotification),
            name: .init("CleanupVideoPlayers"),
            object: nil
        )
        
        // Check if video is in user's second brain
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await checkSecondBrainStatus()
            } catch {
                LoggingService.error("Failed to check second brain status: \(error)", component: "Player")
            }
        }
        
        // Setup a synchronous deinit handler to invalidate observers and cleanup player
        let observersCopy = observers
        let playerCopy = player
        let timeObserverTokenCopy = timeObserverToken
        deinitHandler = {
            observersCopy.forEach { $0.invalidate() }
            if let token = timeObserverTokenCopy, let player = playerCopy {
                player.removeTimeObserver(token)
            }
            playerCopy?.pause()
            playerCopy?.replaceCurrentItem(with: nil)
        }
    }
    
    private func setupDocumentListener() {
        // Remove existing listener if any
        documentListener?.remove()
        
        // Set up new listener
        let docRef = firestore.collection("videos").document(video.id)
        documentListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else {
                LoggingService.debug("VideoPlayerViewModel was deallocated during snapshot update", component: "Player")
                return
            }
            
            if let error = error {
                LoggingService.error("Error listening to video \(self.video.id) updates: \(error.localizedDescription)", component: "Player")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists,
                  let updatedVideo = Video(document: snapshot) else {
                LoggingService.error("No valid snapshot for video \(self.video.id)", component: "Player")
                return
            }
            
            // Update video model
            Task { [weak self] in
                guard let self = self else { return }
                await MainActor.run {
                    let oldStatus = self.video.processingStatus
                    self.video = updatedVideo
                    
                    // If status changed to ready, attempt to load the video
                    if oldStatus != .ready && updatedVideo.processingStatus == .ready {
                        LoggingService.video("Video \(self.video.id) is now ready, loading video...", component: "Player")
                        Task {
                            await self.loadVideo()
                        }
                    }
                }
            }
        }
        
        LoggingService.debug("Set up document listener for video \(video.id)", component: "Player")
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
    public func cleanup() async {
        if isCleaningUp {
            LoggingService.debug("Cleanup already in progress for video: \(video.id)", component: "Player")
            return
        }
        isCleaningUp = true
        
        LoggingService.debug("Starting cleanup for video: \(video.id)", component: "Player")
        
        // Safely remove document listener
        if let listener = documentListener {
            listener.remove()
            documentListener = nil
            LoggingService.debug("Removed document listener for video: \(video.id)", component: "Player")
        }
        
        // Cancel any existing tasks
        fadeTask?.cancel()
        fadeInTask?.cancel()
        fadeTask = nil
        fadeInTask = nil
        LoggingService.debug("Cancelled fade tasks for video: \(video.id)", component: "Player")
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        LoggingService.debug("Removed notification observers for video: \(video.id)", component: "Player")
        
        // Safely invalidate observers
        for observer in observers {
            observer.invalidate()
            LoggingService.debug("Invalidated observer for video: \(video.id)", component: "Player")
        }
        observers.removeAll()
        
        if let observer = bufferingObserver {
            observer.invalidate()
            bufferingObserver = nil
            LoggingService.debug("Invalidated buffering observer for video: \(video.id)", component: "Player")
        }
        
        if let observer = loadingObserver {
            observer.invalidate()
            loadingObserver = nil
            LoggingService.debug("Invalidated loading observer for video: \(video.id)", component: "Player")
        }
        
        // Clear player
        if let player = player {
            if let token = timeObserverToken {
                player.removeTimeObserver(token)
                timeObserverToken = nil
                LoggingService.debug("Removed time observer for video: \(video.id)", component: "Player")
            }
            player.pause()
            player.replaceCurrentItem(with: nil)
            self.player = nil
            LoggingService.debug("Cleared player for video: \(video.id)", component: "Player")
        }
        
        // Clear preloaded players
        for (_, player) in preloadedPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        preloadedPlayers.removeAll()
        LoggingService.debug("Cleared preloaded players for video: \(video.id)", component: "Player")
        
        isCleaningUp = false
        LoggingService.debug("Completed cleanup for video: \(video.id)", component: "Player")
    }
    
    deinit {
        Task { @MainActor in
            let videoId = self.video.id
            LoggingService.debug("VideoPlayerViewModel deinit started for video: \(videoId)", component: "Player")
            
            // Remove from active view models
            Self.activeViewModels.remove(self)
            
            // Execute cleanup synchronously to ensure it completes
            await cleanup()
            
            // Execute deinit handler if it exists
            self.deinitHandler?()
            self.deinitHandler = nil
            
            // Clear all references that might cause retain cycles
            self.player = nil
            self.observers.removeAll()
            self.bufferingObserver = nil
            self.loadingObserver = nil
            self.documentListener = nil
            self.timeObserverToken = nil
            self.preloadedPlayers.removeAll()
            
            LoggingService.debug("VideoPlayerViewModel deinit completed for video: \(videoId)", component: "Player")
        }
    }
    
    public func loadVideo() async {
        LoggingService.video("🎬 Starting loadVideo for \(video.id)", component: "Player")
        isLoading = true
        loadingProgress = 0
        error = nil
        
        // Check if we have a preloaded player first
        if let preloadedPlayer = preloadedPlayers[video.id] {
            LoggingService.video("✅ Using preloaded player for \(video.id)", component: "Player")
            do {
                try await setupPlayer(preloadedPlayer)
                preloadedPlayers.removeValue(forKey: video.id)
                LoggingService.video("✅ Successfully set up preloaded player for \(video.id)", component: "Player")
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
            
            try await Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.setupPlayer(player)
                } catch {
                    LoggingService.error("Failed to setup player: \(error)", component: "Player")
                }
            }.value

            // Wait for player to be ready before attempting preroll
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let statusObserver = player.observe(\.status) { [weak self] player, _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        switch player.status {
                        case .failed:
                            self.error = player.error?.localizedDescription
                            LoggingService.error("Player failed for \(self.video.id): \(player.error?.localizedDescription ?? "Unknown error")", component: "Player")
                            continuation.resume(throwing: player.error ?? NSError(domain: "AVPlayer", code: -1))
                        case .readyToPlay:
                            LoggingService.video("Player ready for \(self.video.id)", component: "Player")
                            // Start buffering only when player is ready
                            try await Task {
                                do {
                                    let success = try await player.preroll(atRate: 1.0)
                                    if success {
                                        LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                                        continuation.resume()
                                    } else {
                                        LoggingService.error("Preroll failed for \(self.video.id)", component: "Player")
                                        continuation.resume(throwing: NSError(domain: "AVPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Preroll failed"]))
                                    }
                                } catch {
                                    LoggingService.error("Preroll error for \(self.video.id): \(error)", component: "Player")
                                    continuation.resume(throwing: error)
                                }
                            }.value
                        default:
                            break
                        }
                    }
                }
                observers.insert(statusObserver)
            }
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    private func setupPlayer(_ player: AVPlayer) async throws {
        LoggingService.video("Setting up player for \(video.id)", component: "Player")
        
        // Clean up existing player first
        await cleanup()
        
        self.player = player
        
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
        
        // Wait for player to be ready before attempting preroll
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let statusObserver = player.observe(\.status) { [weak self] player, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    switch player.status {
                    case .failed:
                        self.error = player.error?.localizedDescription
                        LoggingService.error("Player failed for \(self.video.id): \(player.error?.localizedDescription ?? "Unknown error")", component: "Player")
                        continuation.resume(throwing: player.error ?? NSError(domain: "AVPlayer", code: -1))
                    case .readyToPlay:
                        LoggingService.video("Player ready for \(self.video.id)", component: "Player")
                        // Start buffering only when player is ready
                        Task {
                            do {
                                let success = try await player.preroll(atRate: 1.0)
                                if success {
                                    LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                                    continuation.resume()
                                } else {
                                    LoggingService.error("Preroll failed for \(self.video.id)", component: "Player")
                                    continuation.resume(throwing: NSError(domain: "AVPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Preroll failed"]))
                                }
                            } catch {
                                LoggingService.error("Preroll error for \(self.video.id): \(error)", component: "Player")
                                continuation.resume(throwing: error)
                            }
                        }
                    default:
                        break
                    }
                }
            }
            observers.insert(statusObserver)
        }
        
        LoggingService.video("✅ Player setup complete for \(video.id)", component: "Player")
        isLoading = false
        
        // Store in preloaded players
        preloadedPlayers[video.id] = player
        LoggingService.video("✅ Successfully preloaded video \(video.id)", component: "Player")
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
        Task { [weak self] in
            try? await self?.fadeInAudio()
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
            
            let transactionResult = try await firestore.runTransaction { (transaction, errorPointer) -> Any? in
                let secondBrainDoc: DocumentSnapshot
                let videoDoc: DocumentSnapshot
                
                do {
                    secondBrainDoc = try transaction.getDocument(secondBrainRef)
                    videoDoc = try transaction.getDocument(videoRef)
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
                    
                    LoggingService.success("Removed video \(self.video.id) from second brain", component: "Player")
                    return true as Any
                } else {
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
                    return false as Any
                }
            }
            
            // Update UI state after transaction completes
            await MainActor.run {
                if let wasRemoved = transactionResult as? Bool {
                    if wasRemoved {
                        self.isInSecondBrain = false
                        self.brainCount -= 1
                        self.showBrainAnimation = false
                        LoggingService.debug("UI updated after removing from second brain", component: "Player")
                    } else {
                        self.isInSecondBrain = true
                        self.brainCount += 1
                        self.showBrainAnimation = true
                        LoggingService.debug("UI updated after adding to second brain", component: "Player")
                    }
                }
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
        LoggingService.debug("▶️ Play requested for video \(video.id)", component: "Player")
        
        // Initialize player if needed
        if player == nil || player?.currentItem == nil {
            LoggingService.debug("Player is nil, loading video first for \(video.id)", component: "Player")
            await loadVideo()
        }
        
        guard let player = player else {
            LoggingService.error("❌ Player still nil after loadVideo for \(video.id)", component: "Player")
            return
        }
        
        // Ensure volume is set to 1.0 initially
        let previousVolume = player.volume
        player.volume = 1.0
        LoggingService.debug("Initial volume set to 1.0 (was \(previousVolume)) for video \(video.id)", component: "Player")
        
        // Start playback
        player.play()
        isPlaying = true
        VideoPlayerViewModel.currentlyPlayingViewModel = self
        LoggingService.debug("🎵 Playback started for video \(video.id)", component: "Player")
        
        // Cancel any existing fade tasks
        cancelFades()
        
        // Fade in audio
        do {
            LoggingService.debug("Starting audio fade in for video \(video.id)", component: "Player")
            try await fadeInAudio()
        } catch {
            LoggingService.error("Error during audio fade: \(error)", component: "Player")
        }
        
        // Increment view count
        do {
            try await incrementViewCount()
        } catch {
            LoggingService.error("Failed to increment view count: \(error)", component: "Player")
        }
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
        LoggingService.debug("Starting fadeOutAudio for video \(video.id), initial volume: \(player.volume)", component: "Player")
        cancelFades()
        let steps = 5
        let time = 0.3
        let chunk = player.volume / Float(steps)
        fadeTask = Task {
            for step in 0..<steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(time*1_000_000_000 / Double(steps)))
                player.volume -= chunk
                LoggingService.debug("FadeOut step \(step + 1)/\(steps), volume now: \(player.volume)", component: "Player")
            }
        }
        await fadeTask?.value
        LoggingService.debug("FadeOut complete for video \(video.id), final volume: \(player.volume)", component: "Player")
    }
    
    private func fadeInAudio() async throws {
        guard let player = player else { return }
        
        LoggingService.debug("Starting fadeInAudio for video \(video.id), initial volume: \(player.volume)", component: "Player")
        
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
                LoggingService.debug("FadeIn step \(i + 1)/\(steps), volume now: \(player.volume)", component: "Player")
                try await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
            
            // Ensure we end at full volume
            if !Task.isCancelled {
                player.volume = 1.0
                LoggingService.debug("FadeIn complete, final volume set to 1.0", component: "Player")
            }
            
            LoggingService.debug("Audio fade complete for video \(video.id)", component: "Player")
        }
        
        // Wait for fade to complete
        try await fadeInTask?.value
    }
    
    @MainActor
    private func updateSecondBrainStatus() async throws {
        let videoId = video.id // Capture video.id on MainActor
        let isInSecondBrainValue = isInSecondBrain // Capture isInSecondBrain on MainActor
        
        let data: [String: SendableValue] = [
            "isInSecondBrain": .bool(isInSecondBrainValue)
        ]
        
        try await firestore.collection("videos").document(videoId).updateData(data.asDictionary)
    }
    
    private func prerollIfNeeded() async throws {
        guard let player = player else { return }
        let success = try await player.preroll(atRate: 1.0)
        if success {
            let videoId = await MainActor.run { video.id }
            LoggingService.video("Preroll complete for \(videoId)", component: "Player")
        } else {
            let videoId = await MainActor.run { video.id }
            LoggingService.error("Preroll failed for \(videoId)", component: "Player")
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
        guard !hasIncrementedViewCount else {
            LoggingService.debug("View count already incremented for video \(video.id)", component: "Player")
            return
        }
        
        // Check if another instance has already incremented the view count
        if Self.activeViewModels.contains(where: { $0 !== self && $0.video.id == video.id && $0.hasIncrementedViewCount }) {
            LoggingService.debug("View count already incremented by another instance for video \(video.id)", component: "Player")
            return
        }
        
        LoggingService.video("Incrementing view count for video \(video.id)", component: "Player")
        
        do {
            // Use a transaction to ensure atomic update
            try await firestore.runTransaction { [videoId = video.id] (transaction, errorPointer) -> Any? in
                do {
                    let videoRef = self.firestore.collection("videos").document(videoId)
                    let videoDoc = try transaction.getDocument(videoRef)
                    
                    guard videoDoc.exists else {
                        let error = NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video document not found"])
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    transaction.updateData([
                        "viewCount": FieldValue.increment(Int64(1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            
            hasIncrementedViewCount = true
            LoggingService.video("Successfully incremented view count for video \(video.id)", component: "Player")
            
            // Update local state
            await MainActor.run {
                video.viewCount += 1
            }
        } catch {
            LoggingService.error("Failed to increment view count for video \(video.id): \(error.localizedDescription)", component: "Player")
            throw error
        }
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
    
    @objc private func handleCleanupNotification(_ notification: Notification) {
        LoggingService.debug("Received cleanup notification for video: \(video.id)", component: "Player")
        
        let cleanupGroup = notification.userInfo?["cleanupGroup"] as? DispatchGroup
        
        Task {
            await cleanup()
            cleanupGroup?.leave()
            LoggingService.debug("Cleanup notification handled for video: \(video.id)", component: "Player")
        }
    }
} 