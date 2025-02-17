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
    @State private var showNotificationSetup = false
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
        LoggingService.video("Initializing VideoPlayerView for video: \(video.id)", component: "UI")
    }
    
    public var body: some View {
        ZStack {
            // Video Player
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .containerRelativeFrame([.horizontal, .vertical])
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player for \(video.title)")
                    .accessibilityAddTraits(.startsMediaSession)
                    .overlay(
                        // Replace buffering spinner with our custom LoadingAnimation
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
                    showComments: $showComments,
                    showNotificationSetup: $showNotificationSetup
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // Confetti animation overlay
            if viewModel.showBrainAnimation {
                ConfettiView(position: viewModel.brainAnimationPosition)
                    .accessibilityHidden(true)
            }
        }
        .background(Color.black)
        .task {
            if !viewModel.isLoading && viewModel.player == nil {
                await viewModel.loadVideo()
            }
        }
        .onAppear {
            LoggingService.video("Video view appeared for \(video.id)", component: "Player")
            isVisible = true
        }
        .task(id: isVisible) {
            if isVisible && !viewModel.isLoading {
                await viewModel.play()
            }
        }
        .onDisappear {
            LoggingService.video("Video view disappeared for \(video.id)", component: "Player")
            isVisible = false
            Task {
                await viewModel.pause()
            }
        }
        .onChange(of: viewModel.loadingProgress) { _, newProgress in
            loadingProgress = newProgress
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if !isLoading && isVisible {
                LoggingService.video("Video loaded for \(video.id)", component: "Player")
                Task {
                    await viewModel.play()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleControls()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let location = value.location
                    viewModel.brainAnimationPosition = location
                }
        )
        .onTapGesture(count: 2) {
            Task {
                do {
                    try await viewModel.addToSecondBrain()
                } catch {
                    LoggingService.error("Failed to add to second brain: \(error)", component: "Player")
                    errorMessage = "Failed to save to Second Brain"
                    showError = true
                }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(video: video)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNotificationSetup) {
            if let transcript = viewModel.video.transcript {
                VideoNotificationSetupView(videoId: video.id, originalTranscript: transcript)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Cannot Set Notification")
                        .font(.headline)
                    Text("The video is still processing. Please try again in a moment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("OK", role: .cancel) {
                        showNotificationSetup = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationDetents([.height(250)])
            }
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
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
    @Binding var showNotificationSetup: Bool

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
                            LoggingService.debug("Bell icon tapped for video: \(video.id), has transcript: \(viewModel.video.transcript != nil)", component: "Player")
                            if viewModel.isSubscribedToNotifications {
                                Task {
                                    await viewModel.removeNotification()
                                }
                            } else {
                                showNotificationSetup = true
                            }
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