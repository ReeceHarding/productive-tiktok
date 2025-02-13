import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Environment(\.colorScheme) var colorScheme
    
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
                // Chat messages
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                messageBubble(for: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        // Scroll to bottom
                        if let lastId = viewModel.messages.last?.id {
                            withAnimation {
                                scrollProxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input area
                chatInputBar
            }
            .navigationTitle("Ask GPT-4")
            .navigationBarTitleDisplayMode(.inline)
            
            if viewModel.isLoading {
                ProgressView("Thinking...")
                    .padding()
                    .background(Color(.systemBackground).opacity(0.85))
                    .cornerRadius(12)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Chat Bubbles
    @ViewBuilder
    private func messageBubble(for msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .assistant {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(msg.role == .user ? "You" : "GPT-4")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(msg.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(
                        msg.role == .user
                        ? Color.blue.opacity(0.2)
                        : Color.gray.opacity(0.2)
                    )
                    .cornerRadius(12)
            }
            
            if msg.role == .user {
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Input Bar
    private var chatInputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Type your question...", text: $viewModel.userInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task {
                        await viewModel.sendUserMessage()
                    }
                }
            Button {
                Task {
                    await viewModel.sendUserMessage()
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .disabled(viewModel.userInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.9))
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
} 