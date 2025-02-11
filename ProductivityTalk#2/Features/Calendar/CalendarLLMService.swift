import Foundation
import SwiftUI

/// Logging for debug
private let llmLogger = LoggingService.self

/**
 CalendarLLMService is responsible for calling the LLM endpoint to generate a recommended
 Title, Description, and approximate Duration for a new calendar event, given a video transcript
 and user preferences for time of day.
 
 It references the existing OPENAI_API_KEY environment variable via process.env in Node or
 iOS environment in Swift. We rely on the same approach used in the codebase for
 transcript generation. Once we receive the LLM response, we parse out the recommended Title,
 Description, and Duration in minutes. 
 */
actor CalendarLLMService {
    
    static let shared = CalendarLLMService()
    
    private init() {
        llmLogger.info("CalendarLLMService initialized", component: "CalendarLLM")
    }
    
    /**
     Generates an event recommendation with Title, Description, and Duration (in minutes).
     
     - Parameters:
       - transcript: The transcript text from the relevant video
       - timeOfDay: A string like "morning", "afternoon", or "evening"
       - userPrompt: Additional user instructions for the LLM (optional)
     
     - Returns: (title, description, durationInMinutes)
     */
    func generateEventProposal(transcript: String,
                               timeOfDay: String,
                               userPrompt: String? = nil) async throws -> (String, String, Int) {
        
        // Build the prompt
        let basePrompt = """
You are an AI that helps schedule a beneficial habit or activity derived from a video transcript.
The user wants to schedule an event in their calendar for the \(timeOfDay).
1. Provide an engaging Title in fewer than 60 characters.
2. Provide a concise Description, under 160 characters, referencing key points from the transcript.
3. Provide an estimated Duration in minutes that the user should allocate for this habit.
The transcript is below:
"\(transcript)"
"""
        let finalPrompt: String
        if let userPrompt = userPrompt, !userPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            finalPrompt = basePrompt + "\nUser's additional instructions:\n\(userPrompt)"
        } else {
            finalPrompt = basePrompt
        }
        
        llmLogger.debug("LLM Prompt: \(finalPrompt)", component: "CalendarLLM")
        
        // Create request
        let requestData: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "user", "content": finalPrompt]
            ],
            "temperature": 0.6,
            "max_tokens": 300
        ]
        
        let openAIKey = APIConfig.shared.openAIKey
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "CalendarLLMService",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid openai URL"])
        }
        
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestData, options: [])
        urlReq.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: urlReq)
        if let httpResp = response as? HTTPURLResponse,
           !(200...299).contains(httpResp.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            llmLogger.error("OpenAI call failed. Status: \(httpResp.statusCode), Body: \(bodyStr)", component: "CalendarLLM")
            throw NSError(domain: "CalendarLLMService", code: httpResp.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "OpenAI call failed: \(bodyStr)"])
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "CalendarLLMService", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse OpenAI chat response"])
        }
        
        llmLogger.debug("LLM raw response: \(content)", component: "CalendarLLM")
        
        // Parse lines
        var eventTitle = "Scheduled Activity"
        var eventDesc = "Auto-generated from transcript"
        var eventDuration = 30
        
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for line in lines {
            let lower = line.lowercased()
            if lower.starts(with: "title:") {
                eventTitle = line.replacingOccurrences(of: "title:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if lower.starts(with: "description:") {
                eventDesc = line.replacingOccurrences(of: "description:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if lower.starts(with: "duration:") {
                let durStr = line.replacingOccurrences(of: "duration:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                let intVal = Int(durStr.filter("0123456789".contains)) ?? 30
                eventDuration = max(intVal, 5)
            }
        }
        
        llmLogger.debug("LLM extracted => Title: \(eventTitle), Desc: \(eventDesc), Duration: \(eventDuration) minutes", component: "CalendarLLM")
        return (eventTitle, eventDesc, eventDuration)
    }
} 