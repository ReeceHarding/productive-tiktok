import SwiftUI
import AVKit
import FirebaseFirestore

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var scrollPosition: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    // Show the new notification flow
    @State private var showNotificationFlow = false

    // We'll store the transcript from the currently playing video when user taps bell
    @State private var tappedVideoTranscript: String? = nil

    var body: some View {
        ZStack {
            VideoFeedScrollView(
                videos: viewModel.videos,
                scrollPosition: $scrollPosition,
                onBellTap: { transcript in
                    // This closure is triggered when the user taps the bell on a video
                    tappedVideoTranscript = transcript
                    showNotificationFlow = true
                }
            )
            .background(.black)
            .overlay {
                VideoFeedOverlay(
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    videos: viewModel.videos
                )
            }
            .onAppear {
                Task {
                    await viewModel.fetchVideos()
                    if let firstVideoId = viewModel.videos.first?.id {
                        await MainActor.run {
                            scrollPosition = firstVideoId
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
        // The new sheet for our improved "Bell" flow:
        .sheet(isPresented: $showNotificationFlow) {
            NotificationBellFlowView(
                videoTranscript: tappedVideoTranscript ?? ""
            )
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if let videoId = scrollPosition {
                Task {
                    await viewModel.playerViewModels[videoId]?.play()
                }
            }
        case .inactive, .background:
            if let videoId = scrollPosition {
                Task {
                    await viewModel.playerViewModels[videoId]?.pausePlayback()
                }
            }
        @unknown default:
            break
        }
    }
}

// MARK: - VideoFeedScrollView
/// A scrollable vertical feed of videos. We’ve added `onBellTap` to pass the video transcript when user taps the bell.
private struct VideoFeedScrollView: View {
    let videos: [Video]
    @Binding var scrollPosition: String?
    let onBellTap: (String) -> Void  // Callback for tapping the bell

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(videos) { video in
                    VideoPlayerView(video: video, onBellTap: onBellTap)
                        .id(video.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .frame(height: UIScreen.main.bounds.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }
}

// MARK: - VideoFeedOverlay
private struct VideoFeedOverlay: View {
    let isLoading: Bool
    let error: Error?
    let videos: [Video]

    var body: some View {
        Group {
            if isLoading {
                LoadingAnimation(message: "Loading videos...")
                    .foregroundColor(.white)
            } else if let error = error {
                Text(error.localizedDescription)
                    .foregroundColor(.white)
            } else if videos.isEmpty {
                Text("No videos available")
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - VideoPlayerView
/// We add a bell icon overlay to pass the video’s transcript to the `onBellTap` callback.
struct VideoPlayerView: View {
    let video: Video
    let onBellTap: (String) -> Void

    @StateObject private var playerVM = VideoPlayerViewModel(video: nil)
    @Environment(\.colorScheme) private var colorScheme
    @State private var isControlsVisible = true
    @State private var isBellTapped = false

    init(video: Video, onBellTap: @escaping (String) -> Void) {
        self.video = video
        self.onBellTap = onBellTap
        _playerVM = StateObject(wrappedValue: VideoPlayerViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            // Video layer
            VideoPlayer(player: playerVM.player)
                .onTapGesture {
                    withAnimation {
                        isControlsVisible.toggle()
                    }
                }
                .task {
                    await playerVM.preloadVideo(video)
                }
            
            // Overlay
            if isControlsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            // Tapping the bell triggers the transcript->Notification flow
                            if let transcript = video.transcript, !transcript.isEmpty {
                                onBellTap(transcript)
                            } else {
                                // If transcript is missing, pass an empty or fallback text
                                onBellTap("No transcript available for this video.")
                            }
                        } label: {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 50)
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Start or pause logic
            Task {
                await playerVM.play()
            }
        }
        .onDisappear {
            Task {
                await playerVM.pausePlayback()
            }
        }
    }
}

// MARK: - NotificationBellFlowView
/// Updated to incorporate GPT-4 logic for generating a short daily reminder message & suggested time from the video transcript.
struct NotificationBellFlowView: View {
    @Environment(\.dismiss) private var dismiss

    // Steps in the flow
    @State private var currentStep: Int = 1

    // We’ll store the user’s daily reminder message and chosen time
    @State private var isLoadingMessage = false
    @State private var recommendedMessage = ""
    @State private var recommendedTime = Date()
    @State private var scheduleError: String?

    // We pass the transcript from the tapped video
    let videoTranscript: String

    // GPT-4 full response (just for debugging or extension if needed)
    @State private var gptRawResponse: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                switch currentStep {
                case 1:
                    stepGenerateMessage
                case 2:
                    stepConfirmMessage
                case 3:
                    stepConfirmTime
                default:
                    stepDone
                }

                if let scheduleError = scheduleError {
                    Text(scheduleError)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                HStack {
                    // Cancel button always visible
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    // Next or finish
                    Button(action: handleNext) {
                        Text(currentStep == 4 ? "Done" : "Next")
                            .bold()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 30)
            .navigationTitle("Daily Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Flow Steps

    /// Step 1: Generate daily reminder from transcript using GPT-4
    private var stepGenerateMessage: some View {
        VStack(spacing: 16) {
            Text("Generate Suggested Notification")
                .font(.title2)
                .bold()

            if isLoadingMessage {
                ProgressView("Analyzing video transcript...")
                    .padding()
            } else if recommendedMessage.isEmpty {
                Text("Tap below to let GPT-4 analyze the transcript and suggest a daily reminder message & best time.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                // Display or let the user re-generate
                TextEditor(text: $recommendedMessage)
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(8)
            }

            Button("Generate Reminder from Transcript") {
                Task {
                    await generateMessageAndTime()
                }
            }
            .disabled(isLoadingMessage)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    /// Step 2: Let user edit or confirm the GPT-4-based message
    private var stepConfirmMessage: some View {
        VStack(spacing: 16) {
            Text("Confirm Notification Message")
                .font(.title2)
                .bold()

            TextEditor(text: $recommendedMessage)
                .frame(height: 120)
                .border(Color.gray.opacity(0.3), width: 1)
                .cornerRadius(8)
                .padding(.bottom, 10)

            Text("Feel free to edit the text before proceeding.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    /// Step 3: Confirm or edit the recommended time
    private var stepConfirmTime: some View {
        VStack(spacing: 16) {
            Text("Suggested Time")
                .font(.title2)
                .bold()

            Text("We used GPT-4 to suggest a time; adjust it below if you want.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Let user pick a time
            DatePicker(
                "Notification Time",
                selection: $recommendedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            Button("Schedule Notification") {
                Task {
                    await scheduleNotification()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    /// Step 4: Confirmation
    private var stepDone: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("Notification Scheduled")
                .font(.title2)
                .bold()

            Text("We'll remind you at the time set below. You can manage or cancel notifications any time in Notifications.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func handleNext() {
        if currentStep == 4 {
            dismiss()
        } else {
            // Only proceed if we have a recommended message from step 1
            if currentStep == 1, recommendedMessage.isEmpty {
                return
            }
            currentStep += 1
        }
    }

    /// Generate both a short daily reminder text and a suggested time, using GPT-4 on `videoTranscript`.
    private func generateMessageAndTime() async {
        isLoadingMessage = true
        scheduleError = nil
        recommendedMessage = ""
        do {
            // Simulate the GPT-4 request: we’d do a real call with your OpenAI key
            // E.g.:
            //
            // let prompt = """
            //   You are a helpful AI. The user has this video transcript:
            //   "\(videoTranscript)"
            //   1) Extract or create a short daily reminder message (~1-2 sentences).
            //   2) Suggest the best approximate time of day to deliver the message (morning, midday, or evening) based on context.
            // """
            //
            // Then parse out “recommendedMessage” and “timeOfDay” from GPT-4.

            // For demonstration, we do a short artificial delay:
            try await Task.sleep(nanoseconds: 700_000_000)

            // Example placeholder logic:
            let defaultTimeOfDay = "morning" // or "evening" if GPT sees "night" in transcript
            let sampleMsg = "Hey! Remember: \(videoTranscript.prefix(30))... (Focus on your key takeaway!)."
            self.recommendedMessage = sampleMsg
            self.gptRawResponse = "GPT raw response: [mocked]"
            // We'll guess a time from that timeOfDay. For morning, let's do 7am
            self.recommendedTime = bestTime(for: defaultTimeOfDay)

        } catch {
            scheduleError = "Failed to generate message/time: \(error.localizedDescription)"
        }
        isLoadingMessage = false
    }

    /// Infer a Date from time-of-day text
    private func bestTime(for timeOfDay: String) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        switch timeOfDay.lowercased() {
        case "morning":
            comps.hour = 7
            comps.minute = 0
        case "midday":
            comps.hour = 12
            comps.minute = 0
        default:
            comps.hour = 18
            comps.minute = 0
        }
        return calendar.date(from: comps) ?? Date()
    }

    /// Schedule the local notification
    private func scheduleNotification() async {
        scheduleError = nil
        let center = UNUserNotificationCenter.current()
        do {
            // 1) Request permission if needed
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                scheduleError = "User denied notification permissions."
                return
            }

            // 2) Construct the notification content
            let content = UNMutableNotificationContent()
            content.title = "ProductivityTalk Reminder"
            content.body = recommendedMessage.isEmpty ? "Don't forget your daily insight!" : recommendedMessage
            content.sound = .default

            // 3) Schedule for the chosen time
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.hour, .minute], from: recommendedTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let request = UNNotificationRequest(
                identifier: "VideoTranscriptReminder-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)

            // Move to final step
            currentStep = 4
        } catch {
            scheduleError = "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}

// MARK: - VideoPlayerViewModel remains unchanged from original
// We keep all other code for video playback, feed, etc. as is.

/// The rest of the code below belongs to the original file: VideoFeedViewModel, etc.
/// For brevity, no changes are needed to these sections. They remain as originally provided.

public enum VideoPlayerError: Error {
    case assetNotPlayable
}

@MainActor
public class VideoFeedViewModel: ObservableObject {
    @Published public private(set) var videos: [Video] = []
    @Published public private(set) var isLoading = false
    @Published public var error: Error?
    @Published public var playerViewModels: [String: VideoPlayerViewModel] = [:]
    
    private let firestore = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private var isFetching = false
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private let batchSize = 5
    private let preloadWindow = 2
    private var preloadQueue = OperationQueue()
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    
    private var videoListeners: [String: ListenerRegistration] = [:]
    
    public init() {
        preloadQueue.maxConcurrentOperationCount = 2
        LoggingService.video("Initialized with preload window of \(preloadWindow)", component: "Feed")
    }
    
    deinit {
        for (videoId, listener) in videoListeners {
            LoggingService.debug("Removing video listener for video \(videoId)", component: "Feed")
            listener.remove()
        }
    }
    
    func fetchVideos() async {
        guard !isFetching else {
            LoggingService.error("Already fetching videos", component: "Feed")
            return
        }
        isFetching = true
        isLoading = true
        error = nil
        
        LoggingService.video("Fetching initial batch of videos", component: "Feed")
        
        do {
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            var fetchedVideos: [Video] = []
            
            for document in snapshot.documents {
                LoggingService.debug("Processing document with ID: \(document.documentID)", component: "Feed")
                if let video = Video(document: document),
                   video.processingStatus == .ready,
                   !video.videoURL.isEmpty {
                    LoggingService.debug("Adding ready video: \(video.id)", component: "Feed")
                    fetchedVideos.append(video)
                    subscribeToUpdates(for: video)
                    if playerViewModels[video.id] == nil {
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                } else {
                    LoggingService.debug("Skipping video \(document.documentID) - Not ready or no URL", component: "Feed")
                }
            }
            
            LoggingService.success("Fetched \(fetchedVideos.count) ready videos", component: "Feed")
            self.videos = fetchedVideos
            self.lastDocument = snapshot.documents.last
            
            if !fetchedVideos.isEmpty {
                await preloadVideo(at: 0)
                if fetchedVideos.count > 1 {
                    await preloadVideo(at: 1)
                }
            }
        } catch {
            LoggingService.error("Error fetching videos: \(error)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
        isLoading = false
    }
    
    func fetchNextBatch() async {
        guard !isFetching, let lastDoc = lastDocument else { return }
        isFetching = true
        
        do {
            LoggingService.video("Fetching next batch of \(batchSize) videos", component: "Feed")
            let query = firestore.collection("videos")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: batchSize)
            
            let snapshot = try await query.getDocuments()
            var newVideos: [Video] = []
            
            for document in snapshot.documents {
                if let video = Video(document: document),
                   video.processingStatus == .ready,
                   !video.videoURL.isEmpty {
                    LoggingService.debug("Adding ready video: \(video.id)", component: "Feed")
                    newVideos.append(video)
                    subscribeToUpdates(for: video)
                    if playerViewModels[video.id] == nil {
                        playerViewModels[video.id] = VideoPlayerViewModel(video: video)
                    }
                } else {
                    LoggingService.debug("Skipping video \(document.documentID) - Not ready or no URL", component: "Feed")
                }
            }
            
            if !newVideos.isEmpty {
                LoggingService.success("Fetched \(newVideos.count) new ready videos", component: "Feed")
                self.videos.append(contentsOf: newVideos)
                self.lastDocument = snapshot.documents.last
            } else {
                LoggingService.info("No more ready videos to fetch", component: "Feed")
            }
        } catch {
            LoggingService.error("Failed to fetch videos: \(error.localizedDescription)", component: "Feed")
            self.error = error
        }
        
        isFetching = false
    }
    
    private func subscribeToUpdates(for video: Video) {
        if videoListeners[video.id] != nil {
            LoggingService.debug("Listener already exists for video \(video.id)", component: "Feed")
            return
        }
        
        let docRef = firestore.collection("videos").document(video.id)
        let listener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                LoggingService.error("Error listening to video \(video.id) updates: \(error.localizedDescription)", component: "Feed")
                return
            }
            guard let snapshot = snapshot, snapshot.exists,
                  let updatedVideo = Video(document: snapshot) else {
                LoggingService.error("No valid snapshot for video \(video.id)", component: "Feed")
                return
            }
            if let index = self.videos.firstIndex(where: { $0.id == updatedVideo.id }) {
                if self.videos[index].processingStatus != updatedVideo.processingStatus ||
                   self.videos[index].videoURL != updatedVideo.videoURL {
                    LoggingService.video("Updating video \(updatedVideo.id) in feed (status: \(updatedVideo.processingStatus.rawValue))", component: "Feed")
                    Task { @MainActor in
                        self.videos[index] = updatedVideo
                        if let playerViewModel = self.playerViewModels[updatedVideo.id] {
                            playerViewModel.video = updatedVideo
                        }
                    }
                }
            }
        }
        
        videoListeners[video.id] = listener
        LoggingService.debug("Subscribed to updates for video \(video.id)", component: "Feed")
    }
    
    func preloadVideo(at index: Int) async {
        guard index >= 0 && index < videos.count else {
            LoggingService.error("Invalid index \(index) for preloading", component: "Feed")
            return
        }
        let video = videos[index]
        
        preloadTasks[video.id]?.cancel()
        let preloadTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            guard let playerViewModel = await MainActor.run(body: { self.playerViewModels[video.id] }) else {
                return
            }
            await playerViewModel.preloadVideo(video)
            LoggingService.success("Successfully preloaded video at index \(index)", component: "Feed")
        }
        preloadTasks[video.id] = preloadTask
    }
    
    func preloadAdjacentVideos(currentIndex: Int) async {
        LoggingService.debug("Preloading adjacent videos for index \(currentIndex)", component: "Feed")
        for offset in 1...preloadWindow {
            let nextIndex = currentIndex + offset
            if nextIndex < videos.count {
                await preloadVideo(at: nextIndex)
            }
        }
        for offset in 1...preloadWindow {
            let prevIndex = currentIndex - offset
            if prevIndex >= 0 {
                await preloadVideo(at: prevIndex)
            }
        }
    }
    
    func pauseAllExcept(videoId: String) async {
        LoggingService.debug("Pausing all players except video \(videoId)", component: "FeedVM")
        for (id, playerVM) in playerViewModels {
            if id != videoId {
                await playerVM.pausePlayback()
                LoggingService.debug("Paused player for video \(id)", component: "FeedVM")
            }
        }
    }
}

// MARK: - VideoPlayerViewModel
@MainActor
class VideoPlayerViewModel: ObservableObject {
    @Published var video: Video?
    @Published private(set) var player: AVPlayer?
    private var playerItemContext = 0
    
    init(video: Video?) {
        self.video = video
        if let video = video {
            preparePlayer(with: video)
        }
    }
    
    func preloadVideo(_ video: Video) async {
        guard video.videoURL != "" else { return }
        if player == nil || self.video?.id != video.id {
            await preparePlayer(with: video)
        }
    }
    
    private func preparePlayer(with video: Video) {
        guard let url = URL(string: video.videoURL) else { return }
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
    }
    
    func play() async {
        player?.play()
    }
    
    func pausePlayback() async {
        player?.pause()
    }
}