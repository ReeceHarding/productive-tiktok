import SwiftUI
import AVKit
import FirebaseFirestore
import Combine

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @State private var isRefreshing = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                // Show skeleton placeholders
                SkeletonScrollView()
            } else {
                // Main feed
                ScrollView {
                    // Pull-to-refresh
                    refreshableContent
                }
                .background(.black)
                .scrollIndicators(.hidden)
                
                // Error or empty overlay
                if let error = viewModel.error {
                    errorOverlay(error.localizedDescription)
                } else if viewModel.videos.isEmpty {
                    emptyOverlay
                }
            }
            
            // Performance overlay or optional metrics
            performanceOverlay
        }
        .onAppear {
            Task {
                // If not loaded, do initial fetch
                if viewModel.videos.isEmpty {
                    await viewModel.fetchVideos()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .navigationBarHidden(true)
    }
    
    /// The main body of the feed when we have data.
    private var refreshableContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.videos) { video in
                FeedVideoCell(video: video)
                    .id(video.id)
                    .frame(height: UIScreen.main.bounds.height)
                    .overlay(
                        // Tappable overlay to bring up controls with a single tap
                        Button {
                            // We can show/hide overlay or do custom logic
                        } label: {
                            Rectangle().foregroundColor(.clear)
                        }
                    )
                    .onAppear {
                        let index = viewModel.videos.firstIndex(where: { $0.id == video.id }) ?? 0
                        // Attempt next batch if near the end
                        if index == viewModel.videos.count - 2 {
                            Task { await viewModel.fetchNextBatch() }
                        }
                        // Preload adjacent
                        Task {
                            await viewModel.preloadVideo(at: index + 1)
                        }
                    }
            }
        }
        .overlay(
            // Custom "pull to refresh" if desired
            GeometryReader { geometry in
                if geometry.frame(in: .global).minY > 80 {
                    // Trigger refresh once user drags enough
                    Color.clear
                        .onAppear {
                            if !isRefreshing {
                                isRefreshing = true
                                Task {
                                    viewModel.error = nil
                                    viewModel.setLoading(true)
                                    await viewModel.fetchVideos()
                                    isRefreshing = false
                                }
                            }
                        }
                }
            }
        )
    }
    
    /// Error state overlay
    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Error")
                .font(.title)
                .foregroundColor(.white)
            Text(message)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    viewModel.error = nil
                    viewModel.setLoading(true)
                    await viewModel.fetchVideos()
                }
            }
            .padding()
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
    }
    
    /// Empty overlay if no videos
    private var emptyOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack")
                .font(.system(size: 48))
                .foregroundColor(.white)
            Text("No videos available")
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Possibly resume the currently visible video
            break
        case .inactive, .background:
            // Pause all videos
            Task {
                await viewModel.pauseAllExcept(videoId: "")
            }
        @unknown default:
            break
        }
    }
    
    /// Optional performance overlay
    private var performanceOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("FPS: \(PerformanceMonitor.shared.fps)")
                    Text("Mem: \(String(format: "%.1f", PerformanceMonitor.shared.memoryUsageMB)) MB")
                }
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding()
            Spacer()
        }
    }
}

// MARK: - Skeleton ScrollView
private struct SkeletonScrollView: View {
    var body: some View {
        ScrollView {
            ForEach(0..<3) { _ in
                SkeletonView()
                    .frame(height: UIScreen.main.bounds.height * 0.75)
                    .padding(.bottom, 20)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .background(Color.black)
    }
}

// MARK: - FeedVideoCell
private struct FeedVideoCell: View {
    let video: Video
    @EnvironmentObject var viewModel: VideoFeedViewModel  // Not used here; can be used for direct calls
    
    var body: some View {
        ZStack {
            // The actual video player
            if let vm = viewModel.playerViewModels[video.id] {
                VideoPlayerView(video: video)
                    .environmentObject(vm)
            } else {
                // If no VM yet, fallback
                Color.black
            }
            
            // Top-right or top-left corner for stats, etc. if needed
        }
        .ignoresSafeArea()
    }
}