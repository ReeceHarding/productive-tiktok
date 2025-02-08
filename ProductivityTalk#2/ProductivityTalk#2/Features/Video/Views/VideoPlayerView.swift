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
    @Environment(\.scenePhase) private var scenePhase
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                CustomVideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        print("▶️ VideoPlayer: Starting playback for video: \(video.id)")
                        player.play()
                    }
                    .onDisappear {
                        print("⏸️ VideoPlayer: Pausing playback for video: \(video.id)")
                        player.pause()
                    }
                
                // Video Controls Overlay
                VStack {
                    Spacer()
                    
                    // Video Information
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.title)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text(video.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Right-side interaction buttons
                        VStack(spacing: 20) {
                            Button(action: viewModel.toggleLike) {
                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(viewModel.isLiked ? .red : .white)
                            }
                            
                            Button(action: viewModel.toggleSave) {
                                Image(systemName: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.title)
                                    .foregroundColor(viewModel.isSaved ? .yellow : .white)
                            }
                            
                            Button {
                                viewModel.shareVideo()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing)
                        .padding(.bottom, 40)
                    }
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
            
            // Overlay Content
            VStack {
                Spacer()
                
                HStack(alignment: .bottom, spacing: 16) {
                    // Left side - Username and Caption
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(video.ownerUsername)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(video.description)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                        
                        FlowLayout(spacing: 4) {
                            ForEach(video.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.leading)
                    .padding(.bottom, 20)
                    
                    Spacer()
                    
                    // Right side - Interaction Buttons
                    VStack(spacing: 24) {
                        // Profile Picture with Follow Button
                        VStack(spacing: 4) {
                            AsyncImage(url: URL(string: video.ownerProfilePicURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white))
                                    .offset(y: 20)
                            )
                        }
                        .padding(.bottom, 10)
                        
                        // Like Button
                        VStack(spacing: 4) {
                            Button(action: { viewModel.toggleLike() }) {
                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                    .foregroundColor(viewModel.isLiked ? .red : .white)
                                    .font(.system(size: 32))
                            }
                            Text(formatCount(video.likeCount))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        // Comments Button
                        VStack(spacing: 4) {
                            Button(action: { showComments = true }) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
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
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Text("Share")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing)
                    .padding(.bottom, 20)
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.3)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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
                viewModel.player?.play()
            case .inactive, .background:
                print("📱 VideoPlayer: App became inactive/background - pausing playback")
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
}

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎥 CustomVideoPlayer: Creating new AVPlayerViewController")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
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