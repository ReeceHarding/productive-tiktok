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
                    .onAppear {
                        // Ensure player starts when view appears
                        Task {
                            await viewModel.play()
                        }
                    }
            } else {
                LoadingAnimation(message: "Loading video...")
                    .foregroundColor(.white)
                    .containerRelativeFrame([.horizontal, .vertical])
            }
            
            // Overlay for UI controls (shown when toggled)
            if viewModel.showControls {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
            }
            
            // Overlay for UI controls (shown when toggled)
            if viewModel.showControls {
                GeometryReader { geometry in
                    HStack {
                        Spacer()
                        VStack(spacing: 24) {
                            // Brain button
                            Button {
                                LoggingService.debug("Brain icon tapped for video: \(video.id)", component: "Player")
                                Task {
                                    do {
                                        try await viewModel.addToSecondBrain()
                                    } catch {
                                        print("Error adding to second brain: \(error)")
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: viewModel.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                                        .font(.system(size: 34))
                                        .foregroundColor(viewModel.isInSecondBrain ? .blue : .white)
                                        .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: 2)
                                    
                                    Text("\(viewModel.brainCount)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .frame(width: 44, height: 60)
                            
                            // Comment Button
                            Button {
                                LoggingService.debug("Comment icon tapped for video: \(video.id)", component: "Player")
                                showComments = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 34))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: 2)
                                    
                                    Text("\(video.commentCount)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .frame(width: 44, height: 60)
                        }
                        .padding(.trailing, geometry.size.width * 0.05)
                        .padding(.bottom, geometry.size.height * 0.15)
                    }
                }
                .transition(.opacity)
            }
            
            // Confetti animation overlay
            if viewModel.showBrainAnimation {
                ConfettiView(position: viewModel.brainAnimationPosition)
            }
        }
        .background(Color.black)
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
                    print("Error adding to second brain: \(error)")
                }
            }
        }
        .task {
            if !viewModel.isLoading && viewModel.player == nil {
                await viewModel.loadVideo()
            }
        }
        .onChange(of: video.videoURL) { _, newURL in
            if !newURL.isEmpty {
                Task {
                    await viewModel.loadVideo()
                }
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