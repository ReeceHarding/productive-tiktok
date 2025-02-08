import SwiftUI

struct CommentsView: View {
    let video: Video
    @StateObject private var viewModel: CommentsViewModel
    @State private var newCommentText = ""
    @State private var showSecondBrainConfirmation = false
    @State private var selectedCommentId: String?
    @Environment(\.dismiss) private var dismiss
    
    init(video: Video) {
        self.video = video
        self._viewModel = StateObject(wrappedValue: CommentsViewModel(video: video))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.secondary.opacity(0.1)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Comments List
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.comments) { comment in
                                CommentCell(
                                    comment: comment,
                                    onSecondBrainTap: {
                                        selectedCommentId = comment.id
                                        Task {
                                            await viewModel.toggleSecondBrain(for: comment)
                                            showSecondBrainConfirmation = true
                                        }
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    
                    // Comment Input
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            TextField("Add a comment...", text: $newCommentText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button {
                                guard !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                
                                Task {
                                    await viewModel.addComment(text: newCommentText)
                                    newCommentText = ""
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                    .background(Color.white)
                }
                
                // Loading State
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
                
                // Second Brain Confirmation
                if showSecondBrainConfirmation {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Added to Second Brain!")
                            .font(.headline)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
            .onChange(of: showSecondBrainConfirmation) { _, newValue in
                if newValue {
                    // Auto-hide the confirmation after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSecondBrainConfirmation = false
                            selectedCommentId = nil
                        }
                    }
                }
            }
            .task {
                await viewModel.loadComments()
            }
        }
    }
}

// MARK: - Comment Cell
struct CommentCell: View {
    let comment: Comment
    let onSecondBrainTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile Picture
            AsyncImage(url: URL(string: comment.userProfilePicURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                // Username and Time
                HStack {
                    Text("@\(comment.userUsername)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("•")
                    
                    Text(comment.createdAt, style: .relative)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Comment Text
                Text(comment.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Second Brain Button
            VStack(spacing: 4) {
                Button(action: onSecondBrainTap) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(comment.secondBrainCount > 0 ? .green : .gray)
                }
                
                Text("\(comment.secondBrainCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
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