import Foundation
import EventKit
import SwiftUI

@MainActor
public class CalendarSchedulingViewModel: ObservableObject {
    // Published State
    @Published public var selectedTimeOfDay: TimeOfDayOption? = nil
    @Published public var generatedTitle: String = ""
    @Published public var generatedDescription: String = ""
    @Published public var generatedDurationMinutes: Int = 30
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var scheduledStart: Date? = nil
    @Published public var scheduledEnd: Date? = nil
    
    // A reference to the video transcript or user instructions
    public var transcript: String = ""
    
    // For Apple's local calendar usage
    private let eventStore = EKEventStore()
    
    public enum TimeOfDayOption: String, CaseIterable {
        case morning = "Morning"
        case midday = "Midday"
        case evening = "Evening"
        case custom = "Custom"
    }
    
    public init(transcript: String) {
        self.transcript = transcript
        LoggingService.debug("CalendarSchedulingViewModel initialized with transcript length: \(transcript.count) chars", component: "CalendarSchedulingVM")
        
        // Add calendar authorization status check
        Task {
            let status = EKEventStore.authorizationStatus(for: .event)
            LoggingService.debug("📅 Calendar authorization status: \(status.rawValue)", component: "CalendarSchedulingVM")
        }
    }
    
    // 1. Request Calendar Permission for EventKit
    public func requestCalendarAccess() async throws {
        LoggingService.debug("Requesting calendar access", component: "CalendarSchedulingVM")
        
        if #available(iOS 17.0, *) {
            // Use the new iOS 17+ API
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else {
                throw NSError(domain: "Calendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Calendar access denied"])
            }
        } else {
            // Use the older API for iOS versions before 17
            let granted = try await eventStore.requestAccess(to: .event)
            guard granted else {
                throw NSError(domain: "Calendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Calendar access denied"])
            }
        }
        
        LoggingService.success("Calendar access granted", component: "CalendarSchedulingVM")
    }
    
    // 2. Generate event suggestions from LLM
    public func generateEventSuggestion() async {
        LoggingService.debug("Starting LLM-based generation for event suggestion", component: "CalendarSchedulingVM")
        isLoading = true
        errorMessage = nil
        
        // Example of sending prompt to LLM
        let timeOfDayStr = selectedTimeOfDay?.rawValue ?? "Unspecified"
        let prompt = """
        The user wants to schedule an event from the transcript below. The user has chosen time-of-day: \(timeOfDayStr).
        Transcript or user instructions:
        "\(transcript)"
        
        Please propose:
        1) A short event title (max 60 chars).
        2) A short description (1-2 sentences).
        3) The recommended duration in minutes (like 15 or 30).
        """
        
        // For demonstration, we mock the response to skip actual network calls
        // In real usage, we'd do a POST request to our LLM server with `prompt`
        // Then parse JSON response or text
        await Task.sleep(1_000_000_000) // Simulate some network wait
        
        // Mock result
        self.generatedTitle = "Morning Sunlight Habit"
        self.generatedDescription = "Get 15 minutes of direct sunlight. Avoid sunglasses; incorporate this into daily walk."
        self.generatedDurationMinutes = 15
        LoggingService.debug("LLM suggested: Title=\(generatedTitle), Desc=\(generatedDescription)", component: "CalendarSchedulingVM")
        
        isLoading = false
    }
    
    // 3. Check for free calendar slot
    public func findFreeSlot() async {
        LoggingService.debug("Finding free slot for user-chosen time-of-day: \(String(describing: selectedTimeOfDay))", component: "CalendarSchedulingVM")
        
        guard let tod = selectedTimeOfDay else {
            LoggingService.warning("No time of day chosen, defaulting to morning window", component: "CalendarSchedulingVM")
            return
        }
        
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.day = components.day! + 1 // Start searching tomorrow
        
        switch tod {
        case .morning:
            components.hour = 7
            components.minute = 30
        case .midday:
            components.hour = 12
            components.minute = 0
        case .evening:
            components.hour = 18
            components.minute = 0
        case .custom:
            // For a custom time, you might prompt for explicit hour/min
            components.hour = 10
            components.minute = 0
        }
        
        guard let potentialStart = Calendar.current.date(from: components) else { return }
        let potentialEnd = Calendar.current.date(byAdding: .minute, value: generatedDurationMinutes, to: potentialStart)
        
        // In a real solution, query existing events in the store and see if there's a conflict.
        // For now, we pretend it's free.
        self.scheduledStart = potentialStart
        self.scheduledEnd = potentialEnd
        
        LoggingService.success("Found a free slot from \(String(describing: scheduledStart)) to \(String(describing: scheduledEnd))", component: "CalendarSchedulingVM")
    }
    
    // 4. Create an event in the local Apple calendar
    public func createLocalCalendarEvent() async throws {
        LoggingService.debug("📅 Creating local Apple Calendar event using EventKit", component: "CalendarSchedulingVM")
        
        // Check calendar authorization first
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        LoggingService.debug("📅 Current calendar authorization status: \(authStatus.rawValue)", component: "CalendarSchedulingVM")
        
        guard let start = scheduledStart, let end = scheduledEnd else {
            LoggingService.error("📅 No valid scheduling time found", component: "CalendarSchedulingVM")
            throw NSError(domain: "Calendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid scheduling time found"])
        }
        
        LoggingService.debug("📅 Attempting to create event from \(start) to \(end)", component: "CalendarSchedulingVM")
        
        // Get the default calendar for new events
        let calendar: EKCalendar
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            calendar = defaultCalendar
            LoggingService.debug("📅 Using default calendar: \(calendar.title)", component: "CalendarSchedulingVM")
        } else {
            // If no default calendar, try to get the first available calendar
            let calendars = eventStore.calendars(for: .event)
            LoggingService.debug("📅 Available calendars: \(calendars.map { $0.title })", component: "CalendarSchedulingVM")
            
            guard let firstCalendar = calendars.first else {
                LoggingService.error("📅 No available calendars found", component: "CalendarSchedulingVM")
                throw NSError(domain: "Calendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "No available calendars found"])
            }
            calendar = firstCalendar
            LoggingService.warning("📅 No default calendar found, using first available: \(calendar.title)", component: "CalendarSchedulingVM")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = generatedTitle
        event.notes = generatedDescription
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        
        // Add a default alarm 15 minutes before
        let alarm = EKAlarm(relativeOffset: -900) // 15 minutes in seconds
        event.addAlarm(alarm)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            LoggingService.success("Event saved to local Apple Calendar successfully", component: "CalendarSchedulingVM")
        } catch {
            LoggingService.error("Failed to save event: \(error)", component: "CalendarSchedulingVM")
            throw error
        }
    }
} 