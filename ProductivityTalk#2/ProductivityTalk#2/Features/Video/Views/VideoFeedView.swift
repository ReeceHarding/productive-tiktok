import SwiftUI
import FirebaseFirestore
import CoreHaptics

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    @State private var showComments = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSaveConfirmation = false
    @State private var showSaveError = false
    @State private var errorMessage = ""
    @State private var engine: CHHapticEngine?
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var isScrolling = false
    
    // Animation properties
    private let springAnimation = Animation.spring(response: 0.5, dampingFraction: 0.8)
    private let transitionAnimation = Animation.easeInOut(duration: 0.3)
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.videos.isEmpty {
                emptyStateView
            } else {
                videoContentLayer
                overlayLayer
                fixedUILayer
            }
        }
        .task {
            if viewModel.videos.isEmpty {
                LoggingService.video("Initial video fetch", component: "Feed")
                await viewModel.fetchVideos()
            }
        }
        .sheet(isPresented: $showComments) {
            if let currentVideo = viewModel.videos[safe: currentIndex] {
                CommentsView(video: currentVideo)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            prepareHaptics()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading videos...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 50))
                .foregroundColor(.primary)
            Text("No Videos Available")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text("Check back later for new content")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: {
                Task {
                    await viewModel.fetchVideos()
                }
            }) {
                Text("Refresh")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text("Error Loading Videos")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: {
                Task {
                    await viewModel.fetchVideos()
                }
            }) {
                Text("Try Again")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Content Layers
    
    private var videoContentLayer: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                    VideoPlayerView(video: video)
                        .frame(
                            width: geometry.size.height,
                            height: geometry.size.width
                        )
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                        .gesture(createDragGesture(for: video))
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(
                width: geometry.size.height,
                height: geometry.size.width
            )
            .rotationEffect(.degrees(90))
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .tabViewStyle(
                PageTabViewStyle(indexDisplayMode: .never)
            )
            .ignoresSafeArea()
            .onChange(of: currentIndex) { oldValue, newValue in
                handleIndexChange(newValue)
            }
        }
    }
    
    private var overlayLayer: some View {
        Group {
            if dragOffset > 0 { swipeIndicator }
            if showSaveConfirmation { saveConfirmation }
            if showSaveError { errorOverlay }
        }
    }
    
    private var fixedUILayer: some View {
        VStack {
            topNavigation
            Spacer()
            if !viewModel.videos.isEmpty,
               let currentVideo = viewModel.videos[safe: currentIndex] {
                interactionButtons(for: currentVideo)
            }
        }
    }
    
    // MARK: - UI Components
    
    private var swipeIndicator: some View {
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
        .transition(.scale.combined(with: .opacity))
    }
    
    private var saveConfirmation: some View {
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
        .animation(springAnimation, value: showSaveConfirmation)
    }
    
    private var errorOverlay: some View {
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
        .animation(springAnimation, value: showSaveError)
        .padding(.horizontal)
    }
    
    private var topNavigation: some View {
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
    }
    
    private func interactionButtons(for video: Video) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                profileButton(for: video)
                secondBrainButton(for: video)
                commentsButton(for: video)
                shareButton(for: video)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createDragGesture(for video: Video) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { gesture in
                withAnimation(springAnimation) {
                    dragOffset = max(0, gesture.translation.height)
                }
                if dragOffset > 50 {
                    performHapticFeedback(.light)
                }
            }
            .onEnded { gesture in
                withAnimation(springAnimation) {
                    if dragOffset > 100 {
                        Task {
                            performHapticFeedback(.medium)
                            await saveToSecondBrain(video: video)
                        }
                    }
                    dragOffset = 0
                }
            }
    }
    
    private func handleIndexChange(_ newValue: Int) {
        withAnimation(transitionAnimation) {
            viewModel.preloadAdjacentVideos(currentIndex: newValue)
            performHapticFeedback(.soft)
            
            if newValue >= viewModel.videos.count - 2 {
                Task {
                    print("🔄 VideoFeed: Preloading next batch of videos")
                    await viewModel.fetchNextBatch()
                }
            }
        }
    }
    
    // MARK: - Haptic Feedback
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            engine?.resetHandler = {
                LoggingService.debug("Restarting Haptic engine", component: "Haptics")
                do {
                    try engine?.start()
                } catch {
                    LoggingService.error("Failed to restart haptic engine: \(error.localizedDescription)", component: "Haptics")
                }
            }
            
            engine?.stoppedHandler = { reason in
                LoggingService.debug("Haptic engine stopped: \(reason)", component: "Haptics")
            }
            
        } catch {
            LoggingService.error("Failed to create haptic engine: \(error.localizedDescription)", component: "Haptics")
        }
    }
    
    private func performHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    // MARK: - Button Components
    
    private func profileButton(for video: Video) -> some View {
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
            .onAppear {
                print("Profile button rendered for video id: \(video.id) without plus overlay")
            }
        }
        .padding(.bottom, 10)
    }
    
    private func secondBrainButton(for video: Video) -> some View {
        VStack(spacing: 4) {
            Button(action: {
                if viewModel.playerViewModels[video.id] != nil {
                    Task {
                        await saveToSecondBrain(video: video)
                    }
                }
            }) {
                Image(systemName: viewModel.playerViewModels[video.id]?.isInSecondBrain == true ? "brain.head.profile.fill" : "brain.head.profile")
                    .foregroundColor(viewModel.playerViewModels[video.id]?.isInSecondBrain == true ? .green : .white)
                    .font(.system(size: 32))
            }
            Text(formatCount(video.saveCount))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private func commentsButton(for video: Video) -> some View {
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
    }
    
    private func shareButton(for video: Video) -> some View {
        VStack(spacing: 4) {
            Button {
                if let playerView = viewModel.playerViewModels[video.id] {
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
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
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
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    VideoFeedView()
} 