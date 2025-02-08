import Foundation
import AVKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
class VideoPlayerViewModel: ObservableObject {
    private let video: Video
    @Published var player: AVPlayer?
    @Published private(set) var isLiked = false
    @Published private(set) var isSaved = false
    @Published private(set) var playerStatus: String = "unknown"
    @Published private(set) var playerError: String?
    @Published var isInSecondBrain = false
    
    private let firestore = Firestore.firestore()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    
    init(video: Video) {
        self.video = video
        print("📱 VideoPlayer: Initialized for video ID: \(video.id)")
        setupPlayer()
        checkInteractionStatus()
    }
    
    func setupPlayer() {
        guard let url = URL(string: video.videoURL) else {
            print("❌ VideoPlayer: Invalid video URL")
            return
        }
        
        print("🎬 VideoPlayer: Setting up player for URL: \(url)")
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Configure for looping
        print("🔄 VideoPlayer: Configuring video to loop")
        player.actionAtItemEnd = .none
        
        // Add periodic time observer
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            guard let _ = self else { return }
            print("⏱️ VideoPlayer: Playback time: \(time.seconds) seconds")
        }
        
        // Observe player status
        statusObserver = player.observe(\.status, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in
                switch player.status {
                case .readyToPlay:
                    print("✅ VideoPlayer: Player ready to play")
                    self?.playerStatus = "ready"
                case .failed:
                    let error = player.error?.localizedDescription ?? "Unknown error"
                    print("❌ VideoPlayer: Player failed - \(error)")
                    self?.playerStatus = "failed"
                    self?.playerError = error
                case .unknown:
                    print("⚠️ VideoPlayer: Player status unknown")
                    self?.playerStatus = "unknown"
                @unknown default:
                    print("⚠️ VideoPlayer: Player status - unexpected value")
                    self?.playerStatus = "unexpected"
                }
            }
        }
        
        // Observe player errors
        errorObserver = player.observe(\.error, options: [.new]) { [weak self] player, _ in
            if let error = player.error {
                Task { @MainActor in
                    print("❌ VideoPlayer: Player error - \(error.localizedDescription)")
                    self?.playerError = error.localizedDescription
                }
            }
        }
        
        // Add notification observers for playback issues
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEndTime),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: player.currentItem
        )
        
        // Configure AVPlayerItem
        if let playerItem = player.currentItem {
            print("📊 VideoPlayer: Buffer full duration: \(playerItem.duration.seconds) seconds")
            print("📊 VideoPlayer: Playback buffer full: \(playerItem.isPlaybackBufferFull)")
            print("📊 VideoPlayer: Playback buffer empty: \(playerItem.isPlaybackBufferEmpty)")
            print("📊 VideoPlayer: Playback likely to keep up: \(playerItem.isPlaybackLikelyToKeepUp)")
        }
        
        self.player = player
        
        // Start playing
        player.play()
    }
    
    @objc private func playerItemDidPlayToEndTime() {
        print("✅ VideoPlayer: Playback completed - restarting for loop")
        player?.seek(to: .zero)
        player?.play()
    }
    
    @objc private func playerItemFailedToPlayToEndTime(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            print("❌ VideoPlayer: Failed to play to end - \(error.localizedDescription)")
            self.playerError = error.localizedDescription
        }
    }
    
    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        print("⚠️ VideoPlayer: Playback stalled")
        // Try to recover by seeking slightly ahead
        if let player = self.player, let currentTime = player.currentItem?.currentTime() {
            let newTime = CMTimeAdd(currentTime, CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
            player.seek(to: newTime)
            player.play()
        }
    }
    
    func cleanup() {
        print("🧹 VideoPlayer: Cleaning up resources")
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        errorObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        player = nil
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
        Task {
            do {
                let secondBrainDoc = try await firestore.collection("users")
                    .document(userId)
                    .collection("secondBrain")
                    .document(video.id)
                    .getDocument()
                
                await MainActor.run {
                    self.isInSecondBrain = secondBrainDoc.exists
                }
                print("✅ VideoPlayer: Second Brain status checked - isInSecondBrain: \(self.isInSecondBrain)")
            } catch {
                print("❌ VideoPlayer: Error checking Second Brain status: \(error.localizedDescription)")
            }
        }
    }
    
    func toggleLike() {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ VideoPlayer: No authenticated user")
            return
        }
        
        let videoRef = firestore.collection("videos").document(video.id)
        let likeRef = videoRef.collection("likes").document(userId)
        
        Task {
            do {
                _ = try await firestore.runTransaction({ (transaction, errorPointer) -> Any? in
                    let videoDoc: DocumentSnapshot
                    do {
                        videoDoc = try transaction.getDocument(videoRef)
                    } catch let fetchError as NSError {
                        errorPointer?.pointee = fetchError
                        print("❌ VideoPlayer: Failed to fetch video document in like transaction: \(fetchError)")
                        return nil
                    }
                    
                    let currentLikes = videoDoc.data()?["likeCount"] as? Int ?? 0
                    
                    if self.isLiked {
                        // Unlike
                        transaction.deleteDocument(likeRef)
                        transaction.updateData(["likeCount": currentLikes - 1], forDocument: videoRef)
                        print("👎 VideoPlayer: Removed like")
                    } else {
                        // Like
                        transaction.setData([:], forDocument: likeRef)
                        transaction.updateData(["likeCount": currentLikes + 1], forDocument: videoRef)
                        print("👍 VideoPlayer: Added like")
                    }
                    
                    return nil
                })
                
                // Update UI
                isLiked.toggle()
            } catch {
                print("❌ VideoPlayer: Error toggling like: \(error.localizedDescription)")
            }
        }
    }
    
    func toggleSave() {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ VideoPlayer: No authenticated user")
            return
        }
        
        let videoRef = firestore.collection("videos").document(video.id)
        let saveRef = firestore
            .collection("users")
            .document(userId)
            .collection("savedVideos")
            .document(video.id)
        
        Task {
            do {
                _ = try await firestore.runTransaction({ (transaction, errorPointer) -> Any? in
                    let videoDoc: DocumentSnapshot
                    do {
                        videoDoc = try transaction.getDocument(videoRef)
                    } catch let fetchError as NSError {
                        errorPointer?.pointee = fetchError
                        print("❌ VideoPlayer: Failed to fetch video document in save transaction: \(fetchError)")
                        return nil
                    }
                    
                    let currentSaves = videoDoc.data()?["saveCount"] as? Int ?? 0
                    
                    if self.isSaved {
                        // Unsave
                        transaction.deleteDocument(saveRef)
                        transaction.updateData(["saveCount": currentSaves - 1], forDocument: videoRef)
                        print("🗑️ VideoPlayer: Removed from saved")
                    } else {
                        // Save
                        transaction.setData([:], forDocument: saveRef)
                        transaction.updateData(["saveCount": currentSaves + 1], forDocument: videoRef)
                        print("💾 VideoPlayer: Added to saved")
                    }
                    
                    return nil
                })
                
                // Update UI
                isSaved.toggle()
            } catch {
                print("❌ VideoPlayer: Error toggling save: \(error.localizedDescription)")
            }
        }
    }
    
    func saveToSecondBrain() async throws {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ VideoPlayer: No authenticated user")
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let videoRef = firestore.collection("videos").document(video.id)
        let secondBrainRef = firestore.collection("users").document(userId).collection("secondBrain").document(video.id)
        
        let _ = try await firestore.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                // Get the current video document
                let videoDoc = try transaction.getDocument(videoRef)
                guard let currentSaveCount = videoDoc.data()?["saveCount"] as? Int else {
                    errorPointer?.pointee = NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video data"])
                    return nil
                }
                
                // Calculate new hotScore based on saves and recency
                let createdAt = (videoDoc.data()?["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let ageInHours = Date().timeIntervalSince(createdAt) / 3600
                let recencyBonus = max(0, 100 - (ageInHours * 0.5)) // Decay of 0.5 points per hour, max 100 points
                let newHotScore = Double(currentSaveCount + 1) * 10.0 + recencyBonus
                
                print("🔥 VideoPlayer: Calculating hotScore - Saves: \(currentSaveCount + 1), Age: \(ageInHours)h, Recency Bonus: \(recencyBonus), New Score: \(newHotScore)")
                
                // Update video document
                transaction.updateData([
                    "saveCount": currentSaveCount + 1,
                    "hotScore": newHotScore
                ], forDocument: videoRef)
                
                // Add to user's second brain
                let secondBrainData: [String: Any] = [
                    "videoId": self.video.id,
                    "savedAt": Timestamp(date: Date()),
                    "videoURL": self.video.videoURL,
                    "thumbnailURL": self.video.thumbnailURL,
                    "title": self.video.title,
                    "description": self.video.description
                ]
                transaction.setData(secondBrainData, forDocument: secondBrainRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        
        print("✅ VideoPlayer: Successfully saved video to Second Brain")
        await MainActor.run {
            self.isSaved = true
            self.isInSecondBrain = true
        }
    }
    
    func removeFromSecondBrain() async throws {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ VideoPlayer: No authenticated user")
            throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let videoRef = firestore.collection("videos").document(video.id)
        let secondBrainRef = firestore.collection("users").document(userId).collection("secondBrain").document(video.id)
        
        let _ = try await firestore.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                // Get the current video document
                let videoDoc = try transaction.getDocument(videoRef)
                guard let currentSaveCount = videoDoc.data()?["saveCount"] as? Int else {
                    errorPointer?.pointee = NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video data"])
                    return nil
                }
                
                // Calculate new hotScore based on saves and recency
                let createdAt = (videoDoc.data()?["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let ageInHours = Date().timeIntervalSince(createdAt) / 3600
                let recencyBonus = max(0, 100 - (ageInHours * 0.5)) // Decay of 0.5 points per hour, max 100 points
                let newHotScore = max(0, Double(currentSaveCount - 1) * 10.0 + recencyBonus)
                
                print("🔥 VideoPlayer: Calculating hotScore - Saves: \(currentSaveCount - 1), Age: \(ageInHours)h, Recency Bonus: \(recencyBonus), New Score: \(newHotScore)")
                
                // Update video document
                transaction.updateData([
                    "saveCount": max(0, currentSaveCount - 1),
                    "hotScore": newHotScore
                ], forDocument: videoRef)
                
                // Remove from user's second brain
                transaction.deleteDocument(secondBrainRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        
        print("✅ VideoPlayer: Successfully removed video from Second Brain")
        await MainActor.run {
            self.isSaved = false
            self.isInSecondBrain = false
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
} 