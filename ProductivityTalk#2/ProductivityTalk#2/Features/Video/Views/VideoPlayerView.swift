import SwiftUI
import AVKit
import FirebaseFirestore

public struct VideoPlayerView: View {
    let video: Video
    @StateObject var viewModel: VideoPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var isOverlayVisible = true
    @State private var showBrainAnimation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isVisible = false
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    public var body: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .onAppear {
                        LoggingService.video("Video view appeared for \(video.id)", component: "Player")
                        isVisible = true
                        if !viewModel.isLoading {
                            viewModel.play()
                        }
                    }
                    .onDisappear {
                        LoggingService.video("Video view disappeared for \(video.id)", component: "Player")
                        isVisible = false
                        viewModel.pause()
                    }
                    .onChange(of: viewModel.isLoading) { isLoading in
                        if !isLoading && isVisible {
                            LoggingService.video("Video loaded for \(video.id)", component: "Player")
                            viewModel.play()
                        }
                    }
                    .ignoresSafeArea()
            } else {
                LoadingAnimation(message: "Loading video...")
                    .foregroundColor(.white)
            }
            
            // Overlay for UI controls (shown when toggled)
            if viewModel.showControls {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 20) {
                            // Brain button
                            Button {
                                LoggingService.debug("Brain icon tapped", component: "Player")
                                Task {
                                    await viewModel.addToSecondBrain()
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: viewModel.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                                        .font(.system(size: 32))
                                        .foregroundColor(viewModel.isInSecondBrain ? .blue : .white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    
                                    Text("\(viewModel.brainCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Comment Button
                            Button {
                                LoggingService.debug("Comment icon tapped", component: "Player")
                                showComments = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    
                                    Text("\(video.commentCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.opacity)
            }
            
            // Confetti animation overlay
            if viewModel.showBrainAnimation {
                ConfettiView(position: viewModel.brainAnimationPosition)
            }
            
            // Video controls overlay
            if isOverlayVisible {
                videoControlsOverlay
            }
        }
        // Use tap gestures for control toggling and second brain actions
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            viewModel.toggleControls()
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
                await viewModel.addToSecondBrain()
            }
        }
        .task {
            if !viewModel.isLoading && viewModel.player == nil {
                viewModel.loadVideo()
            }
        }
        .onChange(of: video.videoURL) { newURL in
            if !newURL.isEmpty {
                viewModel.loadVideo()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if isVisible {
                    viewModel.play()
                }
            case .inactive, .background:
                viewModel.pause()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(video: video)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
    }
    
    private var videoControlsOverlay: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Spacer()
                
                // Comment Button
                Button {
                    LoggingService.debug("Comment icon tapped", component: "Player")
                    showComments = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        
                        Text("\(video.commentCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.trailing, 16)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showComments) {
            CommentsView(video: video)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
    }
    
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
} 