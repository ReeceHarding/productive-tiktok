import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

/**
 A simple chat ViewModel that:
 1) Loads user's secondBrain transcripts.
 2) On user question, finds relevant transcripts (basic substring match).
 3) Calls ChatLLMService to get short GPT-4 answer.
 4) Stores messages in a local array to display in ChatView.
 */

@MainActor
class ChatViewModel: ObservableObject {
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let content: String
        let isUser: Bool
    }
    
    @Published var messages: [ChatMessage] = []
    @Published var userQuery: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store transcripts with their metadata for better context
    private struct SavedTranscript {
        let id: String
        let transcript: String
        let videoTitle: String?
        let savedAt: Date
        
        var displayTitle: String {
            videoTitle ?? "Untitled Video"
        }
    }
    
    private var savedTranscripts: [SavedTranscript] = []
    
    private let db = Firestore.firestore()
    
    // Content-related question patterns
    private let contentQuestionPatterns = [
        ["what", "transcript"],
        ["what", "note"],
        ["what", "content"],
        ["what", "have"],
        ["what", "saved"],
        ["show", "transcript"],
        ["show", "note"],
        ["show", "content"],
        ["list", "transcript"],
        ["list", "note"],
        ["list", "content"],
        ["see", "transcript"],
        ["see", "note"],
        ["see", "content"],
        ["tell", "about"],
        ["what's", "saved"],
        ["what's", "available"]
    ]
    
    init() {
        loadSecondBrainTranscripts()
    }
    
    func loadSecondBrainTranscripts() {
        guard let userId = Auth.auth().currentUser?.uid else {
            LoggingService.error("No authenticated user found", component: "Chat")
            self.errorMessage = "Please sign in to use chat"
            return
        }
        
        Task {
            do {
                let snapshot = try await db.collection("users")
                    .document(userId)
                    .collection("secondBrain")
                    .order(by: "savedAt", descending: true)
                    .getDocuments()
                
                LoggingService.debug("📚 Found \(snapshot.documents.count) Second Brain documents", component: "Chat")
                
                var loadedTranscripts: [SavedTranscript] = []
                for doc in snapshot.documents {
                    let data = doc.data()
                    if let transcript = data["transcript"] as? String,
                       !transcript.isEmpty {
                        // Extract video metadata
                        let videoTitle = data["videoTitle"] as? String ?? "Untitled Video"
                        let savedAt = (data["savedAt"] as? Timestamp)?.dateValue() ?? Date()
                        
                        // Log the raw data for debugging
                        LoggingService.debug("📝 Raw document data: \(data)", component: "Chat")
                        
                        let saved = SavedTranscript(
                            id: doc.documentID,
                            transcript: transcript,
                            videoTitle: videoTitle,
                            savedAt: savedAt
                        )
                        loadedTranscripts.append(saved)
                        
                        LoggingService.debug("📼 Added transcript - ID: \(doc.documentID), Title: \(videoTitle), Length: \(transcript.count) chars, Saved: \(savedAt)", component: "Chat")
                    }
                }
                
                self.savedTranscripts = loadedTranscripts
                
                if loadedTranscripts.isEmpty {
                    LoggingService.warning("⚠️ No transcripts found in Second Brain", component: "Chat")
                    self.errorMessage = "No notes found in your Second Brain yet. Try saving some videos first!"
                } else {
                    LoggingService.success("✅ Successfully loaded \(loadedTranscripts.count) transcripts", component: "Chat")
                    let titles = loadedTranscripts.map { "\($0.displayTitle) (saved \(DateFormatter.localizedString(from: $0.savedAt, dateStyle: .short, timeStyle: .short)))" }.joined(separator: "\n- ")
                    LoggingService.debug("📋 Available videos:\n- \(titles)", component: "Chat")
                }
            } catch {
                LoggingService.error("❌ Failed to load transcripts: \(error.localizedDescription)", component: "Chat")
                self.errorMessage = "Failed to load transcripts: \(error.localizedDescription)"
            }
        }
    }
    
    func sendMessage() {
        let trimmed = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        LoggingService.debug("User sent message: \(trimmed)", component: "Chat")
        
        // User message
        messages.append(ChatMessage(content: trimmed, isUser: true))
        
        // Clear the text field
        userQuery = ""
        
        // Perform GPT call
        Task {
            await fetchAnswer(for: trimmed)
        }
    }
    
    private func isContentQuestion(_ question: String) -> Bool {
        let words = question.lowercased().split(separator: " ").map(String.init)
        
        // Check if any of our patterns match the question
        return contentQuestionPatterns.contains { pattern in
            // For each word in the pattern, check if it appears in the question
            pattern.allSatisfy { patternWord in
                words.contains { $0.contains(patternWord) }
            }
        }
    }
    
    private func fetchAnswer(for question: String) async {
        isLoading = true
        
        // If we have no transcripts, inform the user
        if savedTranscripts.isEmpty {
            LoggingService.warning("⚠️ No transcripts available for query", component: "Chat")
            messages.append(ChatMessage(
                content: "I don't see any notes in your Second Brain yet. Try saving some videos first!",
                isUser: false
            ))
            isLoading = false
            return
        }
        
        // Check if this is a content-related question
        let askingAboutContent = isContentQuestion(question)
        LoggingService.debug("❓ Question '\(question)' is \(askingAboutContent ? "" : "not ")a content query", component: "Chat")
        
        let relevantTranscripts: [SavedTranscript]
        if askingAboutContent {
            // For content questions, include all transcripts
            relevantTranscripts = savedTranscripts
            LoggingService.debug("📚 Including all \(savedTranscripts.count) transcripts for content query", component: "Chat")
        } else {
            // For specific questions, do semantic matching
            let lowerQ = question.lowercased().split(separator: " ").map(String.init)
            relevantTranscripts = savedTranscripts.filter { saved in
                // Check if any word from the question appears in the transcript or title
                lowerQ.contains { word in
                    saved.transcript.lowercased().contains(word) ||
                    (saved.videoTitle?.lowercased().contains(word) ?? false)
                }
            }
            LoggingService.debug("🔍 Found \(relevantTranscripts.count) relevant transcripts for specific query", component: "Chat")
        }
        
        if !relevantTranscripts.isEmpty {
            let titles = relevantTranscripts.map { "\($0.displayTitle) (saved \(DateFormatter.localizedString(from: $0.savedAt, dateStyle: .short, timeStyle: .short)))" }.joined(separator: "\n- ")
            LoggingService.debug("📋 Relevant videos:\n- \(titles)", component: "Chat")
        }
        
        // Format transcripts with titles for the LLM
        let formattedTranscripts = relevantTranscripts.map { saved -> String in
            """
            Title: \(saved.displayTitle)
            Saved: \(DateFormatter.localizedString(from: saved.savedAt, dateStyle: .medium, timeStyle: .short))
            Content: \(saved.transcript)
            """
        }
        
        do {
            let reply = try await ChatLLMService.shared.generateChatReply(
                question: question,
                relevantTranscripts: formattedTranscripts,
                allTranscriptCount: savedTranscripts.count
            )
            LoggingService.success("✅ Got GPT reply of length: \(reply.count)", component: "Chat")
            LoggingService.debug("💬 GPT Reply: \(reply)", component: "Chat")
            messages.append(ChatMessage(content: reply, isUser: false))
        } catch {
            LoggingService.error("❌ Failed to get GPT reply: \(error.localizedDescription)", component: "Chat")
            let fallback = "Sorry, I couldn't process your request. \(error.localizedDescription)"
            messages.append(ChatMessage(content: fallback, isUser: false))
        }
        
        isLoading = false
    }
} 