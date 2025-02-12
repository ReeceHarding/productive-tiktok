import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore
import Combine

@MainActor
class CommentsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var comments: [Comment] = []
    @Published var newCommentText: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var hasMoreComments = true
    
    // MARK: - Private Properties
    private let video: Video
    private let firestore = Firestore.firestore()
    private let batchSize = 20
    private var lastDocument: DocumentSnapshot?
    private var isFetching = false
    private var commentCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 100 // Limit cache to 100 video comment lists
        return cache
    }()
    
    // MARK: - Initialization
    init(video: Video) {
        self.video = video
        Task {
            await fetchInitialComments()
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch initial batch of comments with caching
    func fetchInitialComments() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        
        // Check cache first
        if let cached = commentCache.object(forKey: video.id as NSString) as? [Comment] {
            LoggingService.debug("Using cached comments for video \(video.id)", component: "Comments")
            comments = cached
            isLoading = false
            return
        }
        
        do {
            let query = firestore
                .collection("videos")
                .document(video.id)
                .collection("comments")
                .order(by: "timestamp", descending: true)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            
            var loadedComments: [Comment] = []
            for doc in snapshot.documents {
                if let parsed = Comment(document: doc) {
                    loadedComments.append(parsed)
                }
            }
            
            comments = loadedComments
            lastDocument = snapshot.documents.last
            hasMoreComments = !snapshot.documents.isEmpty && snapshot.documents.count == batchSize
            
            // Cache the results
            commentCache.setObject(loadedComments as NSArray, forKey: video.id as NSString)
            
        } catch {
            self.error = "Failed to load comments: \(error.localizedDescription)"
            LoggingService.error("Failed to load comments for video \(video.id): \(error)", component: "Comments")
        }
        isLoading = false
    }
    
    /// Fetch next batch of comments
    func fetchMoreComments() async {
        guard !isFetching,
              hasMoreComments,
              let lastDoc = lastDocument else { return }
        
        isFetching = true
        
        do {
            let query = firestore
                .collection("videos")
                .document(video.id)
                .collection("comments")
                .order(by: "timestamp", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            
            var newComments: [Comment] = []
            for doc in snapshot.documents {
                if let parsed = Comment(document: doc) {
                    newComments.append(parsed)
                }
            }
            
            comments.append(contentsOf: newComments)
            lastDocument = snapshot.documents.last
            hasMoreComments = !snapshot.documents.isEmpty && snapshot.documents.count == batchSize
            
        } catch {
            self.error = "Failed to load more comments: \(error.localizedDescription)"
            LoggingService.error("Failed to load more comments for video \(video.id): \(error)", component: "Comments")
        }
        
        isFetching = false
    }
    
    /// Add a new comment under this video
    func addComment() async {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let userId = Auth.auth().currentUser?.uid else {
            self.error = "Please sign in to comment"
            return
        }
        
        isLoading = true
        error = nil
        
        let commentId = UUID().uuidString
        let commentDoc = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .document(commentId)
        
        let timestamp = Date()
        let userName = Auth.auth().currentUser?.displayName ?? "Anonymous"
        let newComment = Comment(
            id: commentId,
            videoId: video.id,
            userId: userId,
            text: trimmed,
            timestamp: timestamp,
            userName: userName
        )
        
        // Optimistically append
        comments.insert(newComment, at: 0)
        newCommentText = ""
        
        do {
            // Use a transaction to ensure atomicity
            try await firestore.runTransaction { transaction, errorPointer in
                // Update comment document
                transaction.setData(newComment.toFirestore, forDocument: commentDoc)
                
                // Update video comment count
                let videoRef = self.firestore.collection("videos").document(self.video.id)
                transaction.updateData([
                    "commentCount": FieldValue.increment(Int64(1))
                ], forDocument: videoRef)
                
                return nil
            }
            
            // Update cache
            commentCache.setObject(comments as NSArray, forKey: video.id as NSString)
            
        } catch {
            // Revert if error
            if let index = comments.firstIndex(where: { $0.id == commentId }) {
                comments.remove(at: index)
            }
            self.error = "Failed to add comment: \(error.localizedDescription)"
            LoggingService.error("Failed to add comment for video \(video.id): \(error)", component: "Comments")
        }
        
        isLoading = false
    }
    
    /// Toggle second brain status for a comment
    func toggleSecondBrain(for comment: Comment) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.error = "Please sign in to use Second Brain"
            return
        }
        
        guard let idx = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let wasInBrain = comments[idx].isInSecondBrain
        let oldSaveCount = comments[idx].saveCount
        
        // Optimistically update
        comments[idx].isInSecondBrain.toggle()
        comments[idx].saveCount = wasInBrain ? (oldSaveCount - 1) : (oldSaveCount + 1)
        
        let commentRef = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .document(comment.id)
        
        let userBrainRef = firestore
            .collection("users")
            .document(userId)
            .collection("secondBrain")
            .document(comment.id)
        
        do {
            // Use a transaction for atomicity
            try await firestore.runTransaction { transaction, errorPointer in
                if self.comments[idx].isInSecondBrain {
                    // Add to second brain
                    let updatedCount = oldSaveCount + 1
                    transaction.updateData([
                        "isInSecondBrain": true,
                        "saveCount": updatedCount
                    ], forDocument: commentRef)
                    
                    let secondBrainData: [String: Any] = [
                        "userId": userId,
                        "videoId": self.video.id,
                        "commentId": comment.id,
                        "text": comment.text,
                        "savedAt": FieldValue.serverTimestamp(),
                        "videoTitle": self.video.title,
                        "category": self.video.tags.first ?? "Uncategorized",
                        "type": "comment"
                    ]
                    transaction.setData(secondBrainData, forDocument: userBrainRef)
                } else {
                    // Remove from second brain
                    let updatedCount = oldSaveCount - 1
                    transaction.updateData([
                        "isInSecondBrain": false,
                        "saveCount": max(0, updatedCount)
                    ], forDocument: commentRef)
                    
                    transaction.deleteDocument(userBrainRef)
                }
                
                return nil
            }
            
            // Update cache
            commentCache.setObject(comments as NSArray, forKey: video.id as NSString)
            
        } catch {
            // Revert if error
            comments[idx].isInSecondBrain = wasInBrain
            comments[idx].saveCount = oldSaveCount
            self.error = "Failed to toggle second brain status: \(error.localizedDescription)"
            LoggingService.error("Failed to toggle second brain for comment \(comment.id): \(error)", component: "Comments")
        }
    }
    
    // MARK: - Error Handling
    func clearError() {
        error = nil
    }
}