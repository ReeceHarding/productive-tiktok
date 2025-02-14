import Foundation
import OSLog

/**
 ChatLLMService is responsible for calling GPT-4 to answer user questions.
 It gathers relevant transcript context from the user's secondBrain data
 (passed in from outside), then sends a short user question + context to GPT-4
 for a concise answer.
 */
actor ChatLLMService {
    
    static let shared = ChatLLMService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.productivitytalk", category: "ChatLLM")
    
    private init() {
        logger.info("Initialized ChatLLMService")
    }
    
    /**
     Build a prompt from the user's question plus relevant transcripts, then call GPT-4.
     Returns the GPT-4 answer (short and simple).
     */
    func generateChatReply(question: String, relevantTranscripts: [String], allTranscriptCount: Int) async throws -> String {
        logger.debug("Generating reply for question: \"\(question)\" with \(relevantTranscripts.count) relevant transcripts out of \(allTranscriptCount) total")
        
        // Merge transcripts into a single context block with clear separators
        let combinedContext = relevantTranscripts.enumerated().map { index, transcript in
            """
            TRANSCRIPT \(index + 1):
            \(transcript)
            """
        }.joined(separator: "\n\n---\n\n")
        
        // Build a more informative prompt
        let prompt = """
You are an AI assistant helping with a Second Brain app that saves video transcripts. The user has \(allTranscriptCount) saved lesson transcripts.

If the user asks what content they have:
1. Tell them how many transcripts they have
2. List the titles of their saved videos
3. For each video, provide a 1-line summary of its main topic/lesson
4. If no transcripts are provided, explain that while they have \(allTranscriptCount) saved transcripts, none match their current query

For other questions:
1. Answer based on the relevant transcripts provided below
2. Reference specific videos by title when answering
3. If no relevant transcripts are found, let them know you can't find content matching their question
4. Suggest they try rephrasing or ask about different topics

RELEVANT TRANSCRIPTS:
\(combinedContext)

USER QUESTION:
\(question)

RETURN a helpful, specific answer focusing on the actual content of their saved lessons:
"""
        
        logger.debug("Prompt for GPT-4: \(prompt.prefix(300))...(truncated)")
        
        // Prepare request. Reuse the same approach as the other LLM services
        let requestData: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        // Reuse openAIKey from your existing approach. Adjust as needed.
        let openAIKey = APIConfig.shared.openAIKey
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "ChatLLMService",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL"])
        }
        
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestData, options: [])
        urlReq.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: urlReq)
        
        if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("OpenAI call failed. Status: \(httpResp.statusCode) - \(bodyStr)")
            throw NSError(domain: "ChatLLMService", code: httpResp.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI request failed: \(bodyStr)"])
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageDict = firstChoice["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            logger.error("Unable to parse GPT-4 response for chat query")
            throw NSError(domain: "ChatLLMService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse GPT-4 chat response"])
        }
        
        logger.debug("GPT-4 reply: \(content.prefix(300))...(truncated)")
        
        // Return the text
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 