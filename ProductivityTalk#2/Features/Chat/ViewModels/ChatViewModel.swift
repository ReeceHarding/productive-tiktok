import SwiftUI
import FirebaseFirestore
import OSLog

enum ChatRole {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
}

/**
 ChatViewModel: Manages chat conversation, loads transcripts from secondBrain, calls GPTChatService to get responses, and updates UI.
 */
@MainActor
class ChatViewModel: ObservableObject {
    
    @Published var messages: [ChatMessage] = []
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    
    // We'll store an aggregated transcripts string for naive approach
    private var transcripts: String = ""
    
    init() {
        LoggingService.debug("ChatViewModel initialized", component: "Chat")
        Task {
            await loadTranscripts()
        }
    }
    
    func loadTranscripts() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
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
            
            // We'll gather transcripts from each doc
            var allTranscripts: [String] = []
            for doc in snapshot.documents {
                let data = doc.data()
                if let transcript = data["transcript"] as? String,
                   !transcript.isEmpty {
                    // We'll also store the videoId or title if we want to reference it
                    let videoId = data["videoId"] as? String ?? "UnknownVideo"
                    let videoTitle = data["videoTitle"] as? String ?? ""
                    
                    LoggingService.debug("Processing transcript for video: \(videoId) - \(videoTitle)", component: "Chat")
                    
                    // We'll embed them in a bracket
                    let combined = """
---
VideoID: \(videoId)
Title: \(videoTitle)
Transcript:
\(transcript)
---
"""
                    allTranscripts.append(combined)
                }
            }
            
            transcripts = allTranscripts.joined(separator: "\n\n")
            LoggingService.debug("Successfully loaded \(allTranscripts.count) transcripts", component: "Chat")
            
            isLoading = false
        } catch {
            LoggingService.error("Failed to load transcripts: \(error.localizedDescription)", component: "Chat")
            self.errorMessage = "Failed to load transcripts: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    func sendUserMessage() async {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LoggingService.debug("Ignoring empty user message", component: "Chat")
            return
        }
        
        // Add user message to messages
        let userMsg = ChatMessage(role: .user, content: userInput)
        messages.append(userMsg)
        
        let question = userInput
        userInput = ""
        isLoading = true
        
        LoggingService.debug("Processing user message: \(question)", component: "Chat")
        
        do {
            // Call GPTChatService with transcripts + question
            LoggingService.debug("Sending request to GPTChatService", component: "Chat")
            let responseText = try await GPTChatService.shared.sendMessage(transcripts: transcripts, userMessage: question)
            
            LoggingService.debug("Received response from GPTChatService", component: "Chat")
            
            // Add assistant response
            let assistantMsg = ChatMessage(role: .assistant, content: responseText)
            messages.append(assistantMsg)
            
        } catch {
            LoggingService.error("Failed to get GPT response: \(error.localizedDescription)", component: "Chat")
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
} 