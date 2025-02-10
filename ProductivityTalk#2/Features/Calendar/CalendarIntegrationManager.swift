import Foundation
import SwiftUI
import GoogleSignIn
import GTMAppAuth
import GoogleAPIClientForRESTCore
import GoogleAPIClientForREST_Calendar

/**
 CalendarIntegrationManager is responsible for:
 - Authenticating user with Google (OAuth 2.0).
 - Checking or refreshing tokens.
 - Creating events in the user's primary calendar.
 - Querying free busy times to find open slots.
 

 
 Ensure your Info.plist has the required Google Reversed Client ID entries. 
 */
final class CalendarIntegrationManager: ObservableObject {
    
    static let shared = CalendarIntegrationManager()
    
    // The service object for interacting with Google Calendar
    private let service = GTLRCalendarService()
    
    // OAuth token storage
    @Published var currentAuthorization: GTMAppAuthFetcherAuthorization?
    
    private init() {
        LoggingService.info("CalendarIntegrationManager initialized", component: "GoogleCalendar")
    }
    
    /**
     Check if we have a saved auth state from previous sessions. 
     If so, restore it; if not, user must log in.
     */
    func restorePreviousSignInIfAvailable() {
        // Implementation can restore from Keychain or user defaults
        // For brevity, not implemented. If needed, add restore logic here.
        LoggingService.debug("Checking for previous Google OAuth state...", component: "GoogleCalendar")
    }
    
