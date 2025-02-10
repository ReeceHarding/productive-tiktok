import SwiftUI
import PhotosUI
import AVKit

@MainActor
struct VideoUploadView: View {
    // ViewModel for uploading videos
    @StateObject private var uploadViewModel: VideoUploadViewModel
    // ViewModel for managing existing videos and stats
    @StateObject private var managementViewModel = VideoManagementViewModel()

    // Controls error handling and sheet presentations
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: VideoUploadViewModel? = nil) {
        // If provided with a custom VM, use it; otherwise create a new instance
        let vm = viewModel ?? VideoUploadViewModel()
        _uploadViewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: - Dashboard Header
                    dashboardHeader

                    // MARK: - Statistics Overview
                    if managementViewModel.isLoading {
                        ProgressView("Loading Dashboard...")
                            .padding()
                    } else {
                        statsGrid
                    }

                    // MARK: - Upload Section
                    uploadSection

                    // MARK: - Previously Uploaded Videos
                    uploadedVideosList
                }
                .padding(.vertical)
            }
            .navigationTitle("Video Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            // Alert handling
            .alert("Error", isPresented: $uploadViewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadViewModel.errorMessage ?? "An unknown error occurred")
            }
            .alert("Management Error", isPresented: .constant(managementViewModel.error != nil)) {
                Button("OK", role: .cancel) {
                    managementViewModel.error = nil
                }
            } message: {
                if let error = managementViewModel.error {
                    Text(error)
                }
            }
            .onAppear {
                // Load existing videos once this screen appears
                Task {
                    await managementViewModel.loadVideos()
                }
            }
        }
        .onChange(of: uploadViewModel.selectedItems) { newValue in
            if !newValue.isEmpty {
                Task {
                    await uploadViewModel.loadVideos()
                }
            }
        }
    }
}

// MARK: - Subviews
extension VideoUploadView {
    
