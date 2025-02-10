import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSchedulingView = false
    @State private var selectedVideo: Video?
    
    var body: some View {
        VideoFeedScrollView(
            videos: viewModel.videos,
            scrollPosition: $scrollPosition,
            selectedVideo: $selectedVideo,
            showingSchedulingView: $showingSchedulingView
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
        .sheet(isPresented: $showingSchedulingView) {
            if let video = selectedVideo,
               let transcript = video.transcript {
                SchedulingView(
                    transcript: transcript,
                    videoTitle: video.title
                )
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
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

// MARK: - VideoFeedScrollView
private struct VideoFeedScrollView: View {
    let videos: [Video]
    @Binding var scrollPosition: String?
    @Binding var selectedVideo: Video?
    @Binding var showingSchedulingView: Bool
    
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