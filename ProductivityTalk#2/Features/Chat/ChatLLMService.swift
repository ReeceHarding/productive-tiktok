import Foundation
import SwiftUI
import ProductivityTalk_2

/**
 ChatLLMService handles calling GPT-4 to answer user queries while using transcripts from the user's
 second brain as context. The service fetches an environment variable OPENAI_API_KEY via `APIConfig.shared.openAIKey`
 (similar to existing LLM calls in the codebase).
 
 It merges all relevant transcripts + titles as context, then appends the user question to form the final prompt.
 */
actor ChatLLMService {
    
    static let shared = ChatLLMService()
    
    private let modelName = "gpt-4"
    
    private init() {
        LoggingService.debug("ChatLLMService initialized for GPT-4 usage", component: "ChatLLM")
    }
    
    /**
     Sends a chat request to GPT-4, providing second brain transcripts as context, plus the user's question.
     
     - Parameters:
        - question: The user's question or prompt.
        - secondBrainEntries: An array of (videoTitle, transcript) from the user's second brain.
     - Returns: The GPT-4 response string
     */
    func sendChat(question: String, secondBrainEntries: [(title: String, transcript: String)]) async throws -> String {
        
        // Prepare context from secondBrainEntries.
        // We'll create a brief context that enumerates each transcript's title + snippet
        // to keep the token usage lower. We'll keep them short (truncate if needed).
        
        let maxTranscriptLength = 1000 // example limit to keep prompt short
        
        var contextText = "You have access to the user's Second Brain transcripts. Each transcript is associated with a video title. " +
                          "Provide short, actionable advice by referencing these transcripts if relevant. Always cite the relevant video title when you give an answer.\n\n"
        
        for (index, entry) in secondBrainEntries.enumerated() {
            let truncated = entry.transcript.prefix(maxTranscriptLength)
            contextText += "Title #\(index+1): \(entry.title)\nTranscript:\n\"\(truncated)\"\n\n"
        }
        
        let finalUserPrompt = """
You are a helpful AI. The user has transcripts from their second brain. Provide a short, actionable piece of advice referencing the transcripts if helpful. Cite the specific video title in your advice. Keep the answer concise.

User's question: "\(question)"
"""
        
        let openAIKey = APIConfig.shared.openAIKey
        guard !openAIKey.isEmpty else {
            throw NSError(domain: "ChatLLMService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "OPENAI_API_KEY is missing or empty."])
        }
        
        // Build the messages array for the chat endpoint
        let messages: [[String: String]] = [
            ["role": "system", "content": contextText],
            ["role": "user",   "content": finalUserPrompt]
        ]
        
        // Construct request
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "ChatLLMService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL"])
        }
        
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        urlReq.timeoutInterval = 60
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        urlReq.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: urlReq)
        
        if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            LoggingService.error("ChatLLMService: GPT-4 call failed with status \(httpResp.statusCode): \(bodyStr)", component: "ChatLLM")
            throw NSError(domain: "ChatLLMService", code: httpResp.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI error: \(bodyStr)"])
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "ChatLLMService", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse GPT-4 response."])
        }
        
        LoggingService.debug("ChatLLMService - GPT-4 raw response: \(content)", component: "ChatLLM")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 