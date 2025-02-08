import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var showComments = false
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            // Video Player
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
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
                            Button(action: {}) {
                                Image(systemName: "arrowshape.turn.up.right")
                                    .font(.system(size: 28))
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

struct CommentsView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Text("Comments Coming Soon")
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
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