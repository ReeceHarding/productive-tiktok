import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI

@MainActor
public class VideoPlayerViewModel: ObservableObject {
    @Published public var video: Video
    @Published public var player: AVPlayer?
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var showBrainAnimation = false
    @Published public var brainAnimationPosition: CGPoint = .zero
    @Published public var isInSecondBrain = false
    @Published public var brainCount: Int = 0
    @Published public var showControls = true
    
    private var observers: [NSKeyValueObservation] = []
    private var deinitHandler: (() -> Void)?
    private let firestore = Firestore.firestore()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    
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
        deinitHandler = { [observersCopy, playerCopy] in
            observersCopy.forEach { $0.invalidate() }
            playerCopy?.pause()
            playerCopy?.replaceCurrentItem(with: nil)
        }
    }
    
    private func checkSecondBrainStatus() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let snapshot = try await firestore.collection("users")
            .document(userId)
            .collection("secondBrain")
            .whereField("videoId", isEqualTo: video.id)
            .limit(to: 1)
            .getDocuments()
        
        await MainActor.run {
            self.isInSecondBrain = !snapshot.documents.isEmpty
        }
    }
    
    private func cleanup() {
        // Invalidate observers - this is thread-safe
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        
        // Clean up player
        if let player = player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player = nil
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
                    await Task { @MainActor in
                        do {
                            try await player.preroll(atRate: 1.0)
                            LoggingService.video("Preroll complete for \(self.video.id)", component: "Player")
                        } catch {
                            LoggingService.error("Preroll failed for \(self.video.id): \(error.localizedDescription)", component: "Player")
                        }
                    }
                default:
                    break
                }
            }
        }
        observers.append(statusObserver)
    }
    
    public func addToSecondBrain() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("Cannot add to SecondBrain: No authenticated user", component: "SecondBrain")
            return
        }
        
        // Optimistic update
        let wasInSecondBrain = isInSecondBrain
        isInSecondBrain.toggle()
        brainCount += wasInSecondBrain ? -1 : 1
        
        showBrainAnimation = true
        
        do {
            if wasInSecondBrain {
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
            brainCount -= wasInSecondBrain ? -1 : 1
            LoggingService.error("Failed to update SecondBrain: \(error.localizedDescription)", component: "SecondBrain")
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        showBrainAnimation = false
    }
    
    public func play() {
        LoggingService.video("Playing video \(video.id)", component: "Player")
        player?.play()
    }
    
    public func pause() {
        LoggingService.video("Pausing video \(video.id)", component: "Player")
        player?.pause()
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
                
                // Start preloading
                try await player.preroll(atRate: 1.0)
                
                // Store in preloaded players
                preloadedPlayers[video.id] = player
                LoggingService.video("✅ Successfully preloaded video \(video.id)", component: "Player")
            } catch {
                LoggingService.error("Failed to preload video \(video.id): \(error.localizedDescription)", component: "Player")
            }
        }
    }
} 