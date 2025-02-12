import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore
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
        // Configure Firebase and Firestore logging to suppress internal logs
        FirebaseConfiguration.shared.setLoggerLevel(.error)
        Firestore.enableLogging(false)  // Disable Firestore debug logging
        setupCommentsListener()
    }
    
    // MARK: - Public Methods
    func refreshComments() async {
        lastDocument = nil
        comments = []
        await loadMoreComments()
    }
    
    func loadMoreComments() async {
        guard !isLoadingMore && hasMoreComments else { return }
        
        isLoadingMore = true
        
        do {
            var query = firestore
                .collection("videos")
                .document(video.id)
                .collection("comments")
                .order(by: "saveCount", descending: true)
                .limit(to: pageSize)
            
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                hasMoreComments = false
                isLoadingMore = false
                return
            }
            
            lastDocument = snapshot.documents.last
            
            let newComments: [Comment] = snapshot.documents.compactMap { document in
                guard let comment = Comment(document: document) else {
                    LoggingService.error("Failed to parse comment from doc: \(document.documentID)", component: "Comments")
                    return nil
                }
                return comment
            }
            
            let sortedComments = newComments.sorted { comment1, comment2 in
                let ratio1 = Double(comment1.saveCount) / Double(max(comment1.viewCount, 1))
                let ratio2 = Double(comment2.saveCount) / Double(max(comment2.viewCount, 1))
                return ratio1 > ratio2
            }
            
            comments.append(contentsOf: sortedComments)
            
        } catch {
            LoggingService.error("Error loading more comments: \(error.localizedDescription)", component: "Comments")
            self.error = "Failed to load more comments: \(error.localizedDescription)"
        }
        
        isLoadingMore = false
    }
    
    func addComment(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            self.error = "Please sign in to comment"
            return
        }
        
        let commentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create optimistic comment
        let optimisticComment = Comment(
            videoId: video.id,
            userId: userId,
            text: commentText,
            userName: Auth.auth().currentUser?.displayName
        )
        
        comments.insert(optimisticComment, at: 0)
        
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
            
        } catch {
            LoggingService.error("Error adding comment: \(error.localizedDescription)", component: "Comments")
            // Remove optimistic comment on error
            if let index = comments.firstIndex(where: { $0.id == optimisticComment.id }) {
                comments.remove(at: index)
            }
            self.error = "Failed to add comment: \(error.localizedDescription)"
        }
    }
    
    func toggleSecondBrain(for comment: Comment) async {
        guard Auth.auth().currentUser != nil else {
            self.error = "Please sign in to add to Second Brain"
            return
        }
        
        let commentRef = firestore
            .collection("videos")
            .document(video.id)
            .collection("comments")
            .document(comment.id)
        
        do {
            // Optimistically update UI
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].isInSecondBrain.toggle()
                comments[index].saveCount += comments[index].isInSecondBrain ? 1 : -1
            }
            
            let _ = try await firestore.runTransaction({ (transaction, errorPointer) -> Any? in
                let commentDoc: DocumentSnapshot
                do {
                    commentDoc = try transaction.getDocument(commentRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                var currentData = commentDoc.data() ?? [:]
                let newSecondBrainStatus = !(currentData["isInSecondBrain"] as? Bool ?? false)
                currentData["isInSecondBrain"] = newSecondBrainStatus
                
                let currentSaveCount = currentData["saveCount"] as? Int ?? 0
                currentData["saveCount"] = currentSaveCount + (newSecondBrainStatus ? 1 : -1)
                
                transaction.setData(currentData, forDocument: commentRef)
                return nil
            })
            
            // Re-sort comments after updating save count
            comments.sort { comment1, comment2 in
                let ratio1 = Double(comment1.saveCount) / Double(max(comment1.viewCount, 1))
                let ratio2 = Double(comment2.saveCount) / Double(max(comment2.viewCount, 1))
                return ratio1 > ratio2
            }
            
        } catch {
            LoggingService.error("Error toggling Second Brain status: \(error.localizedDescription)", component: "Comments")
            // Revert optimistic update on error
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].isInSecondBrain.toggle()
                comments[index].saveCount -= comments[index].isInSecondBrain ? 1 : -1
            }
            self.error = "Failed to update Second Brain status: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func setupCommentsListener() {
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
                    LoggingService.error("Error listening for comments: \(error.localizedDescription)", component: "Comments")
                    self.error = "Failed to load comments: \(error.localizedDescription)"
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                // Process new or modified documents only
                let changedDocs = snapshot?.documentChanges.filter { $0.type == .added || $0.type == .modified } ?? []
                
                // Silently increment view count for new or modified documents
                for change in changedDocs {
                    Task {
                        try? await self.firestore
                            .collection("videos")
                            .document(self.video.id)
                            .collection("comments")
                            .document(change.document.documentID)
                            .updateData([
                                "viewCount": FieldValue.increment(Int64(1)) as Any
                            ])
                    }
                }
                
                let updatedComments = documents.compactMap { document -> Comment? in
                    guard let comment = Comment(document: document) else {
                        LoggingService.error("Failed to parse comment from doc: \(document.documentID)", component: "Comments")
                        return nil
                    }
                    return comment
                }
                
                // Sort by save:view ratio
                let sortedComments = updatedComments.sorted { c1, c2 in
                    let ratio1 = Double(c1.saveCount) / Double(max(c1.viewCount, 1))
                    let ratio2 = Double(c2.saveCount) / Double(max(c2.viewCount, 1))
                    return ratio1 > ratio2
                }
                
                self.comments = sortedComments
                self.isLoading = false
            }
    }
    
    deinit {
        listenerRegistration?.remove()
    }
}