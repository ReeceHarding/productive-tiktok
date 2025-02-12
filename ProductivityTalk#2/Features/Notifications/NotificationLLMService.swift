import Foundation
import OSLog

/**
 NotificationLLMService is responsible for calling GPT-4 to generate a short
 notification message and a suggested time-of-day from a video transcript.
 
 - We rely on the user's OpenAI API key from APIConfig.shared.openAIKey
 - We parse the GPT-4 response to find:
    "NotificationMessage:" <some short text>
    "ProposedTime:" <24-hour format time, e.g. "07:00">
 
 Thoroughly logged to let devs see data in logs.
 */
actor NotificationLLMService {
    
    static let shared = NotificationLLMService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.productivitytalk", category: "NotificationLLM")
    
    private init() {
        logger.info("Initialized NotificationLLMService")
    }
    
    /**
     Generate a short notification proposal from a video transcript.
     
     We'll ask GPT-4 to produce:
       1) A short (1-2 sentence) message to remind the user about the key idea.
       2) A recommended time-of-day in 24-hour format HH:mm, e.g. "07:00".
     
     The response lines we look for:
       NotificationMessage: <some text>
       ProposedTime: <HH:mm>
     
     If GPT-4 fails or doesn't provide, we default to 08:00.
     
     - Parameter transcript: Full transcript text from the video
     - Returns: (notificationMessage, recommendedDate), both unwrapped
     */
    func generateNotificationProposal(transcript: String) async throws -> (String, Date) {
        logger.debug("Generating notification proposal with transcript of length: \(transcript.count) chars")
        
        // Build prompt
        let prompt = """
You are an AI that helps create concise notifications based on a video transcript. 
The user wants a reminder about a key idea from the transcript. Return two lines:

1) NotificationMessage: <one-liner reminder>
2) ProposedTime: <HH:mm 24-hour format for suggested reminder time>

Transcript:
"\(transcript)"
"""
        logger.debug("Notification prompt: \(prompt)")
        
        // Prepare request JSON
        let requestData: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.5,
            "max_tokens": 200
        ]
        
        let openAIKey = APIConfig.shared.openAIKey
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            let err = NSError(domain: "NotificationLLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL"])
            logger.error("Failed with invalid URL")
            throw err
        }
        
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestData, options: [])
        urlReq.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: urlReq)
        
        // Validate status
        if let httpResp = response as? HTTPURLResponse,
           !(200...299).contains(httpResp.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("OpenAI call failed. Status: \(httpResp.statusCode) - \(bodyStr)")
            throw NSError(domain: "NotificationLLMService", code: httpResp.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI request failed: \(bodyStr)"])
        }
        
        // Parse JSON response
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageDict = firstChoice["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            logger.error("Unable to parse GPT-4 response for notification proposal")
            throw NSError(domain: "NotificationLLMService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse GPT-4 notification message"])
        }
        
        logger.debug("Received raw GPT content: \(content)")
        
        // Defaults
        var finalMessage = "Reminder from your video!"
        var finalTimeStr = "08:00"
        
        // Split lines
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines {
            let lower = line.lowercased()
            // Remove numeric prefix and clean up the line
            let cleanedLine = line.replacingOccurrences(of: #"^\d+\)\s*"#, with: "", options: .regularExpression)
            if cleanedLine.lowercased().starts(with: "notificationmessage:") {
                finalMessage = cleanedLine
                    .replacingOccurrences(of: "notificationmessage:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if cleanedLine.lowercased().starts(with: "proposedtime:") {
                finalTimeStr = cleanedLine
                    .replacingOccurrences(of: "proposedtime:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        logger.debug("Parsed => message: \(finalMessage), timeStr: \(finalTimeStr)")
        
        // Convert finalTimeStr "HH:mm" to a Date (today's date + that hour/minute)
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        
        // Fallback to 08:00 if parse fails
        let parts = finalTimeStr.components(separatedBy: ":")
        if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
            components.hour = hour
            components.minute = minute
        } else {
            components.hour = 8
            components.minute = 0
        }
        
        let recommendedDate = calendar.date(from: components) ?? now.addingTimeInterval(60*60*8)
        
        logger.debug("Computed recommended date: \(recommendedDate)")
        return (finalMessage, recommendedDate)
    }
} 