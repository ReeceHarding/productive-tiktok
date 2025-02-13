import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @State private var hasInitializedFirstVideo = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVideo: Video?

    var body: some View {
        VideoFeedScrollView(
            videos: viewModel.videos,
            scrollPosition: $scrollPosition,
            hasInitializedFirstVideo: $hasInitializedFirstVideo
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
                LoggingService.debug("📱 VideoFeedView appeared, fetching videos", component: "Feed")
                await viewModel.fetchVideos()
                if let firstVideoId = viewModel.videos.first?.id {
                    LoggingService.debug("Setting initial scroll position to \(firstVideoId)", component: "Feed")
                    await MainActor.run {
                        scrollPosition = firstVideoId
                        hasInitializedFirstVideo = true
                    }
                }
            }
        }
        .onChange(of: scrollPosition as String?) { oldPosition, newPosition in
            // When scroll position changes, pause the old video and play the new one
            Task {
                LoggingService.debug("🔄 Scroll position changed - old: \(oldPosition ?? "nil"), new: \(newPosition ?? "nil")", component: "Feed")
                
                if let oldId = oldPosition {
                    LoggingService.debug("⏸️ Starting cleanup for old video \(oldId)", component: "Feed")
                    // First pause and cleanup old video
                    if let oldPlayer = viewModel.playerViewModels[oldId] {
                        LoggingService.debug("Found old player for \(oldId), pausing playback", component: "Feed")
                        await oldPlayer.pausePlayback()
                        LoggingService.debug("Starting cleanup for \(oldId)", component: "Feed")
                        await oldPlayer.cleanup()
                        LoggingService.debug("Cleanup complete for \(oldId)", component: "Feed")
                        // Additional delay to ensure audio system is fully reset
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        LoggingService.debug("Finished delay after cleanup for \(oldId)", component: "Feed")
                    } else {
                        LoggingService.debug("⚠️ No player found for old video \(oldId)", component: "Feed")
                    }
                }
                
                if let newId = newPosition {
                    LoggingService.debug("▶️ Starting playback for new video \(newId)", component: "Feed")
                    // Then play new video
                    if let newPlayer = viewModel.playerViewModels[newId] {
                        LoggingService.debug("Found new player for \(newId), starting playback", component: "Feed")
                        await newPlayer.play()
                        LoggingService.debug("Playback started for \(newId)", component: "Feed")
                    } else {
                        LoggingService.debug("⚠️ No player found for new video \(newId)", component: "Feed")
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
    @Binding var hasInitializedFirstVideo: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(videos) { video in
                    VideoPlayerView(video: video, shouldAutoPlay: .constant(hasInitializedFirstVideo))
                        .id(video.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .frame(height: UIScreen.main.bounds.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
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