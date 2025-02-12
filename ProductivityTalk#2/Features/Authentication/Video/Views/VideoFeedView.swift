import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVideo: Video?

    var body: some View {
        VideoFeedScrollView(
            videos: viewModel.videos,
            scrollPosition: $scrollPosition
        )
        .background(.black)
        .overlay {
            VideoFeedOverlay(
                isLoading: viewModel.isLoading,
                error: viewModel.error,
                videos: viewModel.videos
            )
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
            handleScenePhaseChange(newPhase)
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if let videoId = scrollPosition {
                Task {
                    do {
                        try await viewModel.playerViewModels[videoId]?.play()
                    } catch {
                        LoggingService.error("Failed to play video on scene active: \(error)", component: "Feed")
                    }
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

// MARK: - VideoFeedScrollView
private struct VideoFeedScrollView: View {
    let videos: [Video]
    @Binding var scrollPosition: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(videos) { video in
                    VideoPlayerView(video: video)
                        .id(video.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .frame(height: UIScreen.main.bounds.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }
}

// MARK: - VideoFeedOverlay
private struct VideoFeedOverlay: View {
    let isLoading: Bool
    let error: Error?
    let videos: [Video]
    
    var body: some View {
        Group {
            if isLoading {
                // Replace system spinner with LoadingAnimation
                LoadingAnimation(message: "Loading videos...")
                    .foregroundColor(.white)
            } else if let error = error {
                Text(error.localizedDescription)
                    .foregroundColor(.white)
            } else if videos.isEmpty {
                Text("No videos available")
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    VideoFeedView()
}