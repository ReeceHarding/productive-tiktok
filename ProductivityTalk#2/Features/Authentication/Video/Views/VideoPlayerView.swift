import SwiftUI
import AVKit
import FirebaseFirestore

public struct VideoPlayerView: View {
    let video: Video
    @StateObject var viewModel: VideoPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var isOverlayVisible = true
    @State private var showBrainAnimation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isVisible = false
    @State private var loadingProgress: Double = 0
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
        LoggingService.video("Initializing VideoPlayerView for video: \(video.id)", component: "UI")
    }
    
    public var body: some View {
        VideoPlayerContainer(
            video: video,
            viewModel: viewModel,
            isVisible: $isVisible,
            loadingProgress: $loadingProgress,
            showComments: $showComments,
            showError: $showError,
            errorMessage: $errorMessage
        )
    }
}

private struct VideoPlayerContainer: View {
    let video: Video
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var isVisible: Bool
    @Binding var loadingProgress: Double
    @Binding var showComments: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            // Video Player
            VideoPlayerContent(
                video: video,
                viewModel: viewModel,
                loadingProgress: $loadingProgress
            )
            
            // Overlays
            VideoPlayerOverlays(
                video: video,
                viewModel: viewModel,
                showComments: $showComments
            )
        }
        .background(Color.black)
        .task {
            if !viewModel.isLoading && viewModel.player == nil {
                LoggingService.debug("Initial task - Loading video for \(video.id)", component: "Player")
                do {
                    await viewModel.loadVideo()
                } catch {
                    LoggingService.error("Failed to load video: \(error)", component: "Player")
                }
            }
        }
        .onAppear {
            LoggingService.video("Video view appeared for \(video.id)", component: "Player")
            isVisible = true
            LoggingService.debug("Set isVisible to true for \(video.id)", component: "Player")
        }
        .task(id: isVisible) {
            if isVisible && !viewModel.isLoading {
                LoggingService.debug("isVisible task - Playing video \(video.id) (isLoading: \(viewModel.isLoading))", component: "Player")
                do {
                    try await viewModel.play()
                } catch {
                    LoggingService.error("Failed to play video: \(error)", component: "Player")
                }
            }
        }
        .onDisappear {
            LoggingService.video("Video view disappeared for \(video.id)", component: "Player")
            isVisible = false
            LoggingService.debug("Set isVisible to false for \(video.id)", component: "Player")
            Task {
                await viewModel.pausePlayback()
            }
        }
        .onChange(of: viewModel.loadingProgress) { _, newProgress in
            loadingProgress = newProgress
            LoggingService.debug("Loading progress updated to \(newProgress) for \(video.id)", component: "Player")
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if !isLoading && isVisible {
                LoggingService.debug("isLoading changed - Playing video \(video.id) (isVisible: \(isVisible))", component: "Player")
                Task {
                    do {
                        try await viewModel.play()
                    } catch {
                        LoggingService.error("Failed to play video: \(error)", component: "Player")
                    }
                }
            }
        }
        .gesture(
            VideoPlayerGestures(
                viewModel: viewModel,
                showError: $showError,
                errorMessage: $errorMessage
            )
        )
        .sheet(isPresented: $showComments) {
            CommentsView(viewModel: CommentsViewModel(video: video))
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

private struct VideoPlayerOverlays: View {
    let video: Video
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var showComments: Bool
    
    var body: some View {
        ZStack {
            // Error Overlay
            if let error = viewModel.error {
                ErrorOverlay(error: error) {
                    Task {
                        await viewModel.retryLoading()
                    }
                }
            }
            
            // Controls Overlay
            if viewModel.showControls {
                ControlsOverlay(
                    video: video,
                    viewModel: viewModel,
                    showComments: $showComments
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // Confetti animation overlay
            if viewModel.showBrainAnimation {
                ConfettiView(position: viewModel.brainAnimationPosition)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct VideoPlayerGestures: Gesture {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var showError: Bool
    @Binding var errorMessage: String?
    
    var body: some Gesture {
        SimultaneousGesture(
            TapGesture(count: 1)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleControls()
                    }
                },
            SimultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        Task {
                            do {
                                try await viewModel.addToSecondBrain()
                            } catch {
                                LoggingService.error("Failed to add to second brain: \(error)", component: "Player")
                                errorMessage = "Failed to save to Second Brain"
                                showError = true
                            }
                        }
                    },
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        viewModel.brainAnimationPosition = value.location
                    }
            )
        )
    }
}

private struct VideoPlayerContent: View {
    let video: Video
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var loadingProgress: Double
    
    var body: some View {
        Group {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .containerRelativeFrame([.horizontal, .vertical])
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player for \(video.title)")
                    .accessibilityAddTraits(.startsMediaSession)
                    .overlay(
                        Group {
                            if viewModel.isBuffering {
                                ZStack {
                                    Color.black.opacity(0.3)
                                        .ignoresSafeArea()
                                    LoadingAnimation(message: "Buffering...")
                                        .foregroundColor(.white)
                                        .scaleEffect(1.2)
                                }
                            }
                        }
                    )
            } else {
                VideoLoadingView(progress: $loadingProgress)
                    .containerRelativeFrame([.horizontal, .vertical])
            }
        }
    }
}

// MARK: - Supporting Views
private struct VideoLoadingView: View {
    @Binding var progress: Double
    
    var body: some View {
        VStack(spacing: 16) {
            LoadingAnimation(message: nil)
                .scaleEffect(1.5)
            
            Text("\(Int(progress * 100))%")
                .foregroundStyle(.white)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading video \(Int(progress * 100)) percent complete")
    }
}

private struct ErrorOverlay: View {
    let error: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            
            Text(error)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ControlsOverlay: View {
    let video: Video
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var showComments: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 24) {
                        // Brain button
                        ControlButton(
                            icon: viewModel.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile",
                            text: "\(viewModel.brainCount)",
                            isActive: viewModel.isInSecondBrain
                        ) {
                            LoggingService.debug("Brain icon tapped for video: \(video.id)", component: "Player")
                            Task {
                                do {
                                    try await viewModel.addToSecondBrain()
                                } catch {
                                    LoggingService.error("Error adding to second brain: \(error)", component: "Player")
                                }
                            }
                        }
                        
                        // Comment Button
                        ControlButton(
                            icon: "bubble.left",
                            text: "\(video.commentCount)"
                        ) {
                            LoggingService.debug("Comment icon tapped for video: \(video.id)", component: "Player")
                            showComments = true
                        }
                        
                        // Notification Bell Button
                        ControlButton(
                            icon: viewModel.isSubscribedToNotifications ? "bell.fill" : "bell",
                            text: "Remind",
                            isActive: viewModel.isSubscribedToNotifications
                        ) {
                            LoggingService.debug("Bell icon tapped for video: \(video.id)", component: "Player")
                            // This is the notification flow, not calendar
                            viewModel.isSubscribedToNotifications.toggle()
                            // Implementation of showing notification setup
                            // or just open the VideoNotificationSetupView
                            // (Left as is, user did not request removal of notifications)
                        }
                    }
                    .padding(.trailing, geometry.size.width * 0.05)
                    .padding(.bottom, geometry.size.height * 0.15)
                }
            }
        }
        .transition(.opacity)
    }
}

private struct ControlButton: View {
    let icon: String
    let text: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 34))
                    .foregroundColor(isActive ? .blue : .white)
                    .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: 2)
                
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(width: 44, height: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text) button")
        .accessibilityHint("Double tap to \(text.lowercased())")
    }
}