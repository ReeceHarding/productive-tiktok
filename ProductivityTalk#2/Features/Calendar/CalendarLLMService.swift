import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import AVFoundation
import UIKit

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
        LoggingService.info("CalendarLLMService initialized", component: "CalendarLLM")
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
        
        // Build system or user content for the LLM
        let defaultPrompt = """
        You are an AI that helps schedule a beneficial habit or activity derived from a video transcript.
        The user wants to schedule an event in their calendar for the \(timeOfDay).
        1) Provide an engaging Title in fewer than 60 characters.
        2) Provide a concise Description, under 160 characters, referencing key points from the transcript.
        3) Provide an estimated Duration in minutes that the user should allocate for this habit.
        The transcript is below:
        "\(transcript)"
        """
        let fullPrompt: String
        if let userPrompt = userPrompt, !userPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            fullPrompt = defaultPrompt + "\nUser's additional instructions:\n\(userPrompt)"
        } else {
            fullPrompt = defaultPrompt
        }
        
        LoggingService.debug("LLM Prompt: \(fullPrompt)", component: "CalendarLLM")
        
        // Prepare JSON for chat completion
        let requestData: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "user", "content": fullPrompt]
            ],
            "temperature": 0.6,
            "max_tokens": 300
        ]
        
        guard let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw NSError(domain: "CalendarLLMService",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY"])
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestData, options: [])
        urlRequest.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "Unknown error"
            LoggingService.error("OpenAI call failed. Status: \(httpResponse.statusCode), Body: \(bodyString)", component: "CalendarLLM")
            throw NSError(domain: "CalendarLLMService",
                          code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI call failed: \(bodyString)"])
        }
        
        // Parse response for text
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let choices = jsonObject["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(domain: "CalendarLLMService",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse LLM response"])
        }
        
        LoggingService.debug("LLM raw response: \(content)", component: "CalendarLLM")
        
        // Attempt a naive parse for Title, Description, Duration
        // Our minimal format: 
        // Title: ...
        // Description: ...
        // Duration: ...
        var eventTitle = "Scheduled Activity"
        var eventDescription = "Automatically generated from transcript"
        var eventDuration: Int = 30
        
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            if lower.starts(with: "title:") {
                eventTitle = line.replacingOccurrences(of: "title:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.starts(with: "description:") {
                eventDescription = line.replacingOccurrences(of: "description:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.starts(with: "duration:") {
                let durString = line.replacingOccurrences(of: "duration:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                if let intVal = Int(durString.filter("0123456789".contains)) {
                    eventDuration = intVal
                }
            }
        }
        
        // Validate
        if eventTitle.isEmpty { eventTitle = "Scheduled Activity" }
        if eventDescription.isEmpty { eventDescription = "Automatically generated from transcript" }
        if eventDuration < 5 { eventDuration = 30 } // minimum 5 minutes, default 30
        
        LoggingService.debug("LLM extracted => Title: \(eventTitle), Desc: \(eventDescription), Duration: \(eventDuration) minutes", component: "CalendarLLM")
        
        return (eventTitle, eventDescription, eventDuration)
    }
} 