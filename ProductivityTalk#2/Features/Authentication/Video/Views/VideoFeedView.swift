import SwiftUI
import AVKit
@_implementationOnly import ProductivityTalk_2

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = UIScreen.main.bounds.height
            
            ZStack {
                // Match the gradient from SignUpView
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.3),
                        Color.purple.opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if viewModel.isLoading {
                    LoadingAnimation(message: "Loading videos...")
                        .foregroundColor(.white)
                } else if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.white)
                } else if viewModel.videos.isEmpty {
                    Text("No videos available")
                        .foregroundColor(.white)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.videos) { video in
                                VideoPlayerView(video: video)
                                    .id(video.id)
                                    .frame(height: screenHeight)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .frame(height: screenHeight)
                    .scrollPosition(id: $scrollPosition)
                    .scrollTargetBehavior(.paging)
                    .ignoresSafeArea()
                    .onChange(of: scrollPosition) { _, newValue in
                        if let videoId = newValue {
                            Task {
                                // Find the index of the current video
                                if let index = viewModel.videos.firstIndex(where: { $0.id == videoId }) {
                                    // Pause all videos except the new one
                                    await viewModel.pauseAllExcept(videoId: videoId)
                                    
                                    // Play new video
                                    await viewModel.playerViewModels[videoId]?.play()
                                    
                                    // Preload adjacent videos in the background
                                    viewModel.preloadAdjacentVideos(currentIndex: index)
                                    
                                    // Load more videos if we're near the end
                                    if index >= viewModel.videos.count - 2 {
                                        await viewModel.fetchNextBatch()
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Always visible controls overlay
                if let currentVideo = viewModel.videos.first(where: { $0.id == scrollPosition }) {
                    HStack {
                        Spacer()
                        VStack(spacing: 20) {
                            Spacer()
                            
                            // Brain button
                            Button {
                                if let videoId = scrollPosition {
                                    Task {
                                        await viewModel.playerViewModels[videoId]?.addToSecondBrain()
                                    }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: viewModel.playerViewModels[currentVideo.id]?.isInSecondBrain == true ? "brain.head.profile.fill" : "brain.head.profile")
                                        .font(.system(size: 32))
                                        .foregroundColor(viewModel.playerViewModels[currentVideo.id]?.isInSecondBrain == true ? .blue : .white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    
                                    Text("\(currentVideo.brainCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Comment Button
                            Button {
                                LoggingService.debug("Comment icon tapped", component: "Feed")
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    
                                    Text("\(currentVideo.commentCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 70)
                    }
                }
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            Task {
                await viewModel.fetchVideos()
                // Set initial scroll position to first video
                if let firstVideoId = viewModel.videos.first?.id {
                    scrollPosition = firstVideoId
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

#Preview {
    VideoFeedView()
} 