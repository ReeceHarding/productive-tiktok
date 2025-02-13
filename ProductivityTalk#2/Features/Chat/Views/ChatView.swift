import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedVideoId: String?
    @State private var showVideoSheet = false
    @State private var showErrorAlert = false
    @State private var showSearchBar = false
    @State private var showClearChatAlert = false
    @State private var scrollToBottom = false
    @State private var showEmptyState = false
    @State private var isSearching = false
    @FocusState private var isInputFocused: Bool
    
    private let hapticEngine = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            ChatBackgroundView(colorScheme: colorScheme)
            
            VStack(spacing: 0) {
                if showSearchBar {
                    ChatSearchBar(
                        searchQuery: $viewModel.searchQuery,
                        isSearching: $isSearching,
                        hapticEngine: hapticEngine
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                ChatMessagesView(
                    viewModel: viewModel,
                    scrollToBottom: $scrollToBottom,
                    selectedVideoId: $selectedVideoId,
                    showVideoSheet: $showVideoSheet,
                    hapticEngine: hapticEngine
                )
                
                Divider()
                    .background(Color.secondary.opacity(0.2))
                
                ChatInputBar(
                    viewModel: viewModel,
                    isInputFocused: _isInputFocused,
                    scrollToBottom: $scrollToBottom,
                    hapticEngine: hapticEngine
                )
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Chat with GPT-4")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ChatToolbar(
                        showSearchBar: $showSearchBar,
                        showClearChatAlert: $showClearChatAlert,
                        isSearching: $isSearching,
                        viewModel: viewModel,
                        hapticEngine: hapticEngine
                    )
                }
            }
            
            if viewModel.isLoading {
                LoadingOverlay()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newError in
            if newError != nil {
                hapticEngine.impactOccurred(intensity: 0.7)
            }
            showErrorAlert = newError != nil
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                hapticEngine.prepare()
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { 
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Clear Chat", isPresented: $showClearChatAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                hapticEngine.impactOccurred(intensity: 0.6)
                Task {
                    await viewModel.clearChat()
                }
            }
        } message: {
            Text("Are you sure you want to clear all chat messages? This cannot be undone.")
        }
        .sheet(isPresented: $showVideoSheet) {
            LoggingService.debug("Video sheet dismissed", component: "Chat")
        } content: {
            if let videoId = selectedVideoId {
                NavigationView {
                    VideoFeedView(initialVideoId: videoId)
                        .navigationBarItems(trailing: Button("Done") {
                            LoggingService.debug("User tapped Done button on video sheet", component: "Chat")
                            showVideoSheet = false
                        })
                        .onAppear {
                            LoggingService.debug("Presenting video sheet for ID: \(videoId)", component: "Chat")
                        }
                }
            }
        }
    }
}

// MARK: - Supporting Views
private struct ChatBackgroundView: View {
    let colorScheme: ColorScheme
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(colorScheme == .dark ? .systemGray6 : .systemBackground),
                Color.blue.opacity(0.1),
                Color.purple.opacity(0.1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct ChatMessagesView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var scrollToBottom: Bool
    @Binding var selectedVideoId: String?
    @Binding var showVideoSheet: Bool
    let hapticEngine: UIImpactFeedbackGenerator
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        EmptyChatView()
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ForEach(viewModel.searchQuery.isEmpty ? viewModel.messages : viewModel.filteredMessages) { msg in
                            ChatMessageBubble(
                                message: msg,
                                viewModel: viewModel,
                                selectedVideoId: $selectedVideoId,
                                showVideoSheet: $showVideoSheet,
                                hapticEngine: hapticEngine
                            )
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .refreshable {
                hapticEngine.impactOccurred()
                await viewModel.loadTranscripts()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if scrollToBottom {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scrollToLastMessage(proxy: scrollProxy)
                    }
                }
            }
            .onChange(of: scrollToBottom) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scrollToLastMessage(proxy: scrollProxy)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !scrollToBottom && !viewModel.messages.isEmpty {
                    ScrollToBottomButton(
                        scrollToBottom: $scrollToBottom,
                        proxy: scrollProxy,
                        hapticEngine: hapticEngine
                    )
                }
            }
        }
    }
    
    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        if let lastId = viewModel.messages.last?.id {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

private struct ScrollToBottomButton: View {
    @Binding var scrollToBottom: Bool
    let proxy: ScrollViewProxy
    let hapticEngine: UIImpactFeedbackGenerator
    
    var body: some View {
        Button {
            hapticEngine.impactOccurred(intensity: 0.4)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scrollToBottom = true
                if let lastId = proxy.scrollToLastMessage() {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding()
        .transition(.scale.combined(with: .opacity))
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedVideoId: String?
    @Binding var showVideoSheet: Bool
    let hapticEngine: UIImpactFeedbackGenerator
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Avatar(role: .assistant)
                    .transition(.scale.combined(with: .opacity))
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                MessageHeader(message: message)
                MessageContent(
                    message: message,
                    viewModel: viewModel,
                    selectedVideoId: $selectedVideoId,
                    showVideoSheet: $showVideoSheet,
                    hapticEngine: hapticEngine,
                    colorScheme: colorScheme
                )
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                    hapticEngine.impactOccurred(intensity: 0.5)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                if message.role == .user {
                    Button {
                        hapticEngine.impactOccurred(intensity: 0.4)
                        viewModel.userInput = message.content
                        isInputFocused = true
                    } label: {
                        Label("Edit & Resend", systemImage: "pencil")
                    }
                }
            }
            
            if message.role == .user {
                Avatar(role: .user)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .id(message.id)
    }
}

private struct MessageHeader: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            Text(message.role == .user ? "You" : "GPT-4")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(message.timestamp.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

private struct MessageContent: View {
    let message: ChatMessage
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedVideoId: String?
    @Binding var showVideoSheet: Bool
    let hapticEngine: UIImpactFeedbackGenerator
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(message.content))
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user ? 
                            Color.blue.opacity(0.2) :
                            Color(colorScheme == .dark ? .systemGray5 : .systemGray6)
                        )
                )
            
            if !message.associatedVideos.isEmpty {
                AssociatedVideosView(
                    videos: message.associatedVideos,
                    selectedVideoId: $selectedVideoId,
                    showVideoSheet: $showVideoSheet,
                    hapticEngine: hapticEngine
                )
            }
        }
    }
}

private struct AssociatedVideosView: View {
    let videos: [ChatMessage.VideoInfo]
    @Binding var selectedVideoId: String?
    @Binding var showVideoSheet: Bool
    let hapticEngine: UIImpactFeedbackGenerator
    
    var body: some View {
        DisclosureGroup {
            VStack(spacing: 12) {
                ForEach(videos, id: \.id) { video in
                    Button {
                        hapticEngine.impactOccurred(intensity: 0.5)
                        LoggingService.debug("User tapped video link for ID: \(video.id)", component: "Chat")
                        selectedVideoId = video.id
                        showVideoSheet = true
                    } label: {
                        VideoPreviewCard(video: video)
                    }
                    .buttonStyle(VideoCardButtonStyle())
                }
            }
        } label: {
            Label {
                Text("Related Videos (\(videos.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "video.fill")
            }
            .foregroundStyle(.blue)
            .padding(.vertical, 4)
        }
    }
}

private struct Avatar: View {
    let role: ChatRole
    
    var body: some View {
        Group {
            if role == .assistant {
                Image(systemName: "brain")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "person.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 24))
        .frame(width: 32, height: 32)
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                LoadingAnimation(message: "GPT-4 is thinking...")
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
} 
} 