import SwiftUI
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView("Loading videos...")
                        .foregroundColor(.white)
                } else if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.white)
                } else if viewModel.videos.isEmpty {
                    Text("No videos available")
                        .foregroundColor(.white)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                            VideoPlayerView(video: video)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .tag(index)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: currentIndex) { oldValue, newValue in
                        // Preload next video
                        if newValue < viewModel.videos.count - 1 {
                            viewModel.preloadVideo(at: newValue + 1)
                        }
                        // Load more videos if we're near the end
                        if newValue >= viewModel.videos.count - 2 {
                            Task {
                                await viewModel.fetchNextBatch()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.fetchVideos()
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 