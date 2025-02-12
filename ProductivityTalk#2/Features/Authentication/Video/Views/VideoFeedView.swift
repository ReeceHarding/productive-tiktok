import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVideo: Video?
    @State private var isRefreshing = false
    
    var body: some View {
        VideoFeedScrollView(
            videos: viewModel.videos,
            scrollPosition: $scrollPosition,
            onRefresh: {
                isRefreshing = true
                Task {
                    await viewModel.fetchVideos()
                    isRefreshing = false
                }
            },
            isRefreshing: isRefreshing
        )
        .background(.black)
        .overlay {
            VideoFeedOverlay(
                isLoading: viewModel.isLoading,
                error: viewModel.error,
                videos: viewModel.videos
            )
        }
        .task {
            // Load videos immediately on appear
            await viewModel.fetchVideos()
            if let firstVideoId = viewModel.videos.first?.id {
                scrollPosition = firstVideoId
                // Preload the first few videos
                for i in 0..<min(3, viewModel.videos.count) {
                    await viewModel.preloadVideo(at: i)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: scrollPosition) { _, newPosition in
            handleScrollPositionChange(newPosition)
        }
    }
    
    private func handleScrollPositionChange(_ newPosition: String?) {
        guard let newPosition = newPosition,
              let currentIndex = viewModel.videos.firstIndex(where: { video in video.id == newPosition }) else {
            return
        }
        
        Task {
            // Pause all other videos
            await viewModel.pauseAllExcept(videoId: newPosition)
            
            // Preload adjacent videos
            await viewModel.preloadAdjacentVideos(currentIndex: currentIndex)
            
            // Load more videos if we're near the end
            if currentIndex >= viewModel.videos.count - 2 {
                await viewModel.fetchNextBatch()
            }
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
    let onRefresh: () async -> Void
    let isRefreshing: Bool
    
    var body: some View {
        ScrollView {
            RefreshableScrollContent(
                isRefreshing: isRefreshing,
                onRefresh: onRefresh
            )
            
            LazyVStack(spacing: 0) {
                ForEach(videos) { video in
                    VideoPlayerView(video: video)
                        .id(video.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .frame(height: UIScreen.main.bounds.height)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollTargetBehavior(.paging)
        .scrollDisabled(isRefreshing)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }
}

// MARK: - RefreshableScrollContent
private struct RefreshableScrollContent: View {
    let isRefreshing: Bool
    let onRefresh: () async -> Void
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.frame(in: .global).minY > 50 {
                Spacer()
                    .frame(height: 0)
                    .onAppear {
                        Task {
                            await onRefresh()
                        }
                    }
            }
            
            if isRefreshing {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .frame(height: 50)
            }
        }
        .frame(height: 0)
    }
}

// MARK: - VideoFeedOverlay
private struct VideoFeedOverlay: View {
    let isLoading: Bool
    let error: Error?
    let videos: [Video]
    
    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                LoadingAnimation(message: "Loading your feed...")
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(error.localizedDescription)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding()
            } else if videos.isEmpty {
                VStack {
                    Image(systemName: "video.slash.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No videos available")
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding()
            }
        }
    }
}

#Preview {
    VideoFeedView()
}