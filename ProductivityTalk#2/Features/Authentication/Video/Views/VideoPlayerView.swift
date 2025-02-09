import SwiftUI
import AVKit

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
        LoggingService.video("Initializing VideoPlayerView for video: \(video.id)", component: "UI")
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    LoadingAnimation(message: "Loading video...")
                        .foregroundColor(.white)
                }
                
                // Watch Time Indicator (optional, for debugging)
                if viewModel.isPlaying {
                    VStack {
                        HStack {
                            Text("Watch Time: \(Int(viewModel.watchTime))s")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            Spacer()
                        }
                        .padding(.top, 44)
                        .padding(.leading, 16)
                        Spacer()
                    }
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
                                    LoggingService.debug("Brain icon tapped for video: \(video.id)", component: "Player")
                                    Task {
                                        do {
                                            try await viewModel.addToSecondBrain()
                                        } catch {
                                            LoggingService.error("Failed to add to second brain: \(error.localizedDescription)", component: "Player")
                                        }
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
                                    LoggingService.debug("Comment icon tapped for video: \(video.id)", component: "Player")
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
                            .padding(.bottom, 70)
                        }
                    }
                    .transition(.opacity)
                }
                
                // Confetti animation overlay
                if viewModel.showBrainAnimation {
                    ConfettiView(position: viewModel.brainAnimationPosition)
                }
            }
            .onAppear {
                LoggingService.video("Video view appeared for \(video.id)", component: "Player")
                isVisible = true
                if !viewModel.isLoading {
                    Task {
                        await viewModel.play()
                    }
                }
            }
            .onDisappear {
                LoggingService.video("Video view disappeared for \(video.id)", component: "Player")
                isVisible = false
                Task {
                    await viewModel.pause()
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if !isLoading && isVisible {
                    LoggingService.video("Video loaded for \(video.id)", component: "Player")
                    Task {
                        await viewModel.play()
                    }
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
                    do {
                        try await viewModel.addToSecondBrain()
                    } catch {
                        LoggingService.error("Failed to add to second brain: \(error.localizedDescription)", component: "Player")
                    }
                }
            }
            .task {
                if !viewModel.isLoading && viewModel.player == nil {
                    viewModel.loadVideo()
                }
            }
            .onChange(of: video.videoURL) { _, newURL in
                if !newURL.isEmpty {
                    viewModel.loadVideo()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    if isVisible {
                        Task {
                            await viewModel.play()
                        }
                    }
                case .inactive, .background:
                    Task {
                        await viewModel.pause()
                    }
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
    }
} 