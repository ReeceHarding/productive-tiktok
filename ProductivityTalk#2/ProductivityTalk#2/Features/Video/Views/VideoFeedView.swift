import SwiftUI
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.videos) { video in
                        VideoPlayerView(video: video)
                            .frame(height: UIScreen.main.bounds.height)
                    }
                }
            }
            .refreshable {
                await viewModel.fetchVideos()
            }
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.videos.isEmpty {
                    await viewModel.fetchVideos()
                }
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 