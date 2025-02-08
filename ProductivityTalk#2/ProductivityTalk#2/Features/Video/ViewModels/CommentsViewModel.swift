import Foundation
import FirebaseFirestore
import Combine

@MainActor
class CommentsViewModel: ObservableObject {
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let video: Video
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    init(video: Video) {
        self.video = video
        print("🎥 CommentsViewModel: Initialized for video ID: \(video.id)")
    }
    
    func loadComments() async {
        isLoading = true
        print("📥 CommentsViewModel: Starting to load comments for video ID: \(video.id)")
        
        do {
            let snapshot = try await db.collection("comments")
                .whereField("videoId", isEqualTo: video.id)
                .order(by: "secondBrainCount", descending: true)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            print("📊 CommentsViewModel: Retrieved \(snapshot.documents.count) comments")
            
            self.comments = snapshot.documents.compactMap { document in
                guard let comment = Comment(document: document) else {
                    print("❌ CommentsViewModel: Failed to parse comment document: \(document.documentID)")
                    return nil
                }
                return comment
            }
            
            print("✅ CommentsViewModel: Successfully loaded \(self.comments.count) comments")
        } catch {
            print("❌ CommentsViewModel: Error loading comments: \(error.localizedDescription)")
            self.error = "Failed to load comments: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func toggleSecondBrain(for comment: Comment) async {
        print("🧠 CommentsViewModel: Toggling second brain for comment ID: \(comment.id)")
        
        do {
            let commentRef = db.collection("comments").document(comment.id)
            let result = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                do {
                    let snapshot = try transaction.getDocument(commentRef)
                    guard let currentCount = snapshot.data()?["secondBrainCount"] as? Int else {
                        let error = NSError(
                            domain: "AppErrorDomain",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to get current second brain count"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    let newCount = currentCount + 1
                    transaction.updateData(["secondBrainCount": newCount], forDocument: commentRef)
                    
                    print("✅ CommentsViewModel: Updated second brain count to \(newCount) for comment ID: \(comment.id)")
                    return newCount
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            })
            
            if result != nil {
                // Reload comments to reflect the new order
                await loadComments()
            }
        } catch {
            print("❌ CommentsViewModel: Error toggling second brain: \(error.localizedDescription)")
            self.error = "Failed to update second brain count: \(error.localizedDescription)"
        }
    }
    
    func addComment(text: String) async {
        guard let currentUser = try? await db.collection("users").document(UserDefaults.standard.string(forKey: "userId") ?? "").getDocument(),
              let username = currentUser.data()?["username"] as? String else {
            print("❌ CommentsViewModel: Failed to get current user info")
            self.error = "Failed to add comment: Could not get user information"
            return
        }
        
        print("📝 CommentsViewModel: Adding new comment for video ID: \(video.id)")
        
        let newComment = Comment(
            id: UUID().uuidString,
            videoId: video.id,
            userId: currentUser.documentID,
            text: text,
            userUsername: username,
            userProfilePicURL: currentUser.data()?["profilePicURL"] as? String
        )
        
        do {
            try await db.collection("comments").document(newComment.id).setData(newComment.toFirestoreData())
            print("✅ CommentsViewModel: Successfully added new comment with ID: \(newComment.id)")
            
            // Reload comments to include the new one
            await loadComments()
        } catch {
            print("❌ CommentsViewModel: Error adding comment: \(error.localizedDescription)")
            self.error = "Failed to add comment: \(error.localizedDescription)"
        }
    }
} 