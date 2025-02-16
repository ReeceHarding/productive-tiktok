import Foundation
import Combine
import FirebaseFirestore

@MainActor
class ChatViewModel: ObservableObject {
    struct Message: Identifiable {
        enum Role {
            case user
            case assistant
        }
        let id = UUID()
        let role: Role
        let content: String
    }
    
    @Published var messages: [Message] = []
    @Published var currentInput: String = ""
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    
    // Store (title, transcript) from user's second brain
    private var secondBrainEntries: [(title: String, transcript: String)] = []
    
    init() {
        LoggingService.debug("ChatViewModel initialized", component: "ChatVM")
        Task {
            await loadSecondBrainTranscripts()
        }
    }
    
    private func loadSecondBrainTranscripts() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("No authenticated user in ChatViewModel", component: "ChatVM")
            self.error = "Please sign in to use Chat"
            return
        }
        
        isLoading = true
        LoggingService.debug("ChatViewModel: Loading second brain transcripts for user \(userId)", component: "ChatVM")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            var entries: [(String, String)] = []
            for doc in snapshot.documents {
                let data = doc.data()
                let title = data["videoTitle"] as? String ?? "Untitled Video"
                let transcript = data["transcript"] as? String ?? ""
                if !transcript.isEmpty {
                    entries.append((title, transcript))
                }
            }
            
            LoggingService.debug("ChatViewModel: Fetched \(entries.count) transcripts from second brain", component: "ChatVM")
            secondBrainEntries = entries
        } catch {
            LoggingService.error("ChatViewModel: Error loading second brain transcripts: \(error.localizedDescription)", component: "ChatVM")
            self.error = "Failed to load transcripts"
        }
        
        isLoading = false
    }
    
    func sendUserMessage() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Add user message to messages
        messages.append(Message(role: .user, content: trimmed))
        currentInput = ""
        
        // Call GPT-4 in the background
        Task {
            await fetchChatResponse(userQuestion: trimmed)
        }
    }
    
    private func fetchChatResponse(userQuestion: String) async {
        isLoading = true
        do {
            let assistantReply = try await ChatLLMService.shared.sendChat(
                question: userQuestion,
                secondBrainEntries: secondBrainEntries
            )
            
            // Append assistant reply
            messages.append(Message(role: .assistant, content: assistantReply))
            
        } catch {
            LoggingService.error("ChatViewModel: GPT-4 error - \(error.localizedDescription)", component: "ChatVM")
            self.error = "Failed to get GPT-4 reply: \(error.localizedDescription)"
            messages.append(Message(role: .assistant, content: "Sorry, I couldn't fetch a response."))
        }
        isLoading = false
    }
} 