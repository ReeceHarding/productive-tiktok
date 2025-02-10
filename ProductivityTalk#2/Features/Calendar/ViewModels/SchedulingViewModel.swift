import Foundation
import SwiftUI

/**
 SchedulingViewModel coordinates between the UI layer and the services:
 - CalendarLLMService for generating event proposals
 - CalendarIntegrationManager for finding time slots and creating events
 */
@MainActor
final class SchedulingViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let llmService = CalendarLLMService.shared
    private let calendarManager = CalendarIntegrationManager.shared
    
    // MARK: - Published Properties
    @Published private(set) var eventProposal: EventProposal?
    @Published private(set) var availableTimeSlots: [DateInterval] = []
    
    // MARK: - Public Methods
    
    /**
     Generate an event proposal using the LLM service based on video transcript and preferences
     */
    func generateEventProposal(transcript: String, timeOfDay: String, userPrompt: String) async throws {
        LoggingService.debug("Generating event proposal from transcript", component: "Scheduling")
        eventProposal = try await llmService.generateEventProposal(
            transcript: transcript,
            timeOfDay: timeOfDay,
            userPrompt: userPrompt
        )
    }
    
    /**
     Find available time slots that match the desired duration
     */
    func findAvailableTimeSlots(forDuration durationMinutes: Int) async throws {
        LoggingService.debug("Finding available time slots for \(durationMinutes) minutes", component: "Scheduling")
        availableTimeSlots = try await calendarManager.findFreeTime(desiredDurationInMinutes: durationMinutes)
    }
    
    /**
     Schedule an event at the specified time
     */
    func scheduleEvent(title: String, description: String, startTime: Date, durationMinutes: Int) async throws {
        LoggingService.debug("Scheduling event: \(title) at \(startTime)", component: "Scheduling")
        let eventId = try await calendarManager.createCalendarEvent(
            title: title,
            description: description,
            startDate: startTime,
            durationMinutes: durationMinutes
        )
        LoggingService.success("Event scheduled successfully with ID: \(eventId)", component: "Scheduling")
    }
}

// MARK: - Models

struct EventProposal {
    let title: String
    let description: String
    let durationMinutes: Int
} 