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
        isLoading = true
        error = nil
        
        do {
            let snapshot = try await firestore.collection("videos")
                .whereField("processingStatus", isEqualTo: VideoProcessingStatus.ready.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            
            print("✅ VideoFeed: Successfully fetched \(snapshot.documents.count) videos")
            
            self.videos = snapshot.documents.compactMap { document in
                if let video = Video(document: document) {
                    return video
                } else {
                    print("❌ VideoFeed: Failed to parse video document: \(document.documentID)")
                    return nil
                }
            }
        } catch {
            print("❌ VideoFeed: Error fetching videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
} 