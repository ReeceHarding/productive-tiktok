import SwiftUI
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    @State private var showComments = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSaveConfirmation = false
    @State private var showSaveError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Video Content Layer
            GeometryReader { geometry in
                TabView(selection: $currentIndex) {
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                        VideoPlayerView(video: video)
                            .frame(
                                width: geometry.size.height,  // Swap width and height
                                height: geometry.size.width
                            )
                            .rotationEffect(.degrees(-90))
                            .tag(index)
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        // Only track horizontal drag (which is now vertical due to rotation)
                                        dragOffset = max(0, gesture.translation.height)
                                    }
                                    .onEnded { gesture in
                                        if dragOffset > 100 { // Threshold to trigger save
                                            Task {
                                                await saveToSecondBrain(video: video)
                                            }
                                        }
                                        dragOffset = 0
                                    }
                            )
                    }
                }
                .frame(
                    width: geometry.size.height,  // Swap width and height here too
                    height: geometry.size.width
                )
                .rotationEffect(.degrees(90))
                .frame(
                    width: geometry.size.width,   // Frame to maintain original container size
                    height: geometry.size.height
                )
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
                // Monitor index changes for infinite scrolling and preloading
                .onChange(of: currentIndex) { oldValue, newValue in
                    // Preload next set of videos when approaching the end
                    if newValue >= viewModel.videos.count - 2 {
                        Task {
                            print("🔄 VideoFeed: Preloading next batch of videos")
                            await viewModel.fetchNextBatch()
                        }
                    }
                    
                    // Implement infinite scrolling by resetting to start
                    if newValue == viewModel.videos.count - 1 {
                        print("🔄 VideoFeed: Reached end, loading more videos")
                        Task {
                            await viewModel.fetchNextBatch()
                        }
                    }
                    
                    // Preload video for the next index
                    if newValue + 1 < viewModel.videos.count {
                        print("⏭️ VideoFeed: Preloading next video")
                        viewModel.preloadVideo(at: newValue + 1)
                    }
                }
            }
            
            // Swipe Indicator Overlay
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
            
            // Fixed Position UI Elements Layer
            VStack {
                // Top Navigation
                HStack(spacing: 20) {
                    Text("For You")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Right-side interaction buttons
                if !viewModel.videos.isEmpty, let currentVideo = viewModel.videos[safe: currentIndex] {
                    HStack {
                        Spacer()
                        VStack(spacing: 20) {
                            // Profile Picture with Follow Button
                            VStack(spacing: 4) {
                                AsyncImage(url: URL(string: currentVideo.ownerProfilePicURL ?? "")) { image in
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
                                Button(action: {
                                    if let playerView = viewModel.playerViewModels[currentVideo.id] {
                                        playerView.toggleLike()
                                    }
                                }) {
                                    Image(systemName: viewModel.playerViewModels[currentVideo.id]?.isLiked == true ? "heart.fill" : "heart")
                                        .foregroundColor(viewModel.playerViewModels[currentVideo.id]?.isLiked == true ? .red : .white)
                                        .font(.system(size: 32))
                                }
                                Text(formatCount(currentVideo.likeCount))
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
                                Text(formatCount(currentVideo.commentCount))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            // Share Button
                            VStack(spacing: 4) {
                                Button {
                                    if let playerView = viewModel.playerViewModels[currentVideo.id] {
                                        playerView.shareVideo()
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                }
                                Text("Share")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .sheet(isPresented: $showComments) {
            if let currentVideo = viewModel.videos[safe: currentIndex] {
                CommentsView(video: currentVideo)
                    .presentationDetents([.medium, .large])
            }
        }
        .task {
            if viewModel.videos.isEmpty {
                print("🎬 VideoFeed: Initial video fetch")
                await viewModel.fetchVideos()
            }
        }
    }
    
    private func saveToSecondBrain(video: Video) async {
        do {
            if let playerViewModel = viewModel.playerViewModels[video.id] {
                try await playerViewModel.saveToSecondBrain()
                withAnimation {
                    showSaveConfirmation = true
                }
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showSaveConfirmation = false
                    }
                }
            }
        } catch {
            print("❌ VideoFeed: Failed to save to Second Brain: \(error)")
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

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    VideoFeedView()
} 