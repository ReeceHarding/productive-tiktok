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
    
    private var observers: [NSKeyValueObservation] = []
    private var deinitHandler: (() -> Void)?
    
    public init(video: Video) {
        self.video = video
        LoggingService.video("Initialized player for video \(video.id)", component: "Player")
        
        // Capture the cleanup values in a closure that can be called from deinit
        let observersCopy = observers
        let playerCopy = player
        deinitHandler = { [observersCopy, playerCopy] in
            // These operations are thread-safe
            observersCopy.forEach { $0.invalidate() }
            playerCopy?.pause()
            playerCopy?.replaceCurrentItem(with: nil)
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
    
    public func loadVideo() async {
        guard !isLoading else { 
            LoggingService.debug("Skipping load - already loading video \(video.id)", component: "Player")
            return 
        }
        guard !video.videoURL.isEmpty else { 
            LoggingService.debug("Skipping load - empty URL for video \(video.id)", component: "Player")
            return 
        }
        
        isLoading = true
        LoggingService.debug("Starting to load video \(video.id)", component: "Player")
        
        // Clean up existing player
        cleanup()
        
        do {
            guard let url = URL(string: video.videoURL) else {
                LoggingService.error("Invalid URL for video \(video.id)", component: "Player")
                return
            }
            
            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: playerItem)
            
            // Status observation with weak self to prevent retain cycles
            let statusObserver = playerItem.observe(\.status) { [weak self] item, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if item.status == .failed {
                        self.error = item.error?.localizedDescription
                        LoggingService.error("Failed to load video \(self.video.id): \(item.error?.localizedDescription ?? "Unknown error")", component: "Player")
                    }
                }
            }
            observers.append(statusObserver)
            
            player = newPlayer
            
            // Update deinitHandler with new values
            let observersCopy = observers
            let playerCopy = player
            deinitHandler = { [observersCopy, playerCopy] in
                observersCopy.forEach { $0.invalidate() }
                playerCopy?.pause()
                playerCopy?.replaceCurrentItem(with: nil)
            }
            
            LoggingService.success("Successfully loaded video \(video.id)", component: "Player")
        } catch {
            self.error = error.localizedDescription
            LoggingService.error("Error loading video \(video.id): \(error.localizedDescription)", component: "Player")
        }
        
        isLoading = false
    }
    
    public func addToSecondBrain() async {
        showBrainAnimation = true
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        showBrainAnimation = false
    }
} 