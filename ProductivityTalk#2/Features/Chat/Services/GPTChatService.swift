import Foundation
import SwiftUI
import Combine
import OSLog

/**
 GPTChatService is responsible for sending chat requests to GPT-4 with relevant transcripts and user queries.
 
 - The service merges transcripts from secondBrain into a context prompt.
 - It performs a single 'chat/completions' call to GPT-4 and returns the assistant's response.
 - For more advanced usage, you might chunk transcripts, perform embedding lookups, etc. But this example does a naive approach.
 */
actor GPTChatService {
    
    static let shared = GPTChatService()
    
    private let openAIKey = APIConfig.shared.openAIKey
    private let openAIEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        LoggingService.debug("GPTChatService initialized", component: "Chat")
    }
    
    /**
     Sends the user's message + transcripts to GPT-4. Returns the assistant's text or throws an error.
     
     - Parameters:
       - transcripts: Aggregated text from secondBrain. We'll embed them in a single big system prompt for now.
       - userMessage: The user's question.
     - Returns: A string with the GPT-4 answer referencing relevant videos as possible.
     */
    func sendMessage(transcripts: String, userMessage: String) async throws -> String {
        LoggingService.debug("Preparing to send message to GPT-4", component: "Chat")
        LoggingService.debug("User message length: \(userMessage.count)", component: "Chat")
        LoggingService.debug("Transcripts length: \(transcripts.count)", component: "Chat")
        
        // 1) System prompt instructing GPT to reference videos
        let systemPrompt = """
You are a helpful AI assistant. You have access to multiple video transcripts. If the user question references a certain piece of text, mention which video it might be from if it's clearly relevant. Also provide short, helpful answers. If possible, add a link or mention the video ID if helpful. The transcripts are below:
\(transcripts)
"""

        // We'll keep it short to avoid token overflows
        // 2) Build request
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.7
        ]

        guard let url = URL(string: openAIEndpoint) else {
            LoggingService.error("Invalid OpenAI endpoint URL", component: "Chat")
            throw NSError(domain: "GPTChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI endpoint"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.httpBody = bodyData
        
        LoggingService.debug("Sending request to OpenAI API", component: "Chat")
        
        // 3) Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            LoggingService.debug("Received response with status code: \(httpResponse.statusCode)", component: "Chat")
            
            if !(200...299).contains(httpResponse.statusCode) {
                let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
                LoggingService.error("OpenAI API error: \(bodyStr)", component: "Chat")
                throw NSError(domain: "GPTChatService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI call failed: \(bodyStr)"])
            }
        }
        
        // 4) Parse JSON
        do {
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                LoggingService.error("Failed to parse OpenAI response", component: "Chat")
                throw NSError(domain: "GPTChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not parse chat response"])
            }
            
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            LoggingService.debug("Successfully received and parsed GPT response", component: "Chat")
            return trimmedContent
            
        } catch {
            LoggingService.error("JSON parsing error: \(error.localizedDescription)", component: "Chat")
            throw error
        }
    }
} 