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
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)

                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.system(size: 24))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video \(fileId.prefix(8))")
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                            Text(state.statusMessage)
                                .font(.subheadline)
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
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        
                        // Processing Timeline
                        VStack(alignment: .leading, spacing: 12) {
                            TimelineStage(
                                icon: "arrow.up.circle.fill",
                                title: "Upload",
                                subtitle: "Uploading video to server",
                                isComplete: state.processingStatus != .uploading,
                                isCurrent: state.processingStatus == .uploading
                            )
                            
                            TimelineStage(
                                icon: "text.bubble.fill",
                                title: "Transcription",
                                subtitle: "Generating transcript with Whisper AI",
                                isComplete: state.processingStatus != .transcribing && state.transcript != nil,
                                isCurrent: state.processingStatus == .transcribing
                            )
                            
                            TimelineStage(
                                icon: "quote.bubble.fill",
                                title: "Quote Extraction",
                                subtitle: "Extracting meaningful quotes with GPT-4",
                                isComplete: state.processingStatus != .extractingQuotes && state.quotes != nil,
                                isCurrent: state.processingStatus == .extractingQuotes
                            )
                            
                            TimelineStage(
                                icon: "tag.fill",
                                title: "Metadata Generation",
                                subtitle: "Generating title, description, and tags",
                                isComplete: state.processingStatus == .ready,
                                isCurrent: state.processingStatus == .generatingMetadata
                            )
                        }
                        .padding(.vertical, 8)
                        
                        // Generated Content
                        if let transcript = state.transcript {
                            ContentSection(
                                title: "Generated Transcript",
                                content: transcript,
                                maxLines: 3
                            )
                        }
                        
                        if let quotes = state.quotes {
                            ContentSection(
                                title: "Extracted Quotes",
                                content: quotes.joined(separator: "\n• "),
                                prefix: "• ",
                                maxLines: 4
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                if state.processingStatus == .error {
                    Text("Upload failed. Please try again.")
                        .font(.subheadline)
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

    private struct TimelineStage: View {
        let icon: String
        let title: String
        let subtitle: String
        let isComplete: Bool
        let isCurrent: Bool
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isComplete ? .green : (isCurrent ? .blue : .gray))
                    .font(.system(size: 18))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isCurrent {
                    LoadingAnimation(message: nil)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
    
    private struct ContentSection: View {
        let title: String
        let content: String
        var prefix: String = ""
        var maxLines: Int = 3
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(prefix + content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(maxLines)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    VideoUploadView()
}