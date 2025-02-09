import SwiftUI
import Foundation
import FirebaseFirestore

struct CommentsView: View {
    let video: Video
    @StateObject private var viewModel: CommentsViewModel
    @FocusState private var isCommentFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: CommentsViewModel(video: video))
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Comments")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !viewModel.isLoading {
                        Text("(\(viewModel.comments.count))")
                            .foregroundStyle(.secondary)
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Informational text with icon
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                    Text("Tap the brain icon to save insights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comments List with Loading and Empty States
                Group {
                    if viewModel.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading comments...")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.comments.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No comments yet")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Be the first to start the conversation!")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(viewModel.comments) { comment in
                                    CommentCell(comment: comment) {
                                        Task {
                                            await viewModel.toggleSecondBrain(for: comment)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comment Input
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        TextField("Add a comment...", text: $viewModel.newCommentText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemBackground))
                            )
                            .focused($isCommentFieldFocused)
                            .frame(maxHeight: 100)
                        
                        Button {
                            Task {
                                await viewModel.addComment()
                                isCommentFieldFocused = false
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .disabled(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if !viewModel.newCommentText.isEmpty {
                        Text("\(viewModel.newCommentText.count)/1000")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground).opacity(0.8))
            }
        }
        .background(Color(.secondarySystemBackground))
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
    }
}

struct CommentCell: View {
    let comment: Comment
    let onBrainTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFullText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // User Info
            HStack(spacing: 12) {
                if let imageURL = comment.userProfileImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.userName ?? "Anonymous")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(timeAgo(from: comment.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onBrainTap) {
                    Image(systemName: comment.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                        .foregroundColor(comment.isInSecondBrain ? .blue : .gray)
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
            }
            
            // Comment Text
            if comment.text.count > 150 && !showFullText {
                Text(comment.text.prefix(150) + "...")
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullText = true
                        }
                    }
            } else {
                Text(comment.text)
                    .font(.body)
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                       radius: 10, x: 0, y: 4)
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