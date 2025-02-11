import Foundation
import UIKit
import SwiftUI
import os.log
import GoogleAPIClientForRESTCore
import GoogleSignIn
import GTMAppAuth

// Add logging for better debugging
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CalendarIntegration")

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
    private var service: GTLRService?
    private let calendarBaseURL = "https://www.googleapis.com/calendar/v3/"
    
    // OAuth token storage
    @Published var currentAuthorization: GIDGoogleUser?
    
    private init() {
        logger.info("CalendarIntegrationManager initialized")
        setupService()
    }
    
    private func setupService() {
        service = GTLRService()
        service?.rootURLString = self.calendarBaseURL
        service?.isRetryEnabled = true
        logger.debug("Calendar service initialized with base URL: \(self.calendarBaseURL)")
    }
    
    /**
     Check if we have a saved auth state from previous sessions. 
     If so, restore it; if not, user must log in.
     */
    func restorePreviousSignInIfAvailable() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let error = error {
                logger.error("Failed to restore sign in: \(error.localizedDescription)")
                return
            }
            if let user = user {
                self?.currentAuthorization = user
                Task {
                    do {
                        let auth = user.fetcherAuthorizer
                        self?.service?.authorizer = auth
                        logger.info("Successfully restored previous sign in")
                    } catch {
                        logger.error("Failed to refresh authentication: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /**
     Start the Google OAuth sign-in flow if needed. 
     Provide a SwiftUI or UIKit context for presenting the authentication.
     */
    func signIn(presentingViewController: UIViewController) async throws {
        logger.debug("Starting Google OAuth sign-in flow...")
        
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw NSError(domain: "CalendarIntegrationManager",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "GIDClientID not found in Info.plist"])
        }
        
        let config = GIDConfiguration(clientID: clientID)
        let scopes = [
            "https://www.googleapis.com/auth/calendar",
            "https://www.googleapis.com/auth/calendar.events"
        ]
        
        do {
            let signInResult = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: scopes
            )
            
            let user = signInResult.user
            currentAuthorization = user
            service?.authorizer = user.fetcherAuthorizer
            logger.info("Successfully signed in with Google")
        } catch {
            logger.error("Sign in failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /**
     Check if we have valid auth:
     - If no, prompt signIn
     - If yes, proceed
     */
    func ensureAuthorized(presentingViewController: UIViewController) async throws {
        if currentAuthorization == nil {
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
        logger.info("Finding free time of at least \(desiredDurationInMinutes) minutes in the next 7 days...")
        
        guard let service = service else {
            throw NSError(domain: "CalendarIntegrationManager",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Calendar service not initialized"])
        }
        
        let now = Date()
        let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        
        // Create the freebusy request using proper GTLR objects
        let freeBusyRequest = GTLRCalendar_FreeBusyRequest()
        freeBusyRequest.timeMin = GTLRDateTime(date: now)
        freeBusyRequest.timeMax = GTLRDateTime(date: sevenDaysFromNow)
        freeBusyRequest.timeZone = TimeZone.current.identifier
        
        // Create the calendar item
        let calendarItem = GTLRCalendar_FreeBusyRequestItem()
        calendarItem.identifier = "primary"
        freeBusyRequest.items = [calendarItem]
        
        // Create the query
        let query = GTLRCalendarQuery_FreebusyQuery.query(withObject: freeBusyRequest)
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[DateInterval], Error>) in
                service.executeQuery(query) { callbackTicket, result, error in
                    if let error = error {
                        logger.error("Free/busy query failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let response = result as? GTLRCalendar_FreeBusyResponse,
                          let calendars = response.calendars as? [String: GTLRCalendar_FreeBusyCalendar],
                          let primary = calendars["primary"] else {
                        logger.error("Invalid response format from free/busy query")
                        continuation.resume(throwing: NSError(domain: "CalendarIntegrationManager",
                                                           code: -1,
                                                           userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
                        return
                    }
                    
                    do {
                        let busyIntervals = try primary.busy?.compactMap { period -> DateInterval? in
                            guard let start = period.start?.date,
                                  let end = period.end?.date else {
                                logger.warning("Invalid date format in busy period")
                                return nil
                            }
                            return DateInterval(start: start, duration: end.timeIntervalSince(start))
                        } ?? []
                        
                        logger.debug("Found \(busyIntervals.count) busy intervals")
                        
                        let freeSlots = self.findFreeSlots(between: busyIntervals,
                                                         from: now,
                                                         to: sevenDaysFromNow,
                                                         minimumDuration: TimeInterval(desiredDurationInMinutes * 60))
                        
                        logger.info("Found \(freeSlots.count) free slots of at least \(desiredDurationInMinutes) minutes")
                        continuation.resume(returning: freeSlots)
                    } catch {
                        logger.error("Error processing free/busy response: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            return result
        } catch {
            logger.error("Failed to fetch free/busy: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func findFreeSlots(between busyPeriods: [DateInterval],
                             from startDate: Date,
                             to endDate: Date,
                             minimumDuration: TimeInterval) -> [DateInterval] {
        var freeSlots: [DateInterval] = []
        var currentStart = startDate
        
        // Sort busy periods by start time
        let sortedBusyPeriods = busyPeriods.sorted { $0.start < $1.start }
        
        // Find gaps between busy periods
        for busy in sortedBusyPeriods {
            let gap = busy.start.timeIntervalSince(currentStart)
            if gap >= minimumDuration {
                freeSlots.append(DateInterval(start: currentStart, duration: gap))
            }
            currentStart = busy.end
        }
        
        // Check final gap to end date
        let finalGap = endDate.timeIntervalSince(currentStart)
        if finalGap >= minimumDuration {
            freeSlots.append(DateInterval(start: currentStart, duration: finalGap))
        }
        
        return freeSlots
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
        logger.debug("Creating calendar event: '\(title)' starting at \(startDate) for \(durationMinutes) minutes")
        
        guard let service = service else {
            throw NSError(domain: "CalendarIntegrationManager",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Calendar service not initialized"])
        }
        
        let endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)!
        
        let eventDict: [String: Any] = [
            "summary": title,
            "description": description,
            "start": ["dateTime": GTLRDateTime(date: startDate).rfc3339String,
                     "timeZone": TimeZone.current.identifier],
            "end": ["dateTime": GTLRDateTime(date: endDate).rfc3339String,
                   "timeZone": TimeZone.current.identifier]
        ]
        
        let path = "/calendars/primary/events"
        let query = GTLRQuery(
            pathURITemplate: path,
            httpMethod: "POST",
            pathParameterNames: []
        )
        query.json = NSMutableDictionary(dictionary: eventDict)
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                service.executeQuery(query) { callbackTicket, result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let response = result as? [String: Any],
                       let eventId = response["id"] as? String {
                        continuation.resume(returning: eventId)
                    } else {
                        continuation.resume(throwing: NSError(domain: "CalendarIntegrationManager",
                                                           code: -1,
                                                           userInfo: [NSLocalizedDescriptionKey: "Invalid response type"]))
                    }
                }
            }
            
            logger.info("Successfully created calendar event with ID: \(result)")
            return result
        } catch {
            logger.error("Failed to create calendar event: \(error.localizedDescription)")
            throw error
        }
    }
} 