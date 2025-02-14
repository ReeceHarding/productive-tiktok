import SwiftUI
import PhotosUI
import AVFoundation
import FirebaseStorage
import FirebaseFirestore

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @StateObject private var managementViewModel = VideoManagementViewModel()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: VideoUploadViewModel? = nil) {
        let vm = viewModel ?? VideoUploadViewModel()
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Dashboard header
                    dashboardHeader
                    // Stats overview
                    if managementViewModel.isLoading {
                        LoadingAnimation(message: "Loading Dashboard...")
                            .padding()
                    } else {
                        statsGrid
                    }
                    // Upload Section
                    uploadSection
                    // Previously uploaded videos
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
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
                Task {
                    await managementViewModel.loadVideos()
                }
            }
        }
        .onChange(of: viewModel.selectedItems) { newValue in
            if !newValue.isEmpty {
                Task {
                    await viewModel.loadVideos()
                }
            }
        }
    }
    
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

    private var statsGrid: some View {
        let stats = managementViewModel.statistics
        return VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    title: "Total Videos",
                    value: "\(stats.totalVideos)",
                    iconName: "film"
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

    private var uploadSection: some View {
        VStack(spacing: 20) {
            PhotosPicker(
                selection: $viewModel.selectedItems,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    if viewModel.uploadStates.isEmpty {
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
                .frame(height: viewModel.uploadStates.isEmpty ? 150 : 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .foregroundColor(.blue.opacity(0.3))
                )
                .padding(.horizontal, 20)
            }
            
            if !viewModel.uploadStates.isEmpty {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.uploadStates.keys), id: \.self) { id in
                        if let state = viewModel.uploadStates[id] {
                            UploadProgressRow(fileId: id, state: state)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
    }

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
                LoadingAnimation(message: "Loading videos...")
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

extension VideoUploadView {
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

    private struct UploadProgressRow: View {
        let fileId: String
        let state: VideoUploadViewModel.UploadState

        var body: some View {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // no thumbnail for now
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)

                        Image(systemName: "video.fill")
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video \(fileId.prefix(8))")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                            Text(state.statusMessage)
                                .font(.caption)
                                .foregroundColor(statusColor)
                        }

                        if !state.isComplete && state.processingStatus != .error {
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
                        }
                    }
                    Spacer()
                }
                
                // Processing Stages
                if state.processingStatus != .error {
                    VStack(alignment: .leading, spacing: 8) {
                        if !state.isComplete {
                            HStack(spacing: 4) {
                                LoadingAnimation(message: nil)
                                    .frame(width: 24, height: 24)
                                Text(processingStageMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        
                        // Transcript
                        if let transcript = state.transcript,
                           state.processingStatus == .extractingQuotes
                           || state.processingStatus == .generatingMetadata
                           || state.processingStatus == .ready {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Generated Transcript")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(transcript)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Quotes
                        if let quotes = state.quotes, !quotes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Extracted Quotes")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                ForEach(quotes.prefix(3), id: \.self) { quote in
                                    Text("• \(quote)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if quotes.count > 3 {
                                    Text("+ \(quotes.count - 3) more quotes")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                
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
        
        private var statusIcon: String {
            switch state.processingStatus {
            case .uploading:
                return "arrow.up.circle"
            case .transcribing:
                return "text.bubble"
            case .extractingQuotes:
                return "quote.bubble"
            case .generatingMetadata, .processing:
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
            case .transcribing, .extractingQuotes, .generatingMetadata, .processing:
                return .orange
            case .ready:
                return .green
            case .error:
                return .red
            }
        }
        
        private var progressColor: Color {
            statusColor
        }
        
        private var processingStageMessage: String {
            switch state.processingStatus {
            case .uploading:
                return "Uploading video to server..."
            case .transcribing:
                return "Generating transcript using Whisper AI..."
            case .extractingQuotes:
                return "Extracting meaningful quotes using GPT-4..."
            case .generatingMetadata:
                return "Generating title, description, and tags..."
            case .processing:
                return "Processing video..."
            case .ready:
                return "Processing complete"
            case .error:
                return "Processing failed"
            }
        }
    }

    private struct VideoRow: View {
        let video: Video
        let onDelete: () -> Void

        @State private var showComments = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Row top
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
                        Image(systemName: "video.fill")
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title.isEmpty ? "Untitled" : video.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                HStack(spacing: 12) {
                    StatLabel(count: video.saveCount, icon: "bookmark.fill", label: "Saves")
                    StatLabel(count: video.commentCount, icon: "text.bubble.fill", label: "Comments")
                }
                .padding(.horizontal, 12)

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
                CommentsView(video: video)
            }
        }
        
        private var statusColor: Color {
            switch video.processingStatus {
            case .uploading, .transcribing, .extractingQuotes, .generatingMetadata, .processing:
                return .orange
            case .ready:
                return .green
            case .error:
                return .red
            }
        }
        
        private var statusText: String {
            switch video.processingStatus {
            case .uploading:
                return "Uploading..."
            case .transcribing:
                return "Transcribing..."
            case .extractingQuotes:
                return "Extracting Quotes..."
            case .generatingMetadata:
                return "Generating Metadata..."
            case .processing:
                return "Processing..."
            case .ready:
                return "Ready"
            case .error:
                return "Error"
            }
        }
        
        private var engagementRate: String {
            let totalEngagements = video.saveCount + video.commentCount + video.brainCount
            let rate = Double(totalEngagements) * 100
            return String(format: "%.1f", rate)
        }
    }
    
    private struct StatLabel: View {
        let count: Int
        let icon: String
        let label: String
        
        @State private var showTooltip = false
        
        var body: some View {
            Label("\(count)", systemImage: icon)
                .font(.footnote)
                .foregroundColor(.secondary)
                .onTapGesture {
                    showTooltip.toggle()
                }
                .popover(isPresented: $showTooltip) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(.headline)
                        Text("Total \(label.lowercased()): \(count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
        }
    }
}

#Preview {
    VideoUploadView()
}