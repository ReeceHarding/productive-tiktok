import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine
import AVFoundation
import SwiftUI

@MainActor
public class VideoPlayerViewModel: NSObject, ObservableObject {
    // Video data
    @Published public var video: Video
    @Published public var isPlaying = false
    @Published public var isMuted = false
    @Published public var isLiked = false
    @Published public var isSaved = false
    @Published public var error: String?
    @Published public var isInSecondBrain = false
    @Published public var showBrainAnimation: Bool = false
    @Published public var brainAnimationPosition: CGPoint = .zero
    @Published public var isLoading = false
    @Published public var player: AVPlayer?
    
    // Firebase
    private let firestore = Firestore.firestore()
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    
    public init(video: Video) {
        self.video = video
        super.init()
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
    }
    
    deinit {
        // Schedule cleanup on main actor
        Task { @MainActor in
            await cleanup()
        }
    }
    
    private func cleanup() async {
        LoggingService.video("Cleaning up player for video \(video.id)", component: "Player")
        playerItemStatusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    
    public func loadVideo() async {
        guard !video.videoURL.isEmpty else {
            LoggingService.video("Video URL is empty for \(video.id)", component: "Player")
            return
        }
        
        guard let url = URL(string: video.videoURL) else {
            LoggingService.error("Invalid URL for video \(video.id): \(video.videoURL)", component: "Player")
            error = "Invalid video URL"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            // Clean up existing player first
            await cleanup()
            
            let asset = AVAsset(url: url)
            
            // Load asset asynchronously
            let _ = try await asset.load(.isPlayable)
            
            // Create player item with optimized settings
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2.0
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
            
            // Create new player
            player = AVPlayer(playerItem: playerItem)
            player?.automaticallyWaitsToMinimizeStalling = false
            setupObservers()
            
            LoggingService.video("Successfully loaded video \(video.id)", component: "Player")
            isLoading = false
            
        } catch {
            LoggingService.error("Failed to load video \(video.id): \(error.localizedDescription)", component: "Player")
            self.error = "Failed to load video: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func setupObservers() {
        guard let player = player else { return }
        
        // Clean up existing observers
        playerItemStatusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()
        
        // Observe player item status
        playerItemStatusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .failed:
                    self?.error = item.error?.localizedDescription ?? "Video failed to load"
                    LoggingService.error("Player item failed: \(item.error?.localizedDescription ?? "unknown error")", component: "Player")
                case .readyToPlay:
                    LoggingService.video("Player item ready to play", component: "Player")
                default:
                    break
                }
            }
        }
        
        // Observe playback status
        timeControlStatusObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in
                switch player.timeControlStatus {
                case .playing:
                    self?.isPlaying = true
                    LoggingService.video("Video playback started", component: "Player")
                case .paused:
                    self?.isPlaying = false
                    LoggingService.video("Video playback paused", component: "Player")
                default:
                    break
                }
            }
        }
    }
    
    func addToSecondBrain() async {
        LoggingService.video("Starting add to second brain for video \(video.id)", component: "Player")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("Cannot add to second brain - User not authenticated", component: "Player")
            return
        }
        
        guard let transcript = video.transcript, !transcript.isEmpty else {
            LoggingService.error("Cannot add to second brain - No transcript available", component: "Player")
            return
        }
        
        let secondBrainId = UUID().uuidString
        let secondBrainEntry = SecondBrain(
            id: secondBrainId,
            userId: userId,
            videoId: video.id,
            transcript: transcript,
            quotes: video.extractedQuotes ?? [],
            videoTitle: video.title,
            videoThumbnailURL: video.thumbnailURL
        )
        
        do {
            try await firestore.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(secondBrainId)
                .setData(secondBrainEntry.toFirestoreData())
            
            LoggingService.success("Successfully added video \(video.id) to second brain", component: "Player")
            
            // Trigger brain animation
            withAnimation(.spring()) {
                showBrainAnimation = true
            }
            
            // Hide animation after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation {
                    self.showBrainAnimation = false
                }
            }
        } catch {
            LoggingService.error("Failed to add to second brain: \(error.localizedDescription)", component: "Player")
        }
    }
} 