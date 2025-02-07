import Foundation
import FirebaseFirestore

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    
    private let firestore = Firestore.firestore()
    
    func fetchVideos() async {
        print("📱 VideoFeed: Fetching videos")
        print("🔍 VideoFeed: Query parameters - status: ready, limit: 10, ordered by: createdAt desc")
        isLoading = true
        error = nil
        
        do {
            let query = firestore.collection("videos")
                .whereField("processingStatus", isEqualTo: VideoProcessingStatus.ready.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
            
            print("🔍 VideoFeed: Executing query: \(query)")
            
            let snapshot = try await query.getDocuments()
            
            print("📊 VideoFeed: Query results - total documents: \(snapshot.documents.count)")
            
            if snapshot.documents.isEmpty {
                print("ℹ️ VideoFeed: No videos found with status 'ready'")
            }
            
            self.videos = snapshot.documents.compactMap { document in
                if let video = Video(document: document) {
                    print("✅ VideoFeed: Successfully parsed video: \(document.documentID)")
                    return video
                } else {
                    print("❌ VideoFeed: Failed to parse video document: \(document.documentID)")
                    print("📄 VideoFeed: Document data: \(document.data())")
                    return nil
                }
            }
            
            print("✅ VideoFeed: Successfully fetched \(videos.count) videos")
            
        } catch {
            print("❌ VideoFeed: Error fetching videos: \(error.localizedDescription)")
            print("🔍 VideoFeed: Detailed error: \(error)")
            self.error = error
        }
        
        isLoading = false
    }
} 