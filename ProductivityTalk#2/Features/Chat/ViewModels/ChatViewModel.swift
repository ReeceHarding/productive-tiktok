import SwiftUI
import FirebaseFirestore
import OSLog
import Combine

/**
 ChatViewModel: Manages chat conversation, loads transcripts from secondBrain, calls GPTChatService to get responses, and updates UI.
 */
@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isTyping: Bool = false
    @Published var searchQuery: String = ""
    @Published var filteredMessages: [ChatMessage] = []
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var transcripts: String = ""
    private var messageListener: ListenerRegistration?
    private var searchDebouncer: AnyCancellable?
    private var typingTimer: Timer?
    private var userId: String?
    
    // MARK: - Initialization
    init() {
        LoggingService.debug("ChatViewModel initialized", component: "Chat")
        setupSearchDebouncer()
        
        if let userId = AuthenticationManager.shared.currentUser?.uid {
            self.userId = userId
            Task {
                await loadTranscripts()
                setupMessageListener()
            }
        }
    }
    
    deinit {
        messageListener?.remove()
        typingTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    func sendUserMessage() async {
        guard let userId = self.userId,
              !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LoggingService.debug("Ignoring empty user message", component: "Chat")
            return
        }
        
        isLoading = true
        let question = userInput
        userInput = ""
        
        LoggingService.debug("Processing user message: \(question)", component: "Chat")
        
        do {
            // Save user message to Firestore
            let userMsg = ChatMessage(role: .user, content: question, userId: userId)
            try await saveMessage(userMsg)
            
            // Call GPTChatService with transcripts + question
            LoggingService.debug("Sending request to GPTChatService", component: "Chat")
            let responseText = try await GPTChatService.shared.sendMessage(
                transcripts: transcripts,
                userMessage: """
                Please respond in a cheerful and engaging way, using emojis and friendly language. 
                When mentioning videos, make sure to keep the VideoID: format but make the response more conversational.
                Here's the user's question: \(question)
                """
            )
            
            LoggingService.debug("Received response from GPTChatService", component: "Chat")
            
            // Extract video information from the response
            let pattern = "VideoID: ([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})"
            var associatedVideos: [ChatMessage.VideoInfo] = []
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(responseText.startIndex..., in: responseText)
                let matches = regex.matches(in: responseText, options: [], range: range)
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: responseText) {
                        let videoId = String(responseText[range])
                        // Get video info from videos collection
                        do {
                            let videoDoc = try await db.collection("videos").document(videoId).getDocument()
                            if videoDoc.exists,
                               let videoData = videoDoc.data() {
                                let videoTitle = videoData["title"] as? String ?? "Untitled Video"
                                let thumbnailURL = videoData["thumbnailURL"] as? String ?? ""
                                associatedVideos.append(ChatMessage.VideoInfo(
                                    id: videoId,
                                    title: videoTitle,
                                    thumbnailURL: thumbnailURL
                                ))
                                LoggingService.debug("Successfully fetched video info - ID: \(videoId), Title: \(videoTitle)", component: "Chat")
                            } else {
                                LoggingService.warning("Video document not found for ID: \(videoId)", component: "Chat")
                            }
                        } catch {
                            LoggingService.error("Failed to fetch video info: \(error.localizedDescription)", component: "Chat")
                        }
                    }
                }
            }
            
            // Save assistant response to Firestore
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: responseText,
                userId: userId,
                associatedVideos: associatedVideos
            )
            try await saveMessage(assistantMsg)
            
        } catch {
            LoggingService.error("Failed to get GPT response: \(error.localizedDescription)", component: "Chat")
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func clearChat() async {
        guard let userId = self.userId else { return }
        
        do {
            let batch = db.batch()
            let messagesRef = db.collection("users").document(userId).collection("messages")
            let snapshot = try await messagesRef.getDocuments()
            
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            
            try await batch.commit()
            LoggingService.debug("Successfully cleared chat history", component: "Chat")
        } catch {
            LoggingService.error("Failed to clear chat: \(error.localizedDescription)", component: "Chat")
            self.errorMessage = "Failed to clear chat history"
        }
    }
    
    func retryLastMessage() async {
        guard let lastMessage = messages.last(where: { $0.role == .user }) else { return }
        userInput = lastMessage.content
        await sendUserMessage()
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncer() {
        searchDebouncer = $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.filterMessages(query)
            }
    }
    
    private func filterMessages(_ query: String) {
        if query.isEmpty {
            filteredMessages = messages
        } else {
            filteredMessages = messages.filter { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
        }
    }
    
    private func setupMessageListener() {
        guard let userId = self.userId else { return }
        
        let messagesRef = db.collection("users")
            .document(userId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
        
        messageListener = messagesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                LoggingService.error("Error listening for messages: \(error.localizedDescription)", component: "Chat")
                self.errorMessage = "Failed to load messages"
                return
            }
            
            guard let documents = snapshot?.documents else {
                LoggingService.warning("No documents in snapshot", component: "Chat")
                return
            }
            
            self.messages = documents.compactMap { ChatMessage(document: $0) }
            self.filterMessages(self.searchQuery)
        }
    }
    
    private func saveMessage(_ message: ChatMessage) async throws {
        guard let userId = self.userId else { return }
        
        try await db.collection("users")
            .document(userId)
            .collection("messages")
            .document(message.id)
            .setData(message.asDictionary)
        
        LoggingService.debug("Successfully saved message with ID: \(message.id)", component: "Chat")
    }
    
    private func loadTranscripts() async {
        guard let userId = self.userId else {
            LoggingService.error("No authenticated user found", component: "Chat")
            self.errorMessage = "Please sign in to access secondBrain transcripts"
            return
        }
        
        LoggingService.debug("Loading transcripts for user: \(userId)", component: "Chat")
        isLoading = true
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            LoggingService.debug("Found \(snapshot.documents.count) documents in secondBrain", component: "Chat")
            
            var allTranscripts: [String] = []
            var videoInfoMap: [String: ChatMessage.VideoInfo] = [:]
            
            for doc in snapshot.documents {
                let data = doc.data()
                if let transcript = data["transcript"] as? String,
                   !transcript.isEmpty {
                    let videoId = data["videoId"] as? String ?? "UnknownVideo"
                    
                    // Fetch video info from videos collection
                    do {
                        let videoDoc = try await db.collection("videos").document(videoId).getDocument()
                        if videoDoc.exists,
                           let videoData = videoDoc.data() {
                            let videoTitle = videoData["title"] as? String ?? "Untitled Video"
                            let thumbnailURL = videoData["thumbnailURL"] as? String ?? ""
                            
                            LoggingService.debug("Processing transcript for video: \(videoId) - \(videoTitle)", component: "Chat")
                            
                            let combined = """
---
VideoID: \(videoId)
Title: \(videoTitle)
Transcript:
\(transcript)
---
"""
                            allTranscripts.append(combined)
                            
                            // Store video info for later use
                            videoInfoMap[videoId] = ChatMessage.VideoInfo(
                                id: videoId,
                                title: videoTitle,
                                thumbnailURL: thumbnailURL
                            )
                            LoggingService.debug("Successfully stored video info - ID: \(videoId), Title: \(videoTitle)", component: "Chat")
                        } else {
                            LoggingService.warning("Video document not found for ID: \(videoId)", component: "Chat")
                        }
                    } catch {
                        LoggingService.error("Failed to fetch video info: \(error.localizedDescription)", component: "Chat")
                    }
                }
            }
            
            transcripts = allTranscripts.joined(separator: "\n\n")
            LoggingService.debug("Successfully loaded \(allTranscripts.count) transcripts", component: "Chat")
            
            // Update existing messages with video info
            for i in 0..<messages.count {
                if messages[i].role == .assistant {
                    var updatedMessage = messages[i]
                    let content = updatedMessage.content
                    
                    // Extract video IDs from content
                    let pattern = "VideoID: ([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(content.startIndex..., in: content)
                        let matches = regex.matches(in: content, options: [], range: range)
                        
                        var associatedVideos: [ChatMessage.VideoInfo] = []
                        for match in matches {
                            if let range = Range(match.range(at: 1), in: content) {
                                let videoId = String(content[range])
                                if let videoInfo = videoInfoMap[videoId] {
                                    associatedVideos.append(videoInfo)
                                }
                            }
                        }
                        updatedMessage.associatedVideos = associatedVideos
                    }
                    messages[i] = updatedMessage
                }
            }
            
        } catch {
            LoggingService.error("Failed to load transcripts: \(error.localizedDescription)", component: "Chat")
            self.errorMessage = "Failed to load transcripts: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
} 