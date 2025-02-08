import SwiftUI
import AVKit
import FirebaseFirestore

public struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var isOverlayVisible = true
    @State private var showBrainAnimation = false
    @State private var brainAnimationPosition: CGPoint = .zero
    @State private var errorMessage: String?
    @State private var showError = false
    
    public init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .edgesIgnoringSafeArea(.all)
                        .onAppear {
                            LoggingService.video("Playing video with URL: \(video.videoURL)", component: "Player")
                            player.play()
                        }
                        .onDisappear {
                            LoggingService.video("Pausing video with URL: \(video.videoURL)", component: "Player")
                            player.pause()
                        }
                } else if viewModel.isLoading {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                    ProgressView("Loading video...")
                        .foregroundColor(.white)
                } else if let error = viewModel.error {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                } else if video.videoURL.isEmpty {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                    ProgressView("Waiting for video...")
                        .foregroundColor(.white)
                }
                
                // Brain animation overlay
                if viewModel.showBrainAnimation {
                    Image(systemName: "brain.head.profile")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.white)
                        .position(viewModel.brainAnimationPosition)
                        .transition(.scale)
                }
                
                // Video controls overlay
                if isOverlayVisible {
                    videoControlsOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture(count: 1) {
                withAnimation {
                    isOverlayVisible.toggle()
                }
            }
            .onTapGesture(count: 2) { location in
                viewModel.brainAnimationPosition = location
                Task {
                    await viewModel.addToSecondBrain()
                }
            }
            .task {
                await viewModel.loadVideo()
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
                    viewModel.player?.play()
                case .inactive, .background:
                    viewModel.player?.pause()
                @unknown default:
                    break
                }
            }
        }
    }
    
    private var videoControlsOverlay: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Spacer()
                
                // Brain Button
                Button {
                    Task {
                        await viewModel.addToSecondBrain()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }
                .gesture(TapGesture(count: 2).onEnded {
                    Task {
                        await viewModel.addToSecondBrain()
                    }
                })
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100)
        }
    }
} 