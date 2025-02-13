import SwiftUI
import AVKit
import FirebaseFirestore
import UserNotifications

public struct VideoPlayerView: View {
    let video: Video
    @StateObject var viewModel: VideoPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Binding var shouldAutoPlay: Bool
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var isOverlayVisible = true
    @State private var showBrainAnimation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isVisible = false
    @State private var loadingProgress: Double = 0
    @State private var showToast = false
    @State private var toastMessage = ""
    private let hapticManager = UINotificationFeedbackGenerator()
    
    init(video: Video, shouldAutoPlay: Binding<Bool>) {
        self.video = video
        self._shouldAutoPlay = shouldAutoPlay
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
                    .overlay(
                        // Play/Pause tap area (excluding the control buttons area)
                        GeometryReader { geometry in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task {
                                        if viewModel.isPlaying {
                                            await viewModel.pause()
                                        } else {
                                            await viewModel.play()
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: geometry.size.height * 0.85) // Leave space for controls
                        }
                    )
                    // Disable default video controls
                    .disabled(true)
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
                    showComments: $showComments
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // Confetti animation overlay
            if viewModel.showBrainAnimation {
                ConfettiView(position: viewModel.brainAnimationPosition)
                    .accessibilityHidden(true)
            }
            
            // Toast Message
            if let message = viewModel.toastMessage {
                VideoPlayerToastView(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .background(Color.black)
        .task {
            LoggingService.debug("🎥 VideoPlayerView task started for \(video.id), shouldAutoPlay: \(shouldAutoPlay)", component: "UI")
            if !viewModel.isLoading && viewModel.player == nil {
                await viewModel.loadVideo()
            }
        }
        .onAppear {
            LoggingService.video("Video view appeared for \(video.id), shouldAutoPlay: \(shouldAutoPlay)", component: "UI")
            isVisible = true
        }
        .task(id: isVisible) {
            if isVisible && !viewModel.isLoading && shouldAutoPlay {
                LoggingService.debug("🎬 Auto-playing video \(video.id) as it's visible and allowed", component: "UI")
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
                            isActive: viewModel.isInSecondBrain,
                            action: {
                                LoggingService.debug("Brain icon tapped for video: \(video.id)", component: "Player")
                                Task {
                                    do {
                                        try await viewModel.addToSecondBrain()
                                    } catch {
                                        LoggingService.error("Error adding to second brain: \(error)", component: "Player")
                                    }
                                }
                            },
                            onLocationUpdate: { location in
                                viewModel.brainAnimationPosition = location
                            }
                        )
                        .allowsHitTesting(true)
                        
                        // Comment Button
                        ControlButton(
                            icon: "bubble.left",
                            text: "\(video.commentCount)",
                            isActive: false,
                            action: {
                                LoggingService.debug("Comment icon tapped for video: \(video.id)", component: "Player")
                                showComments = true
                            },
                            onLocationUpdate: { _ in }
                        )
                        .allowsHitTesting(true)
                        
                        // Notification Bell Button
                        ControlButton(
                            icon: viewModel.isSubscribedToNotifications ? "bell.fill" : "bell",
                            text: viewModel.isSubscribedToNotifications ? "Subscribed" : "Subscribe",
                            isActive: viewModel.isSubscribedToNotifications,
                            action: {
                                Task {
                                    if viewModel.isSubscribedToNotifications {
                                        await viewModel.removeNotification()
                                    } else {
                                        // Request notification permission and schedule if granted
                                        let center = UNUserNotificationCenter.current()
                                        let settings = await center.notificationSettings()
                                        
                                        if settings.authorizationStatus == .authorized {
                                            // Show notification setup view
                                            let setupView = VideoNotificationSetupView(
                                                videoId: viewModel.video.id,
                                                originalTranscript: viewModel.video.transcript ?? ""
                                            )
                                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                               let root = windowScene.windows.first?.rootViewController {
                                                let hostingController = UIHostingController(rootView: setupView)
                                                root.present(hostingController, animated: true)
                                            }
                                        } else {
                                            // Request permission if not granted
                                            do {
                                                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                                                if granted {
                                                    // Show notification setup view after permission granted
                                                    let setupView = VideoNotificationSetupView(
                                                        videoId: viewModel.video.id,
                                                        originalTranscript: viewModel.video.transcript ?? ""
                                                    )
                                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                                       let root = windowScene.windows.first?.rootViewController {
                                                        let hostingController = UIHostingController(rootView: setupView)
                                                        root.present(hostingController, animated: true)
                                                    }
                                                }
                                            } catch {
                                                print("Error requesting notification permission: \(error)")
                                            }
                                        }
                                    }
                                }
                            },
                            onLocationUpdate: { _ in }
                        )
                        .allowsHitTesting(true)
                    }
                    .padding(.trailing, geometry.size.width * 0.05)
                    .padding(.bottom, geometry.size.height * 0.15)
                }
            }
            .contentShape(Rectangle())
            .allowsHitTesting(true)
        }
        .transition(.opacity)
    }
}

private struct ControlButton: View {
    let icon: String
    let text: String
    var isActive: Bool = false
    let action: () -> Void
    let onLocationUpdate: (CGPoint) -> Void
    @State private var location: CGPoint = .zero
    @State private var isPressed = false
    @State private var scale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    private let hapticManager = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        Button {
            hapticManager.impactOccurred(intensity: 0.8)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.2)) {
                isPressed = true
                scale = 0.8
            }
            
            // Reset scale with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.2)) {
                    isPressed = false
                    scale = 1.0
                }
            }
            
            onLocationUpdate(location)
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isActive ? .blue : .white, isActive ? .blue : .white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .symbolEffect(.bounce, value: isActive)
                
                Text(text)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
        .scaleEffect(scale)
        .buttonStyle(.plain)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ButtonFramePreferenceKey.self, value: geometry.frame(in: .global))
            }
        )
        .onPreferenceChange(ButtonFramePreferenceKey.self) { frame in
            location = CGPoint(x: frame.midX, y: frame.midY)
        }
        .onAppear {
            hapticManager.prepare()
        }
    }
}

struct ButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    let mockVideo = Video(
        id: "mock-id",
        ownerId: "mock-owner",
        videoURL: "https://example.com/video.mp4",
        thumbnailURL: "https://example.com/thumbnail.jpg",
        title: "Mock Video",
        tags: ["test", "mock"],
        description: "This is a mock video for testing",
        ownerUsername: "mockUser"
    )
    return VideoPlayerView(video: mockVideo, shouldAutoPlay: .constant(true))
}

// Add ToastView at the end of the file
private struct VideoPlayerToastView: View {
    let message: String?
    
    var body: some View {
        if let message = message {
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4)
                .padding(.top, 50)
        }
    }
}