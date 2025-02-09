import SwiftUI

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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comments")
                    .font(.title3)
                    .fontWeight(.bold)
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
            
            // Informational text
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.secondary)
                Text("Tap the brain icon to save comments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.secondary.opacity(0.2))
            
            // Comments List
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.comments) { comment in
                        CommentCell(comment: comment) {
                            Task {
                                await viewModel.toggleSecondBrain(for: comment)
                            }
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }
                }
                .padding(.vertical)
            }
            
            Divider()
                .background(Color.secondary.opacity(0.2))
            
            // Comment Input
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Add a comment...", text: $viewModel.newCommentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
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
                        .font(.title2)
                        .foregroundColor(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
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
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName ?? "Anonymous")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(timeAgo(from: comment.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Comment Text and Brain Button in same row
            HStack(alignment: .top, spacing: 12) {
                Text(comment.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 4)
                
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
            return "\(year)y ago"
        } else if let month = components.month, month > 0 {
            return "\(month)mo ago"
        } else if let day = components.day, day > 0 {
            return "\(day)d ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m ago"
        } else {
            return "just now"
        }
    }
}

#if DEBUG
struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleVideo = Video(
            id: "preview",
            ownerId: "user123",
            videoURL: "sample.mp4",
            thumbnailURL: "thumbnail.jpg",
            title: "Sample Video",
            tags: ["preview"],
            description: "This is a sample video for preview",
            ownerUsername: "previewUser"
        )
        
        CommentsView(video: sampleVideo)
    }
}
#endif 