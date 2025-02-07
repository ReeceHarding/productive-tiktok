import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel: VideoPlayerViewModel
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            VStack {
                Spacer()
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.title)
                            .font(.headline)
                        
                        Text(video.description)
                            .font(.subheadline)
                        
                        HStack {
                            ForEach(video.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Button(action: { viewModel.toggleLike() }) {
                            VStack {
                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                    .foregroundColor(viewModel.isLiked ? .red : .white)
                                Text("\(video.likeCount)")
                                    .font(.caption)
                            }
                        }
                        
                        Button(action: { viewModel.toggleSave() }) {
                            VStack {
                                Image(systemName: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                                    .foregroundColor(viewModel.isSaved ? .yellow : .white)
                                Text("\(video.saveCount)")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.trailing)
                }
                .foregroundColor(.white)
                .shadow(radius: 3)
            }
        }
        .onAppear {
            viewModel.setupPlayer()
            viewModel.checkInteractionStatus()
        }
        .onDisappear {
            viewModel.cleanup()
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