    // Dashboard Title
    private var dashboardHeader: some View {
        VStack(spacing: 8) {
            Text("Manage & Upload Videos")
                .font(.largeTitle)
                .bold()
            Text("Oversee your existing videos, upload new ones, and monitor key stats.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 16)
    }

    // Grid of stats from managementViewModel.statistics
    private var statsGrid: some View {
        let stats = managementViewModel.statistics
        // We'll present them in two columns
        return VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    title: "Total Videos",
                    value: "\(stats.totalVideos)",
                    iconName: "film"
                )
                StatCard(
                    title: "Total Views",
                    value: "\(stats.totalViews)",
                    iconName: "eye.fill"
                )
                StatCard(
                    title: "Total Likes",
                    value: "\(stats.totalLikes)",
                    iconName: "hand.thumbsup.fill"
                )
                StatCard(
                    title: "Comments",
                    value: "\(stats.totalComments)",
                    iconName: "text.bubble.fill"
                )
                StatCard(
                    title: "Saves",
                    value: "\(stats.totalSaves)",
                    iconName: "bookmark.fill"
                )
                StatCard(
                    title: "Engagement",
                    value: String(format: "%.1f%%", stats.engagementRate * 100),
                    iconName: "chart.line.uptrend.xyaxis"
                )
            }
        }
        .padding(.horizontal)
    }

    // Upload Section
    private var uploadSection: some View {
        VStack(spacing: 20) {
            // Upload selection area
            PhotosPicker(
                selection: $uploadViewModel.selectedItems,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    if uploadViewModel.uploadStates.isEmpty {
                        Text("Tap to Upload Videos")
                            .font(.headline)
                        Text("Select one or more videos to upload.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Add More Videos")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: uploadViewModel.uploadStates.isEmpty ? 150 : 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .foregroundColor(.blue.opacity(0.3))
                )
                .padding(.horizontal, 20)
            }

            // Upload progress list
            if !uploadViewModel.uploadStates.isEmpty {
                VStack(spacing: 12) {
                    ForEach(Array(uploadViewModel.uploadStates.keys), id: \.self) { id in
                        if let state = uploadViewModel.uploadStates[id] {
                            UploadProgressRow(fileId: id, state: state)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
    }

    // List of previously uploaded videos
    private var uploadedVideosList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Uploaded Videos")
                    .font(.title3)
                    .bold()
                Spacer()
                Text("\(managementViewModel.videos.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            if managementViewModel.isLoading {
                ProgressView("Loading videos...")
                    .padding()
            } else if managementViewModel.videos.isEmpty {
                Text("No videos uploaded yet.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 16) {
                    ForEach(managementViewModel.videos, id: \.id) { video in
                        VideoRow(
                            video: video,
                            onDelete: { Task { await managementViewModel.deleteVideo(video) } }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .systemBackground).opacity(0.8))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 32)
    }
}

// MARK: - Helper Views
extension VideoUploadView {

    /// A reusable card for showing stats in a 2-column layout
    private struct StatCard: View {
        let title: String
        let value: String
        let iconName: String

        var body: some View {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(.blue)
                    Spacer()
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.systemBackground).opacity(0.8))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
    }

    /// A row displaying upload progress or completion status for a single video upload
    private struct UploadProgressRow: View {
        let fileId: String
        let state: VideoUploadViewModel.UploadState

        var body: some View {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if let thumbnail = state.thumbnailImage {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 60)

                            Image(systemName: "video.fill")
                                .foregroundColor(.gray)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // Title and ID
                        Text("Video \(fileId.prefix(8))")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        // Status Message with Icon
                        HStack(spacing: 4) {
                            // Dynamic icon based on status
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                            Text(state.statusMessage)
                                .font(.caption)
                                .foregroundColor(statusColor)
                        }

                        // Progress Section
                        if !state.isComplete && state.processingStatus != .error {
                            VStack(alignment: .leading, spacing: 4) {
                                // Progress Bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: geometry.size.width, height: 6)
                                            .cornerRadius(3)
                                        
                                        Rectangle()
                                            .fill(progressColor)
                                            .frame(width: geometry.size.width * CGFloat(state.progress), height: 6)
                                            .cornerRadius(3)
                                    }
                                }
                                .frame(height: 6)
                                
                                // Percentage and Size
                                HStack {
                                    if state.progress > 0 && state.progress < 1 {
                                        Text("\(Int(state.progress * 100))%")
                                            .font(.caption)
                                            .foregroundColor(progressColor)
                                            .bold()
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
                
                // Error Message if any
                if state.processingStatus == .error {
                    Text("Upload failed. Please try again.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .systemBackground).opacity(0.8))
                    .shadow(radius: 2)
            )
        }
        
        // Helper computed properties for UI
        private var statusIcon: String {
            switch state.processingStatus {
            case .uploading:
                return "arrow.up.circle"
            case .processing:
                return "gear.circle"
            case .ready:
                return "checkmark.circle.fill"
            case .error:
                return "exclamationmark.circle.fill"
            }
        }
        
        private var statusColor: Color {
            switch state.processingStatus {
            case .uploading:
                return .blue
            case .processing:
                return .orange
            case .ready:
                return .green
            case .error:
                return .red
            }
        }
        
        private var progressColor: Color {
            switch state.processingStatus {
            case .uploading:
                return .blue
            case .processing:
                return .orange
            case .ready:
                return .green
            case .error:
                return .red
            }
        }
    }

    /// A row for each previously uploaded video in the user's library
    private struct VideoRow: View {
        let video: Video
        let onDelete: () -> Void

        @State private var showComments = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Row top: thumbnail + basic info
                HStack(alignment: .center, spacing: 12) {
                    thumbnailView
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text("Comments: \(video.commentCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                // Row bottom: actions
                HStack(spacing: 16) {
                    Button(action: { showComments = true }) {
                        Label("View Comments", systemImage: "text.bubble")
                            .font(.subheadline)
                    }

                    Spacer()

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .sheet(isPresented: $showComments) {
                // Present the CommentsView
                CommentsView(video: video)
            }
        }

        @ViewBuilder
        private var thumbnailView: some View {
            if let urlString = video.thumbnailURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "video.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    VideoUploadView()
} 