import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var showComments = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSaveConfirmation = false
    @State private var showSaveError = false
    @State private var errorMessage = ""
    @State private var isAppearing = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAddingToSecondBrain = false
    @State private var brainScale: CGFloat = 1.0
    @State private var brainRotation: Double = 0.0
    
    // Animation properties
    private let appearAnimation = Animation.spring(response: 0.6, dampingFraction: 0.8)
    private let contentAnimation = Animation.easeInOut(duration: 0.3)
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                CustomVideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .opacity(isAppearing ? 1 : 0)
                    .onAppear {
                        withAnimation(appearAnimation) {
                            isAppearing = true
                        }
                        print("▶️ VideoPlayer: Starting playback for video: \(video.id)")
                        player.play()
                    }
                    .onDisappear {
                        withAnimation(appearAnimation) {
                            isAppearing = false
                        }
                        print("⏸️ VideoPlayer: Pausing playback for video: \(video.id)")
                        player.pause()
                    }
                
                // Video Controls Overlay with improved animations
                VStack {
                    Spacer()
                    
                    HStack {
                        // Video Information with fade animation
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .opacity(isAppearing ? 1 : 0)
                                .animation(contentAnimation.delay(0.2), value: isAppearing)
                            
                            Text(video.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                                .opacity(isAppearing ? 1 : 0)
                                .animation(contentAnimation.delay(0.3), value: isAppearing)
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Right side buttons
                        VStack(spacing: 24) {
                            brainButton(for: video)  // New brain button
                            
                            // Comments Button
                            VStack(spacing: 4) {
                                Button(action: { showComments = true }) {
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                }
                                .opacity(isAppearing ? 1 : 0)
                                .animation(contentAnimation.delay(0.6), value: isAppearing)
                                
                                Text(formatCount(video.commentCount))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            // Share Button
                            VStack(spacing: 4) {
                                Button {
                                    viewModel.shareVideo()
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                }
                                .opacity(isAppearing ? 1 : 0)
                                .animation(contentAnimation.delay(0.7), value: isAppearing)
                                
                                Text("Share")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing)
                        .padding(.bottom, 50)
                    }
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
            
            // Save Confirmation Overlay
            if showSaveConfirmation {
                VStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("Saved to Second Brain!")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Error Overlay
            if showSaveError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                    Text("Failed to Save")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .transition(.scale.combined(with: .opacity))
                .padding(.horizontal)
            }
            
            // Swipe Indicator
            if dragOffset > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 30))
                    Text("Keep swiping to save")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .scaleEffect(min(1.0, dragOffset / 100))
                .opacity(min(1.0, dragOffset / 100))
            }
        }
        .onAppear {
            viewModel.setupPlayer()
            viewModel.checkInteractionStatus()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showComments) {
            CommentsView(video: video)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                print("📱 VideoPlayer: App became active - resuming playback")
                withAnimation(appearAnimation) {
                    isAppearing = true
                }
                viewModel.player?.play()
            case .inactive, .background:
                print("📱 VideoPlayer: App became inactive/background - pausing playback")
                withAnimation(appearAnimation) {
                    isAppearing = false
                }
                viewModel.player?.pause()
            @unknown default:
                break
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
    
    private func performBrainAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            brainScale = 1.3
            brainRotation = 360
            isAddingToSecondBrain = true
        }
        
        // Reset animation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                brainScale = 1.0
                brainRotation = 0
            }
        }
    }

    private func brainButton(for video: Video) -> some View {
        VStack(spacing: 4) {
            Button(action: {
                performBrainAnimation()
                Task {
                    do {
                        try await viewModel.saveToSecondBrain()
                        withAnimation {
                            showSaveConfirmation = true
                        }
                        // Hide confirmation after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showSaveConfirmation = false
                            }
                        }
                    } catch {
                        print("❌ Failed to save to Second Brain: \(error)")
                        errorMessage = error.localizedDescription
                        withAnimation {
                            showSaveError = true
                        }
                        // Hide error after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                showSaveError = false
                            }
                        }
                    }
                }
            }) {
                Image(systemName: isAddingToSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                    .foregroundColor(isAddingToSecondBrain ? .green : .white)
                    .font(.system(size: 32))
                    .scaleEffect(brainScale)
                    .rotationEffect(.degrees(brainRotation))
            }
            Text("Save")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .opacity(isAppearing ? 1 : 0)
        .animation(contentAnimation.delay(0.5), value: isAppearing)
    }
}

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎥 CustomVideoPlayer: Creating new AVPlayerViewController")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        
        // Optimize playback
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = true
        
        if let playerItem = player.currentItem {
            playerItem.preferredForwardBufferDuration = 4.0
            playerItem.preferredMaximumResolution = CGSize(width: 1080, height: 1920)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update if needed
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, line) in result.lines.enumerated() {
            let y = bounds.minY + result.lineOffsets[index]
            var x = bounds.minX
            
            for item in line {
                let size = item.sizeThatFits(.unspecified)
                item.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }
    
    struct FlowResult {
        var lines: [[LayoutSubview]] = [[]]
        var lineOffsets: [CGFloat] = [0]
        var size: CGSize = .zero
        
        init(in width: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            var currentLine: Int = 0
            var maxWidth: CGFloat = 0
            
            for subview in subviews {
                let itemSize = subview.sizeThatFits(.unspecified)
                
                if x + itemSize.width > width && !lines[currentLine].isEmpty {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                    currentLine += 1
                    lines.append([])
                    lineOffsets.append(y)
                }
                
                lines[currentLine].append(subview)
                x += itemSize.width + spacing
                lineHeight = max(lineHeight, itemSize.height)
                maxWidth = max(maxWidth, x)
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    VideoPlayerView(video: Video(
        id: "preview",
        ownerId: "user123",
        videoURL: "https://example.com/video.mp4",
        thumbnailURL: "https://example.com/thumbnail.jpg",
        title: "Sample Video",
        tags: ["productivity", "tech"],
        description: "This is a sample video description",
        ownerUsername: "testuser"
    ))
} 