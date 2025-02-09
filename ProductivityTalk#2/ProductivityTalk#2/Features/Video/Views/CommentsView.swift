import SwiftUI
import UIKit
// Import models
@_implementationOnly import ProductivityTalk_2

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
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Informational text with icon
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.secondary)
                    Text("Tap the brain icon to save insights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comments List with Loading and Empty States
                Group {
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading comments...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.comments.isEmpty {
                        VStack(spacing: 16) {
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
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.comments) { comment in
                                    CommentCell(comment: comment) {
                                        Task {
                                            await viewModel.toggleSecondBrain(for: comment)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                }
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                // Comment Input
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Add a comment...", text: $viewModel.newCommentText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(UIColor.systemBackground))
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
                    
                    // Character count
                    if !viewModel.newCommentText.isEmpty {
                        Text("\(viewModel.newCommentText.count)/1000")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
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
        VStack(alignment: .leading, spacing: 12) {
            // User Info
            HStack(spacing: 8) {
                if let imageURL = comment.userProfileImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 36))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName ?? "Anonymous")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(timeAgo(from: comment.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Comment Text and Brain Button
            HStack(alignment: .top, spacing: 12) {
                if comment.text.count > 150 && !showFullText {
                    Text(comment.text.prefix(150) + "...")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            withAnimation {
                                showFullText = true
                            }
                        }
                } else {
                    Text(comment.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            if comment.text.count > 150 {
                                withAnimation {
                                    showFullText = false
                                }
                            }
                        }
                }
                
                Spacer(minLength: 16)
                
                Button(action: onBrainTap) {
                    Image(systemName: comment.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                        .foregroundColor(comment.isInSecondBrain ? .blue : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                       radius: 8, x: 0, y: 2)
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