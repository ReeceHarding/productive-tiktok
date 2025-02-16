import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(msg)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    withAnimation {
                        scrollToBottom(scrollProxy)
                    }
                }
            }
            
            // Typing Indicator or Error
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            } else if viewModel.isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Thinking...")
                        .font(.footnote)
                }
                .padding(.bottom, 4)
            }
            
            // Input field
            chatInputBar
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func messageBubble(_ msg: ChatViewModel.Message) -> some View {
        HStack {
            if msg.role == .assistant {
                Spacer(minLength: 30)
            }
            Text(msg.content)
                .padding(12)
                .background(msg.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                .cornerRadius(12)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
            if msg.role == .user {
                Spacer(minLength: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .leading : .trailing)
    }
    
    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask me anything...", text: $viewModel.currentInput, axis: .vertical)
                .focused($isInputFocused)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onSubmit {
                    viewModel.sendUserMessage()
                }
            
            Button(action: {
                viewModel.sendUserMessage()
                isInputFocused = false
            }) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .disabled(viewModel.isLoading || viewModel.currentInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.95))
    }
    
    private func scrollToBottom(_ scrollProxy: ScrollViewProxy) {
        if let lastMsg = viewModel.messages.last?.id {
            scrollProxy.scrollTo(lastMsg, anchor: .bottom)
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
} 