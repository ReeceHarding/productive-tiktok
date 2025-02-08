import Foundation
import AVKit
import FirebaseFirestore

@MainActor
class VideoPlayerViewModel: ObservableObject {
    private let video: Video
    @Published var player: AVPlayer?
    @Published private(set) var isLiked = false
    @Published private(set) var isSaved = false
    
    private let firestore = Firestore.firestore()
    
    init(video: Video) {
        self.video = video
        print("📱 VideoPlayer: Initialized for video ID: \(video.id)")
    }
    
    func setupPlayer() {
        guard let url = URL(string: video.videoURL) else {
            print("❌ VideoPlayer: Invalid video URL")
            return
        }
        
        print("🎬 VideoPlayer: Setting up player for URL: \(url)")
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        
        // Start playing
        player.play()
    }
    
    func cleanup() {
        print("🧹 VideoPlayer: Cleaning up resources")
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
} 