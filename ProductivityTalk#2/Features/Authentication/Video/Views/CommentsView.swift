import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

/// A simple comment view that loads comments once and toggles second brain.
struct CommentsView: View {
    @StateObject var viewModel: CommentsViewModel
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Private Properties
    private let cornerRadius: CGFloat = 12
    private let spacing: CGFloat = 8
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: spacing) {
            commentsList
            commentInput
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.error ?? "")
        }
    }
    
    // MARK: - Private Views
    private var commentsList: some View {
        ScrollView {
            LazyVStack(spacing: spacing) {
                if viewModel.isLoading && viewModel.comments.isEmpty {
                    ProgressView()
                        .padding()
                } else if viewModel.comments.isEmpty {
                    emptyState
                } else {
                    commentsContent
                }
            }
            .padding(.horizontal)
        }
        .refreshable {
            Task {
                await viewModel.fetchInitialComments()
            }
        }
    }
    
    private var commentsContent: some View {
        ForEach(viewModel.comments) { comment in
            CommentCell(comment: comment) {
                Task {
                    await viewModel.toggleSecondBrain(for: comment)
                }
            }
            .onAppear {
                // Load more comments when reaching the end
                if comment == viewModel.comments.last {
                    Task {
                        await viewModel.fetchMoreComments()
                    }
                }
            }
            
            if viewModel.hasMoreComments && comment == viewModel.comments.last {
                ProgressView()
                    .padding()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No comments yet")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Be the first to share your thoughts!")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    private var commentInput: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: spacing) {
                if let user = Auth.auth().currentUser {
                    AsyncImage(url: user.photoURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }
                
                TextField("Add a comment...", text: $viewModel.newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(viewModel.isLoading)
                
                Button {
                    Task {
                        await viewModel.addComment()
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(viewModel.newCommentText.isEmpty ? .gray : .accentColor)
                }
                .disabled(viewModel.newCommentText.isEmpty || viewModel.isLoading)
            }
            .padding()
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

// MARK: - Comment Cell
struct CommentCell: View {
    let comment: Comment
    let onSecondBrainTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.userName)
                    .font(.headline)
                
                Spacer()
                
                Text(comment.formattedDate())
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text(comment.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Spacer()
                
                Button {
                    onSecondBrainTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isInSecondBrain ? "brain.fill" : "brain")
                        Text("\(comment.saveCount)")
                            .font(.caption)
                    }
                    .foregroundColor(comment.isInSecondBrain ? .accentColor : .gray)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    CommentsView(viewModel: CommentsViewModel(video: Video.mock))
}