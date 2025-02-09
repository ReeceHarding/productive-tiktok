import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.videos) { video in
                    VideoPlayerView(video: video)
                        .id(video.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .background(.black)
        .overlay {
            if viewModel.isLoading {
                LoadingAnimation(message: "Loading videos...")
                    .foregroundColor(.white)
            } else if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.white)
            } else if viewModel.videos.isEmpty {
                Text("No videos available")
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            Task {
                await viewModel.fetchVideos()
                if let firstVideoId = viewModel.videos.first?.id {
                    await MainActor.run {
                        scrollPosition = firstVideoId
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if let videoId = scrollPosition {
                    Task {
                        await viewModel.playerViewModels[videoId]?.play()
                    }
                }
            case .inactive, .background:
                if let videoId = scrollPosition {
                    Task {
                        await viewModel.playerViewModels[videoId]?.pausePlayback()
                    }
                }
            @unknown default:
                break
            }
        }
    }
}

// MARK: - TabBarButton
private struct TabBarButton: View {
    let icon: String
    let text: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 24))
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(isSelected ? .blue : .gray)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VideoFeedView()
} 