import SwiftUI
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                    VideoPlayerView(video: video)
                        .rotationEffect(.degrees(0)) // Fixes TabView rotation bug
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            // Top Navigation
            HStack(spacing: 20) {
                Text("For You")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .task {
            if viewModel.videos.isEmpty {
                await viewModel.fetchVideos()
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 