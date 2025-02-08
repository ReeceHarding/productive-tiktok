import SwiftUI

struct CommentsView: View {
    let video: Video
    @StateObject private var viewModel: CommentsViewModel
    @FocusState private var isCommentFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: CommentsViewModel(video: video))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Button {
                    // Dismiss sheet
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding()
            
            Divider()
            
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
            
            // Comment Input
            HStack(spacing: 12) {
                TextField("Add a comment...", text: $viewModel.newCommentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User Info
            HStack {
                if let imageURL = comment.userProfileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
                
                Text(comment.userName ?? "Anonymous")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("•")
                    .foregroundColor(.gray)
                
                Text(timeAgo(from: comment.timestamp))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Comment Text
            Text(comment.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Second Brain Button
            HStack {
                Spacer()
                Button(action: onBrainTap) {
                    Image(systemName: comment.isInSecondBrain ? "brain.head.profile.fill" : "brain.head.profile")
                        .foregroundColor(comment.isInSecondBrain ? .blue : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
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