import SwiftUI
import Foundation
import FirebaseFirestore

struct CommentsView: View {
    let video: Video
    @StateObject private var viewModel: CommentsViewModel
    @FocusState private var isCommentFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: CommentsViewModel(video: video))
        LoggingService.debug("Initializing CommentsView for video: \(video.id)", component: "Comments")
    }
    
    var body: some View {
        ZStack {
            // Background blur and overlay
            Color.black.opacity(colorScheme == .dark ? 0.9 : 0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Comments")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    if !viewModel.isLoading {
                        Text("(\(viewModel.comments.count))")
                            .foregroundStyle(.secondary)
                            .font(.headline)
                            .accessibilityLabel("\(viewModel.comments.count) comments")
                    }
                    
                    Spacer()
                    
                    Button {
                        impactGenerator.impactOccurred(intensity: 0.6)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Close comments")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Informational text with icon
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                    Text("Tap the brain icon to save insights")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.15))
                .accessibilityElement(children: .combine)
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comments List with Loading and Empty States
                Group {
                    if viewModel.isLoading {
                        SharedLoadingView("Loading comments...")
                            .frame(maxHeight: .infinity)
                    } else if viewModel.comments.isEmpty {
                        EmptyCommentsView()
                            .frame(maxHeight: .infinity)
                    } else {
                        CommentsList(
                            comments: viewModel.comments,
                            onBrainTap: { comment in
                                impactGenerator.impactOccurred(intensity: 0.5)
                                Task {
                                    await viewModel.toggleSecondBrain(for: comment)
                                }
                            },
                            viewModel: viewModel
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comment Input
                CommentInputView(
                    text: $viewModel.newCommentText,
                    onSubmit: {
                        impactGenerator.impactOccurred(intensity: 0.7)
                        Task {
                            await viewModel.addComment()
                        }
                    }
                )
            }
            .background(Color(colorScheme == .dark ? .black : .systemBackground).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                notificationGenerator.notificationOccurred(.error)
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                notificationGenerator.prepare()
                impactGenerator.prepare()
            }
        }
    }
}

// MARK: - Supporting Views

private struct EmptyCommentsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce)
            Text("No comments yet")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Be the first to start the conversation!")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct CommentsList: View {
    let comments: [Comment]
    let onBrainTap: (Comment) -> Void
    @ObservedObject var viewModel: CommentsViewModel
    @State private var isRefreshing = false
    
    var body: some View {
        ScrollView {
            SharedRefreshControl(isRefreshing: $isRefreshing) {
                Task {
                    await viewModel.refreshComments()
                    isRefreshing = false
                }
            }
            
            LazyVStack(spacing: 16) {
                ForEach(comments) { comment in
                    CommentCell(comment: comment) {
                        onBrainTap(comment)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                if viewModel.hasMoreComments {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task {
                                await viewModel.loadMoreComments()
                            }
                        }
                }
            }
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityLabel("Comments list")
    }
}

private struct CommentInputView: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    let onSubmit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.secondary.opacity(0.2))
            
            // Input Area
            VStack(spacing: 16) {
                // Text Input
                TextField("Add a comment...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(colorScheme == .dark ? .systemGray6 : .systemGray6))
                    )
                    .focused($isFocused)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Comment input field")
                
                // Bottom Area with Home Indicator
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 134, height: 5)
                    .cornerRadius(2.5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

struct CommentCell: View {
    let comment: Comment
    let onBrainTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFullText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User Info
            HStack(spacing: 10) {
                if let imageURL = comment.userProfileImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 32))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName ?? "Anonymous")
                        .font(.footnote)
                        .fontWeight(.medium)
                    
                    Text(timeAgo(from: comment.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onBrainTap) {
                    Image(systemName: comment.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                        .foregroundColor(comment.isInSecondBrain ? .blue : .gray)
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            
            // Comment Text
            if comment.text.count > 150 && !showFullText {
                Text(comment.text.prefix(150) + "...")
                    .font(.callout)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullText = true
                        }
                    }
            } else {
                Text(comment.text)
                    .font(.callout)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture {
                        if comment.text.count > 150 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFullText = false
                            }
                        }
                    }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
        )
    }
    
    private func timeAgo(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        } else if let day = components.day, day > 0 {
            return "\(day)d"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }
}

#Preview {
    CommentsView(video: Video(
        id: "preview",
        ownerId: "user1",
        videoURL: "",
        thumbnailURL: "",
        title: "Test Video",
        tags: [],
        description: "Test Description",
        ownerUsername: "testUser"
    ))
} 