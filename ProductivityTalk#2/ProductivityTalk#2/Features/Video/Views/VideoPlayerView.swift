import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoPlayerView: View {
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
    
    // Simple animation for video appearance
    @State private var isAppearing = false
    private let appearAnimation = Animation.easeOut(duration: 0.3)
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
        LoggingService.video("Initializing VideoPlayerView for video: \(video.id)", component: "UI")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let error = viewModel.playerError {
                    errorView(error)
                } else if let player = viewModel.player {
                    CustomVideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(isAppearing ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: isAppearing)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        .task {
                            LoggingService.video("🎬 VideoPlayer task started for video: \(video.id)", component: "UI")
                            isAppearing = true
                        }
                        .onAppear {
                            LoggingService.video("👀 VideoPlayer appeared for video: \(video.id)", component: "UI")
                        }
                        .onDisappear {
                            LoggingService.video("🔄 VideoPlayer disappeared for video: \(video.id)", component: "UI")
                            withAnimation(.easeOut(duration: 0.3)) {
                                isAppearing = false
                            }
                            // Ensure cleanup when view disappears
                            Task {
                                await viewModel.cleanup()
                            }
                        }
                        .onTapGesture {
                            withAnimation {
                                isOverlayVisible.toggle()
                            }
                            // Toggle playback
                            viewModel.togglePlayback()
                            // Add haptic feedback
                            performHapticFeedback(viewModel.isPlaying ? .soft : .medium)
                            LoggingService.debug("👆 Video tapped - Playback: \(viewModel.isPlaying ? "Playing" : "Paused"), Overlay: \(isOverlayVisible ? "Visible" : "Hidden")", component: "UI")
                        }
                } else {
                    // Show loading state
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }

                // Video controls overlay
                if isOverlayVisible {
                    videoControlsOverlay
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    if viewModel.isPlaying {
                        viewModel.player?.play()
                    }
                case .inactive, .background:
                    Task {
                        await viewModel.cleanup()
                    }
                @unknown default:
                    break
                }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(video: video)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: video.videoURL) {
                ShareSheet(items: [url])
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text(error)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    private var videoControlsOverlay: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Spacer()
                
                // Brain Button
                Button {
                    Task {
                        // Optimistically update the counter
                        if !viewModel.isInSecondBrain {
                            withAnimation {
                                viewModel.updateSaveCount(increment: true)
                            }
                        }
                        
                        do {
                            try await viewModel.saveToSecondBrain()
                        } catch {
                            // Revert on failure
                            withAnimation {
                                viewModel.updateSaveCount(increment: false)
                            }
                            errorMessage = error.localizedDescription
                            showError = true
                            LoggingService.error("Failed to save to Second Brain: \(error.localizedDescription)", component: "UI")
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundColor(viewModel.isInSecondBrain ? .green : .white)
                        Text(formatCount(viewModel.saveCount))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Comments Button
                Button {
                    performHapticFeedback(.light)
                    showComments = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        Text(formatCount(video.commentCount))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Share Button
                Button {
                    performHapticFeedback(.light)
                    showShareSheet = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        Text("Share")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100)
        }
    }
    
    private func handleDoubleTap() {
        LoggingService.video("Double tap detected - saving to Second Brain", component: "UI")
        performHapticFeedback(.medium)
        
        // Show brain animation with enhanced spring animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showBrainAnimation = true
            if !viewModel.isInSecondBrain {
                viewModel.updateSaveCount(increment: true)
            }
        }
        
        // Save to Second Brain
        Task {
            do {
                try await viewModel.saveToSecondBrain()
                performHapticFeedback(.success)
            } catch {
                // Revert on failure
                withAnimation {
                    viewModel.updateSaveCount(increment: false)
                }
                errorMessage = error.localizedDescription
                showError = true
                performHapticFeedback(.error)
                LoggingService.error("Failed to save to Second Brain: \(error.localizedDescription)", component: "UI")
            }
        }
        
        // Hide brain animation after delay with fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                showBrainAnimation = false
            }
        }
    }
    
    private func performHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        LoggingService.debug("Performed haptic feedback: \(style)", component: "UI")
    }
    
    private func performHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        LoggingService.debug("Performed notification feedback: \(type)", component: "UI")
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
}

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        LoggingService.video("Creating new AVPlayerViewController", component: "UI")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        controller.allowsPictureInPicturePlayback = false
        
        // Configure player for optimal playback
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = true
        
        // Optimize view controller
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.updatesNowPlayingInfoCenter = false
        
        // Optimize view layer
        if let playerLayer = controller.view.layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.needsDisplayOnBoundsChange = false
            playerLayer.shouldRasterize = true
            playerLayer.rasterizationScale = UIScreen.main.scale
        }
        
        // Force playback to start with performance monitoring
        DispatchQueue.main.async {
            LoggingService.debug("🎬 Initiating playback in AVPlayerViewController", component: "UI")
            
            // Reset player state
            player.seek(to: .zero)
            player.play()
            player.rate = 1.0
            
            // Monitor initial playback state
            monitorPlaybackState(player: player)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            LoggingService.debug("Updating player in AVPlayerViewController", component: "UI")
            
            // Cleanup old player
            uiViewController.player?.pause()
            uiViewController.player?.currentItem?.asset.cancelLoading()
            
            // Configure new player
            uiViewController.player = player
            
            // Ensure playback continues with new player
            DispatchQueue.main.async {
                player.play()
                player.rate = 1.0
                
                // Monitor playback after update
                monitorPlaybackState(player: player)
            }
        }
    }
    
    private func monitorPlaybackState(player: AVPlayer) {
        LoggingService.debug("Playback verification:", component: "UI")
        LoggingService.debug("- Player rate: \(player.rate)", component: "UI")
        LoggingService.debug("- Player error: \(player.error?.localizedDescription ?? "none")", component: "UI")
        
        if let currentItem = player.currentItem {
            LoggingService.debug("- Item status: \(currentItem.status.rawValue)", component: "UI")
            LoggingService.debug("- Buffer empty: \(currentItem.isPlaybackBufferEmpty)", component: "UI")
            LoggingService.debug("- Buffer full: \(currentItem.isPlaybackBufferFull)", component: "UI")
            LoggingService.debug("- Likely to keep up: \(currentItem.isPlaybackLikelyToKeepUp)", component: "UI")
            
            // Monitor loaded ranges
            if let timeRange = currentItem.loadedTimeRanges.first?.timeRangeValue {
                let bufferedDuration = timeRange.duration.seconds
                let bufferedStart = timeRange.start.seconds
                LoggingService.debug("- Buffered duration: \(bufferedDuration)s from \(bufferedStart)s", component: "UI")
            }
            
            // Check for stalled state
            if currentItem.isPlaybackBufferEmpty {
                LoggingService.debug("⚠️ Playback buffer empty - may stall", component: "UI")
            }
            
            // Monitor asset loading state
            if let asset = currentItem.asset as? AVURLAsset {
                Task {
                    do {
                        let isPlayable = try await asset.load(.isPlayable)
                        LoggingService.debug("- Asset playable: \(isPlayable)", component: "UI")
                    } catch {
                        LoggingService.error("Failed to load asset properties: \(error.localizedDescription)", component: "UI")
                    }
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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