import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var newCommentText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let video: Video
    private let firestore = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    init(video: Video) {
        self.video = video
        print("📱 CommentsViewModel: Initialized for video ID: \(video.id)")
        setupCommentsListener()
    }
    
    private func setupCommentsListener() {
        print("🎧 CommentsViewModel: Setting up real-time comments listener")
        
        listenerRegistration = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ CommentsViewModel: Error listening for comments: \(error.localizedDescription)")
                    self.error = "Failed to load comments: \(error.localizedDescription)"
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("❌ CommentsViewModel: No documents in snapshot")
                    return
                }
                
                print("📥 CommentsViewModel: Received \(documents.count) comments")
                
                self.comments = documents.compactMap { document in
                    guard let comment = Comment(document: document) else {
                        print("⚠️ CommentsViewModel: Failed to parse comment from document: \(document.documentID)")
                        return nil
                    }
                    return comment
                }
            }
    }
    
    func addComment() async {
        guard !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ CommentsViewModel: Attempted to add empty comment")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ CommentsViewModel: No authenticated user")
            self.error = "Please sign in to comment"
            return
        }
        
        let commentText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create optimistic comment
        let optimisticComment = Comment(
            videoId: video.id,
            userId: userId,
            text: commentText,
            userName: Auth.auth().currentUser?.displayName
        )
        
        // Add optimistic comment to UI
        print("🔄 CommentsViewModel: Adding optimistic comment to UI")
        comments.insert(optimisticComment, at: 0)
        newCommentText = ""
        
        do {
            // Get user data for the comment
            let userDoc = try await firestore.collection("users").document(userId).getDocument()
            let userData = userDoc.data()
            let userName = userData?["username"] as? String ?? Auth.auth().currentUser?.displayName
            let userProfileImageURL = userData?["profileImageURL"] as? String
            
            // Create the actual comment
            let comment = Comment(
                videoId: video.id,
                userId: userId,
                text: commentText,
                userName: userName,
                userProfileImageURL: userProfileImageURL
            )
            
            print("💾 CommentsViewModel: Saving comment to Firestore")
            
            // Save to Firestore
            try await firestore
                .collection("videos")
                .document(video.id)
                .collection("comments")
                .document(comment.id)
                .setData(comment.toFirestore)
            
            // Update video's comment count
            let _ = try await firestore.runTransaction({ (transaction, errorPointer) -> Any? in
                let videoRef = self.firestore.collection("videos").document(self.video.id)
                let videoDoc: DocumentSnapshot
                do {
                    videoDoc = try transaction.getDocument(videoRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                let currentCount = videoDoc.data()?["commentCount"] as? Int ?? 0
                transaction.updateData(["commentCount": currentCount + 1], forDocument: videoRef)
                return nil
            })
            
            print("✅ CommentsViewModel: Successfully added comment")
            
        } catch {
            print("❌ CommentsViewModel: Error adding comment: \(error.localizedDescription)")
            
            // Remove optimistic comment on error
            if let index = comments.firstIndex(where: { $0.id == optimisticComment.id }) {
                comments.remove(at: index)
            }
            
            self.error = "Failed to add comment: \(error.localizedDescription)"
        }
    }
    
    func toggleSecondBrain(for comment: Comment) async {
        guard Auth.auth().currentUser != nil else {
            LoggingService.error("❌ Second Brain: No authenticated user", component: "Comments")
            self.error = "Please sign in to add to Second Brain"
            return
        }
        
        LoggingService.debug("🎬 Second Brain: Starting toggle process for comment ID: \(comment.id)", component: "Comments")
        LoggingService.debug("📝 Second Brain: Comment content:", component: "Comments")
        LoggingService.debug("   - Text: \(comment.text)", component: "Comments")
        LoggingService.debug("   - Author: \(comment.userId)", component: "Comments")
        LoggingService.debug("   - Current Second Brain status: \(comment.isInSecondBrain)", component: "Comments")
        
        let commentRef = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .document(comment.id)
        
        do {
            // Optimistically update UI
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].isInSecondBrain.toggle()
                LoggingService.debug("✅ Second Brain: Optimistically updated UI", component: "Comments")
            }
            
            let _ = try await firestore.runTransaction({ (transaction, errorPointer) -> Any? in
                let commentDoc: DocumentSnapshot
                do {
                    commentDoc = try transaction.getDocument(commentRef)
                    LoggingService.debug("✅ Second Brain: Retrieved comment document", component: "Comments")
                } catch let fetchError as NSError {
                    LoggingService.error("❌ Second Brain: Failed to fetch comment document: \(fetchError.localizedDescription)", component: "Comments")
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                var currentData = commentDoc.data() ?? [:]
                let newSecondBrainStatus = !(currentData["isInSecondBrain"] as? Bool ?? false)
                currentData["isInSecondBrain"] = newSecondBrainStatus
                
                transaction.setData(currentData, forDocument: commentRef)
                LoggingService.success("✅ Second Brain: Successfully toggled status to \(newSecondBrainStatus)", component: "Comments")
                return nil
            })
            
        } catch {
            LoggingService.error("❌ Second Brain: Error toggling status: \(error.localizedDescription)", component: "Comments")
            
            // Revert optimistic update on error
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].isInSecondBrain.toggle()
                LoggingService.debug("↩️ Second Brain: Reverted UI update due to error", component: "Comments")
            }
            
            self.error = "Failed to update Second Brain status: \(error.localizedDescription)"
        }
    }
    
    deinit {
        print("🧹 CommentsViewModel: Cleaning up")
        listenerRegistration?.remove()
    }
} 