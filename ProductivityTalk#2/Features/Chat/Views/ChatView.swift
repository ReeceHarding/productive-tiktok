import SwiftUI

/**
 A simple chat UI for GPT-4 with short answers referencing secondBrain transcripts.
 */

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack {
            // Messages List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.messages) { msg in
                        HStack {
                            if msg.isUser {
                                Spacer()
                                Text(msg.content)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                            } else {
                                Text(msg.content)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding()
                                    .background(
                                        colorScheme == .dark
                                        ? Color.white.opacity(0.2)
                                        : Color.gray.opacity(0.1)
                                    )
                                    .cornerRadius(12)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
            }
            
            // Divider
            Divider()
            
            // Input area
            HStack(spacing: 8) {
                TextField("Type your question...", text: $viewModel.userQuery, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.trailing, 8)
                } else {
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                    }
                    .disabled(viewModel.userQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Chat with GPT-4")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
} 