import Foundation
import UIKit
import OSLog

// Add logging for better debugging
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Scheduling")

/**
 SchedulingViewModel coordinates between the UI layer and the services:
 - CalendarLLMService for generating event proposals
 - CalendarIntegrationManager for finding time slots and creating events
 */
@MainActor
class SchedulingViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let llmService = CalendarLLMService.shared
    private let calendarManager: CalendarIntegrationManager
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var eventCreated = false
    @Published var createdEventId: String?
    @Published var availableTimeSlots: [DateInterval] = []
    @Published var selectedTime: Date?
    @Published var eventTitle: String = ""
    @Published var eventDescription: String = ""
    @Published var durationMinutes: Int = 30
    @Published var eventProposal: EventProposal?
    
    // Helper to get the presenting view controller
    private var presentingViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first?.rootViewController
    }
    
    init(calendarManager: CalendarIntegrationManager) {
        self.calendarManager = calendarManager
    }
    
    // MARK: - Public Methods
    
    /**
     Generate an event proposal using Chat GPT-based `CalendarLLMService`
     */
    func generateEventProposal(transcript: String, timeOfDay: String, userPrompt: String) async throws {
        logger.debug("Generating event proposal from transcript")
        let (title, description, duration) = try await llmService.generateEventProposal(
            transcript: transcript,
            timeOfDay: timeOfDay,
            userPrompt: userPrompt
        )
        self.eventProposal = EventProposal(
            title: title,
            description: description,
            durationMinutes: duration
        )
        logger.debug("Generated proposal => Title: \(title), Desc: \(description), Duration: \(duration) min")
    }
    
    /**
     Ask CalendarIntegrationManager for free time
     */
    func findAvailableTimeSlots(forDuration duration: Int) async throws {
        isLoading = true
        errorMessage = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            calendarManager.findFreeTime(durationMinutes: duration) { [weak self] result in
                guard let self = self else { return }
                
                self.isLoading = false
                
                switch result {
                case .success(let timeSlots):
                    self.availableTimeSlots = timeSlots
                    continuation.resume()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /**
     Schedule the final event
     */
    func scheduleEvent(title: String, description: String, startTime: Date, durationMinutes: Int) async throws {
        guard let selectedTime = selectedTime else {
            throw NSError(domain: "SchedulingViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please select a time slot"])
        }
        
        isLoading = true
        errorMessage = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            calendarManager.createEvent(
                title: title,
                description: description,
                startDate: startTime,
                durationMinutes: durationMinutes
            ) { [weak self] result in
                guard let self = self else { return }
                
                self.isLoading = false
                
                switch result {
                case .success(let eventId):
                    self.eventCreated = true
                    self.createdEventId = eventId
                    continuation.resume()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Models

struct EventProposal {
    let title: String
    let description: String
    let durationMinutes: Int
} 