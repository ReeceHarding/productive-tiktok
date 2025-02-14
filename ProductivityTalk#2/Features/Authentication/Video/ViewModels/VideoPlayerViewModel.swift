import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI
import OSLog
import UserNotifications

@MainActor
public class VideoPlayerViewModel: ObservableObject {
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
    private var bufferingObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private var notificationRequestIds: Set<String> = []
    private var isCleaningUp = false
    private var retryCount = 0
    private let maxRetries = 3
    
    private var subscriptionRequestId: String?
    private var notificationManager = NotificationManager.shared
    
    public init(video: Video) {
        self.video = video
        self.brainCount = video.brainCount
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
        
        Task {
            do {
                try await checkSecondBrainStatus()
            } catch {
                LoggingService.error("Failed to check second brain status: \(error)", component: "Player")
            }
        }
        
        let observersCopy = observers
        let playerCopy = player
        let timeObserverTokenCopy = timeObserverToken
        deinitHandler = { [observersCopy, playerCopy, timeObserverTokenCopy] in
            observersCopy.forEach { $0.invalidate() }
            if let token = timeObserverTokenCopy, let pl = playerCopy {
                pl.removeTimeObserver(token)
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
        do {
            try await loadVideo()
        } catch {
            LoggingService.error("Retry attempt \(retryCount) failed: \(error.localizedDescription)", component: "Player")
            if retryCount >= maxRetries {
                self.error = "Unable to load video after multiple attempts"
            }
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
    
    @MainActor
    public func cleanup() async {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        let videoId = video.id
        LoggingService.debug("🧹 Starting cleanup for video \(videoId)", component: "PlayerVM")
        
        if let pl = player {
            LoggingService.debug("Stopping playback during cleanup for \(videoId)", component: "PlayerVM")
            pl.pause()
            pl.volume = 0
        }
        
        LoggingService.debug("Invalidating observers for video \(videoId)", component: "PlayerVM")
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        bufferingObserver?.invalidate()
        bufferingObserver = nil
        
        loadingObserver?.invalidate()
        loadingObserver = nil
        
        if let token = timeObserverToken, let pl = player {
            LoggingService.debug("Removing time observer for video \(videoId)", component: "PlayerVM")
            pl.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        if let pl = player {
            LoggingService.debug("Final player cleanup for video \(videoId)", component: "PlayerVM")
            pl.replaceCurrentItem(with: nil)
            player = nil
            isPlaying = false
        }
        
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            LoggingService.debug("Clearing static reference to current player for \(videoId)", component: "PlayerVM")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        
        isCleaningUp = false
        LoggingService.debug("✅ Cleanup complete for video \(videoId)", component: "PlayerVM")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    
    deinit {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let videoId = self.video.id
            if let handler = self.deinitHandler {
                await handler()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            do {
                await self.cleanup()
                LoggingService.debug("VideoPlayerViewModel deinit for video \(videoId)", component: "Player")
            } catch {
                LoggingService.error("Error during cleanup in deinit for \(videoId): \(error)", component: "Player")
            }
        }
        Task.detached {
            await self.removeNotification()
        }
    }
    
    public func loadVideo() async throws {
        LoggingService.video("🎬 Starting loadVideo for \(video.id)", component: "Player")
        isLoading = true
        loadingProgress = 0
        error = nil
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for \(video.id)", component: "Player")
            error = "Invalid video URL"
            isLoading = false
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URL"])
        }
        
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4",
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])
        
        LoggingService.video("🔄 Starting immediate asset loading for \(video.id)", component: "Player")
        
        do {
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 5
            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = false
            
            guard playable else {
                LoggingService.error("❌ Asset not playable for \(video.id)", component: "Player")
                await MainActor.run {
                    error = "Video format not supported"
                    isLoading = false
                }
                throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video format not supported"])
            }
            
            try await waitForPlayerReady(newPlayer)
            
            Task { [weak self] in
                guard let self = self else { return }
                self.setupObservers(for: newPlayer, playerItem: playerItem, duration: duration)
            }
            
            await MainActor.run {
                self.player = newPlayer
                self.isLoading = false
                LoggingService.video("✅ Player ready for immediate playback: \(self.video.id)", component: "Player")
            }
            
            do {
                try await newPlayer.preroll(atRate: 1.0)
            } catch {
                LoggingService.error("Preroll failed: \(error.localizedDescription)", component: "Player")
            }
            
        } catch {
            LoggingService.error("Failed to setup player: \(error.localizedDescription)", component: "Player")
            self.error = "Failed to load video: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }
    
    private func waitForPlayerReady(_ player: AVPlayer) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let obs = player.observe(\.status, options: [.new, .initial]) { plr, _ in
                if plr.status == .readyToPlay {
                    continuation.resume()
                } else if plr.status == .failed {
                    continuation.resume(throwing: plr.error ?? NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player failed"]))
                }
            }
            observers.insert(obs)
        }
    }
    
    private func setupObservers(for player: AVPlayer, playerItem: AVPlayerItem, duration: CMTime) {
        let durationInSeconds = CMTimeGetSeconds(duration)
        
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
        
        bufferingObserver = player.observe(\.timeControlStatus) { [weak self] pl, _ in
            Task { @MainActor in
                self?.isBuffering = pl.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        
        addTimeObserver(to: player)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    private func addTimeObserver(to player: AVPlayer) {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        let interval = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task {
                // watch time updates if needed
            }
        }
        timeObserverToken = token
    }
    
    @objc private func playerItemDidReachEnd() {
        LoggingService.debug("🔄 Video reached end, initiating loop (video: \(video.id))", component: "Player")
        guard let player = player else { return }
        
        player.seek(to: .zero)
        
        Task {
            do {
                try await play()
            } catch {
                LoggingService.error("Error restarting playback after end: \(error)", component: "Player")
            }
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
        let videoId = video.id
        
        do {
            let secondBrainRef = firestore.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(videoId)
            
            let videoRef = firestore.collection("videos").document(videoId)
            
            let transactionResult = try await firestore.runTransaction { [weak self] (transaction, errorPointer) -> Any? in
                guard let self = self else { return nil }
                
                let secondBrainDoc: DocumentSnapshot
                let videoDoc: DocumentSnapshot
                
                do {
                    secondBrainDoc = try transaction.getDocument(secondBrainRef)
                    videoDoc = try transaction.getDocument(videoRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                transaction.updateData([
                    "watchTime": FieldValue.serverTimestamp()
                ], forDocument: videoRef)
                
                if secondBrainDoc.exists {
                    transaction.deleteDocument(secondBrainRef)
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(-1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    return false as Any
                } else {
                    let videoData = videoDoc.data() ?? [:]
                    let quotes = videoData["quotes"] as? [String] ?? []
                    let transcript = videoData["transcript"] as? String ?? ""
                    let category = (videoData["tags"] as? [String])?.first ?? "Uncategorized"
                    let title = videoData["title"] as? String ?? "No title"
                    let thumbURL = videoData["thumbnailURL"] as? String ?? ""
                    
                    let secondBrainData: [String: Any] = [
                        "videoId": videoId,
                        "userId": userId,
                        "quotes": quotes,
                        "transcript": transcript,
                        "category": category,
                        "videoTitle": title,
                        "videoThumbnailURL": thumbURL,
                        "savedAt": FieldValue.serverTimestamp()
                    ]
                    
                    transaction.setData(secondBrainData, forDocument: secondBrainRef)
                    
                    transaction.updateData([
                        "brainCount": FieldValue.increment(Int64(1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: videoRef)
                    
                    return true as Any
                }
            }
            
            await MainActor.run {
                if let wasAdded = transactionResult as? Bool {
                    if wasAdded {
                        self.isInSecondBrain = true
                        self.brainCount += 1
                        self.showBrainAnimation = true
                        
                        self.toastMessage = "Added to Second Brain"
                        
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            self.showBrainAnimation = false
                            self.toastMessage = nil
                        }
                    } else {
                        self.isInSecondBrain = false
                        self.brainCount -= 1
                        self.showBrainAnimation = false
                        
                        self.toastMessage = "Removed from Second Brain"
                        
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
            LoggingService.error("❌ Failed to toggle second brain for video \(videoId): \(error.localizedDescription)", component: "Player")
            throw error
        }
    }
    
    @MainActor
    public func play() async throws {
        LoggingService.debug("🎬 Starting play() for video \(video.id)", component: "PlayerVM")
        
        if player == nil || player?.currentItem == nil {
            LoggingService.debug("No player exists, loading video first", component: "PlayerVM")
            try await loadVideo()
        }
        
        guard let pl = player else {
            LoggingService.error("❌ Failed to get player instance for video \(video.id)", component: "PlayerVM")
            return
        }
        
        if let currentPlaying = VideoPlayerViewModel.currentlyPlayingViewModel,
           currentPlaying !== self {
            LoggingService.debug("⚠️ Found another playing video (\(currentPlaying.video.id)), cleaning up", component: "PlayerVM")
            await currentPlaying.cleanup()
        }
        
        pl.volume = 0
        LoggingService.debug("🔊 Starting playback for video \(video.id)", component: "PlayerVM")
        pl.play()
        isPlaying = true
        VideoPlayerViewModel.currentlyPlayingViewModel = self
        
        cancelFades()
        
        do {
            LoggingService.debug("Starting audio fade in for video \(video.id)", component: "PlayerVM")
            try await fadeInAudio()
            LoggingService.debug("✅ Audio fade in complete for video \(video.id)", component: "PlayerVM")
        } catch {
            LoggingService.error("Error during audio fade: \(error)", component: "PlayerVM")
        }
        
        do {
            try await incrementViewCount()
        } catch {
            LoggingService.error("Failed to increment view count: \(error)", component: "PlayerVM")
        }
    }
    
    public func pausePlayback() async {
        LoggingService.debug("⏸️ pausePlayback() called for video \(video.id)", component: "PlayerVM")
        if let pl = player {
            let fadeTime = 0.3
            let steps = 5
            let volumeDecrement = pl.volume / Float(steps)
            for step in 0...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(fadeTime * 1_000_000_000 / Double(steps)))
                pl.volume -= volumeDecrement
                LoggingService.debug("Fading out audio: step \(step) of \(steps), volume=\(pl.volume)", component: "PlayerVM")
            }
            LoggingService.debug("Pausing player for video \(video.id)", component: "PlayerVM")
            pl.pause()
        }
        isPlaying = false
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            LoggingService.debug("Clearing currently playing video reference", component: "PlayerVM")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        LoggingService.debug("✅ Player paused and isPlaying set to false for video \(video.id)", component: "PlayerVM")
    }
    
    public func pause() {
        LoggingService.video("⏸️ PAUSE requested for video \(video.id)", component: "Player")
        player?.pause()
        LoggingService.video("✅ PAUSE command issued for video \(video.id)", component: "Player")
    }
    
    public func toggleControls() {
        LoggingService.video("Toggling controls for \(video.id)", component: "Player")
        showControls.toggle()
    }
    
    public func preloadVideo(_ video: Video) async {
        LoggingService.video("Preloading video \(video.id)", component: "Player")
        
        if let _ = player {
            return
        }
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("❌ Invalid URL for preloading \(video.id)", component: "Player")
            return
        }
        
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
            let preloadedPlayer = AVPlayer(playerItem: playerItem)
            preloadedPlayer.automaticallyWaitsToMinimizeStalling = false
            
            try await waitForPlayerReady(preloadedPlayer)
            
            do {
                let success = try await preloadedPlayer.preroll(atRate: 1.0)
                if success {
                    LoggingService.video("✅ Successfully prerolled video \(video.id)", component: "Player")
                    self.player = preloadedPlayer
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
    
    private func cancelFades() {
        // No separate fade tasks, we just do fade in/out inline in this code
    }
    
    @MainActor
    private func fadeInAudio() async throws {
        guard let pl = player else {
            LoggingService.debug("No player available for fade in", component: "Player")
            return
        }
        
        let steps = 10
        let duration = 0.5
        let stepDuration = duration / Double(steps)
        for i in 0...steps {
            if Task.isCancelled { return }
            pl.volume = Float(i) / Float(steps)
            try await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        if !Task.isCancelled {
            pl.volume = 1.0
            LoggingService.debug("✅ Audio fade complete for video \(video.id)", component: "Player")
        }
    }
    
    private func incrementViewCount() async throws {
        let data: [String: Any] = [
            "viewCount": video.viewCount + 1
        ]
        try await updateVideoStats(data: data)
    }
    
    @MainActor
    private func updateVideoStats(data: [String: Any]) async throws {
        let videoId = video.id
        try await updateVideoData(videoId: videoId, data: data)
    }
    
    nonisolated private func updateVideoData(videoId: String, data: [String: Any]) async throws {
        let firestore = Firestore.firestore()
        let sendableData = data.mapValues { value -> Any in
            if let value = value as? Date {
                return Timestamp(date: value)
            }
            return value
        }
        
        do {
            try await firestore.collection("videos").document(videoId).updateData(sendableData)
            await MainActor.run {
                LoggingService.video("✅ Successfully updated video data for \(videoId)", component: "Player")
            }
        } catch {
            await MainActor.run {
                LoggingService.error("Failed to update video data: \(error.localizedDescription)", component: "Player")
            }
            throw error
        }
    }
    
    public func removeNotification() async {
        LoggingService.debug("Removing notifications for video \(video.id)", component: "Player")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(notificationRequestIds))
        notificationRequestIds.removeAll()
        isSubscribedToNotifications = false
        LoggingService.debug("Removed all notification requests", component: "Player")
    }
    
    public func updateNotificationState(requestId: String?) {
        LoggingService.debug("Updating notification state for video \(video.id)", component: "Player")
        if let requestId = requestId {
            notificationRequestIds.insert(requestId)
            isSubscribedToNotifications = true
            LoggingService.debug("Added notification request ID: \(requestId)", component: "Player")
        }
    }
}