    /**
     Start the Google OAuth sign-in flow if needed. 
     Provide a SwiftUI or UIKit context for presenting the authentication.
     */
    func signIn(presentingViewController: UIViewController) async throws {
        LoggingService.debug("Starting Google OAuth sign-in flow...", component: "GoogleCalendar")
        
        let clientId = Bundle.main.infoDictionary?["GIDClientID"] as? String
        guard let clientId = clientId else {
            LoggingService.error("Missing GIDClientID in Info.plist", component: "GoogleCalendar")
            throw NSError(domain: "CalendarIntegrationManager",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Missing Google OAuth client ID"])
        }
        
        let configuration = GTMAppAuthFetcherAuthorization.configurationForGoogle()
        let scopes = ["https://www.googleapis.com/auth/calendar"]
        
        return try await withCheckedThrowingContinuation { continuation in
            GTMAppAuthFetcherAuthorization.authorizeInKeychain(
                withConfiguration: configuration,
                clientID: clientId,
                clientSecret: nil,
                scopes: scopes,
                additionalParameters: nil,
                presentingViewController: presentingViewController
            ) { authorization, error in
                if let error = error {
                    LoggingService.error("Google OAuth failed: \(error.localizedDescription)", component: "GoogleCalendar")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let authorization = authorization else {
                    LoggingService.error("No authorization received", component: "GoogleCalendar")
                    continuation.resume(throwing: NSError(domain: "CalendarIntegrationManager",
                                                       code: -1,
                                                       userInfo: [NSLocalizedDescriptionKey: "Failed to get authorization"]))
                    return
                }
                
                self.currentAuthorization = authorization
                self.service.authorizer = authorization
                
                LoggingService.success("Google OAuth sign-in successful", component: "GoogleCalendar")
                continuation.resume()
            }
        }
    }
    
    /**
     Check if we have valid auth:
     - If no, prompt signIn
     - If yes, proceed
     */
    func ensureAuthorized(presentingViewController: UIViewController) async throws {
        if currentAuthorization == nil || currentAuthorization?.canAuthorize() == false {
            try await signIn(presentingViewController: presentingViewController)
        }
    }
    
    /**
     Finds open time slots within a given day range. 
     For simplicity, we'll just demonstrate the freebusy request for the next 7 days.
     
     - Parameter desiredDurationInMinutes: Duration that user wants to block off
     
     - Returns: A list of Date intervals representing free time windows
     */
    func findFreeTime(desiredDurationInMinutes: Int) async throws -> [DateInterval] {
        LoggingService.info("Finding free time of at least \(desiredDurationInMinutes) minutes in the next 7 days...", component: "GoogleCalendar")
        
        guard let auth = currentAuthorization else {
            throw NSError(domain: "CalendarIntegrationManager",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No currentAuthorization present"])
        }
        service.authorizer = auth
        
        let now = Date()
        guard let inOneWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            return []
        }
        
        let freeBusyRequest = GTLRCalendar_FreeBusyRequest()
        let timeMin = GTLRDateTime(date: now)
        let timeMax = GTLRDateTime(date: inOneWeek)
        freeBusyRequest.timeMin = timeMin
        freeBusyRequest.timeMax = timeMax
        freeBusyRequest.items = [ GTLRCalendar_FreeBusyRequestItem(json: ["id":"primary"]) ]
        
        let query = GTLRCalendarQuery_FreebusyQuery.query(withObject: freeBusyRequest)
        
        let result: GTLRCalendar_FreeBusyResponse = try await withCheckedThrowingContinuation { continuation in
            self.service.executeQuery(query) { ticket, object, error in
                if let err = error {
                    continuation.resume(throwing: err)
                    return
                }
                guard let freeBusy = object as? GTLRCalendar_FreeBusyResponse else {
                    continuation.resume(throwing: NSError(domain:"GoogleCalendar",
                                                          code:-1,
                                                          userInfo:[NSLocalizedDescriptionKey:"Unable to parse FreeBusyResponse"]))
                    return
                }
                continuation.resume(returning: freeBusy)
            }
        }
        
        // Parsing freeBusy response
        var freeIntervals: [DateInterval] = []
        if let calendars = result.calendars, let primary = calendars["primary"] as? GTLRCalendar_FreeBusyCalendar {
            let busyBlocks = primary.busy ?? []
            // Start from now up to inOneWeek
            var cursor = now
            
            for block in busyBlocks {
                guard let startTime = block.start?.date, let endTime = block.end?.date else {
                    continue
                }
                // If there's free time between cursor and startTime
                if startTime > cursor {
                    freeIntervals.append(DateInterval(start: cursor, end: startTime))
                }
                // Move cursor to endTime
                if endTime > cursor {
                    cursor = endTime
                }
            }
            // If there's remaining gap until inOneWeek
            if cursor < inOneWeek {
                freeIntervals.append(DateInterval(start: cursor, end: inOneWeek))
            }
        }
        
        // Filter intervals to find those big enough for desiredDurationInMinutes
        let filtered = freeIntervals.filter { $0.duration >= Double(desiredDurationInMinutes * 60) }
        LoggingService.debug("Found \(filtered.count) open intervals large enough.", component: "GoogleCalendar")
        
        return filtered
    }
    
    /**
     Create an event on the user's primary Google Calendar.
     
     - Parameters:
        - title: event title
        - description: event description
        - startDate: event start time
        - durationMinutes: length in minutes
     
     - Returns: The newly created event ID if successful
     */
    func createCalendarEvent(title: String,
                             description: String,
                             startDate: Date,
                             durationMinutes: Int) async throws -> String {
        LoggingService.debug("Creating calendar event: '\(title)' starting at \(startDate) for \(durationMinutes) minutes", component: "GoogleCalendar")
        
        guard let auth = currentAuthorization else {
            throw NSError(domain: "CalendarIntegrationManager",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No currentAuthorization present"])
        }
        service.authorizer = auth
        
        let endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate.addingTimeInterval(Double(durationMinutes * 60))
        
        let event = GTLRCalendar_Event()
        event.summary = title
        event.descriptionProperty = description
        
        let startDateTime = GTLRDateTime(date: startDate)
        let endDateTime = GTLRDateTime(date: endDate)
        
        event.start = GTLRCalendar_EventDateTime()
        event.start?.dateTime = startDateTime
        
        event.end = GTLRCalendar_EventDateTime()
        event.end?.dateTime = endDateTime
        
        let query = GTLRCalendarQuery_EventsInsert.query(withObject: event, calendarId: "primary")
        
        let createdEvent: GTLRCalendar_Event = try await withCheckedThrowingContinuation { continuation in
            self.service.executeQuery(query) { ticket, object, error in
                if let err = error {
                    continuation.resume(throwing: err)
                    return
                }
                guard let eventObj = object as? GTLRCalendar_Event else {
                    continuation.resume(throwing: NSError(domain:"GoogleCalendar",
                                                          code:-1,
                                                          userInfo:[NSLocalizedDescriptionKey:"Failed to parse created event"]))
                    return
                }
                continuation.resume(returning: eventObj)
            }
        }
        
        let eventId = createdEvent.identifier ?? ""
        LoggingService.success("Event created successfully with ID: \(eventId)", component: "GoogleCalendar")
        
        return eventId
    }
} 