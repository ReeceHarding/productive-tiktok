import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class CommentsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var comments: [Comment] = []
    @Published var newCommentText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published private(set) var hasMoreComments = true
    @Published private(set) var isLoadingMore = false
    
    // MARK: - Private Properties
    private let video: Video
    private let firestore = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private let pageSize = 20
    private var lastDocument: DocumentSnapshot?
    
    // MARK: - Initialization
    init(video: Video) {
        self.video = video
        LoggingService.debug("📱 CommentsViewModel: Initialized for video ID: \(video.id)", component: "Comments")
        setupCommentsListener()
    }
    
    // MARK: - Public Methods
    func refreshComments() async {
        LoggingService.debug("🔄 CommentsViewModel: Refreshing comments", component: "Comments")
        lastDocument = nil
        comments = []
        await loadMoreComments()
    }
    
    func loadMoreComments() async {
        guard !isLoadingMore && hasMoreComments else { return }
        
        isLoadingMore = true
        LoggingService.debug("📥 CommentsViewModel: Loading more comments", component: "Comments")
        
        do {
            var query = firestore
                .collection("videos")
                .document(video.id)
                .collection("comments")
                .order(by: "saveCount", descending: true) // Sort by saves first
                .limit(to: pageSize)
            
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                LoggingService.debug("📭 CommentsViewModel: No more comments to load", component: "Comments")
                hasMoreComments = false
                isLoadingMore = false
                return
            }
            
            lastDocument = snapshot.documents.last
            
            let newComments: [Comment] = snapshot.documents.compactMap { document in
                guard let comment = Comment(document: document) else {
                    LoggingService.error("⚠️ CommentsViewModel: Failed to parse comment from document: \(document.documentID)", component: "Comments")
                    return nil
                }
                return comment
            }
            
            // Sort by save:view ratio
            let sortedComments = newComments.sorted { comment1, comment2 in
                let ratio1 = Double(comment1.saveCount) / Double(max(comment1.viewCount, 1))
                let ratio2 = Double(comment2.saveCount) / Double(max(comment2.viewCount, 1))
                return ratio1 > ratio2
            }
            
            LoggingService.debug("✅ CommentsViewModel: Loaded \(sortedComments.count) more comments", component: "Comments")
            comments.append(contentsOf: sortedComments)
            
        } catch {
            LoggingService.error("❌ CommentsViewModel: Error loading more comments: \(error.localizedDescription)", component: "Comments")
            self.error = "Failed to load more comments: \(error.localizedDescription)"
        }
        
        isLoadingMore = false
    }
    
    func addComment() async {
        guard !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LoggingService.warning("⚠️ CommentsViewModel: Attempted to add empty comment", component: "Comments")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("❌ CommentsViewModel: No authenticated user", component: "Comments")
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
        LoggingService.debug("🔄 CommentsViewModel: Adding optimistic comment to UI", component: "Comments")
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
            
            LoggingService.debug("💾 CommentsViewModel: Saving comment to Firestore", component: "Comments")
            
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
            
            LoggingService.success("✅ CommentsViewModel: Successfully added comment", component: "Comments")
            
        } catch {
            LoggingService.error("❌ CommentsViewModel: Error adding comment: \(error.localizedDescription)", component: "Comments")
            
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
                // Update save count optimistically
                comments[index].saveCount += comments[index].isInSecondBrain ? 1 : -1
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
                
                // Update save count
                let currentSaveCount = currentData["saveCount"] as? Int ?? 0
                currentData["saveCount"] = currentSaveCount + (newSecondBrainStatus ? 1 : -1)
                
                transaction.setData(currentData, forDocument: commentRef)
                LoggingService.success("✅ Second Brain: Successfully toggled status to \(newSecondBrainStatus)", component: "Comments")
                return nil
            })
            
            // Re-sort comments after updating save count
            comments.sort { comment1, comment2 in
                let ratio1 = Double(comment1.saveCount) / Double(max(comment1.viewCount, 1))
                let ratio2 = Double(comment2.saveCount) / Double(max(comment2.viewCount, 1))
                return ratio1 > ratio2
            }
            
        } catch {
            LoggingService.error("❌ Second Brain: Error toggling status: \(error.localizedDescription)", component: "Comments")
            
            // Revert optimistic update on error
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].isInSecondBrain.toggle()
                comments[index].saveCount -= comments[index].isInSecondBrain ? 1 : -1
                LoggingService.debug("↩️ Second Brain: Reverted UI update due to error", component: "Comments")
            }
            
            self.error = "Failed to update Second Brain status: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func setupCommentsListener() {
        LoggingService.debug("🎧 CommentsViewModel: Setting up real-time comments listener", component: "Comments")
        isLoading = true
        
        listenerRegistration = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .order(by: "saveCount", descending: true)
            .limit(to: pageSize)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    LoggingService.error("❌ CommentsViewModel: Error listening for comments: \(error.localizedDescription)", component: "Comments")
                    self.error = "Failed to load comments: \(error.localizedDescription)"
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    LoggingService.warning("⚠️ CommentsViewModel: No documents in snapshot", component: "Comments")
                    return
                }
                
                let updatedComments = documents.compactMap { document -> Comment? in
                    guard let comment = Comment(document: document) else {
                        LoggingService.error("Failed to parse comment from document: \(document.documentID)", component: "Comments")
                        return nil
                    }
                    
                    // Increment view count
                    Task {
                        do {
                            try await self.firestore
                                .collection("videos")
                                .document(self.video.id)
                                .collection("comments")
                                .document(comment.id)
                                .updateData([
                                    "viewCount": FieldValue.increment(Int64(1))
                                ])
                            LoggingService.debug("✅ Incremented view count for comment: \(comment.id)", component: "Comments")
                        } catch {
                            LoggingService.error("Failed to increment view count: \(error.localizedDescription)", component: "Comments")
                        }
                    }
                    
                    return comment
                }
                
                // Sort by save:view ratio
                let sortedComments = updatedComments.sorted { comment1, comment2 in
                    let ratio1 = Double(comment1.saveCount) / Double(max(comment1.viewCount, 1))
                    let ratio2 = Double(comment2.saveCount) / Double(max(comment2.viewCount, 1))
                    return ratio1 > ratio2
                }
                
                self.comments = sortedComments
                self.isLoading = false
                LoggingService.debug("✅ CommentsViewModel: Updated comments list with \(sortedComments.count) comments", component: "Comments")
            }
    }
    
    deinit {
        LoggingService.debug("🧹 CommentsViewModel: Cleaning up", component: "Comments")
        listenerRegistration?.remove()
    }
} 