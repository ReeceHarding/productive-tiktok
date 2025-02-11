import SwiftUI
import os.log
import GoogleSignIn
import GTMAppAuth
import GoogleAPIClientForRESTCore
import Foundation
import OSLog

/**
 CalendarIntegrationManager is responsible for:
 - Authenticating user with Google (OAuth 2.0).
 - Checking or refreshing tokens.
 - Creating events in the user's primary calendar.
 - Querying free/busy times to find open slots.

 This version uses the official GTLRCalendar classes instead of custom GTLRQuery.
 
 Make sure you have 'pod GoogleAPIClientForREST/Calendar' or a SwiftPM approach that brings in
 the GTLRCalendar library.
 */
final class CalendarIntegrationManager: ObservableObject {
    
    static let shared = CalendarIntegrationManager()
    
    // Logger for debug
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CalendarIntegrationManager", category: "Calendar")
    
    // The GTLRService for calendar
    private var service: GTLRService
    
    // Calendar base URL
    private let calendarBaseURL = "https://www.googleapis.com/calendar/v3"
    
    // Current authorization state
    private var currentAuthorization: GIDGoogleUser?
    
    private init() {
        self.service = GTLRService()
        service.rootURLString = calendarBaseURL
        setupService()
    }
    
    // Setup GTLR service object
    private func setupService() {
        service.shouldFetchNextPages = true
        service.isRetryEnabled = true
        logger.debug("Calendar service configured with URL: \(self.calendarBaseURL)")
    }
    
    func ensureAuthorization(completion: @escaping (Bool) -> Void) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logger.debug("Starting authorization check")
            if self.service.authorizer != nil {
                self.logger.debug("Valid token found")
                completion(true)
            } else {
                self.logger.debug("No valid token, initiating sign in")
                self.signIn { success in
                    if success {
                        self.logger.debug("Sign in successful")
                        completion(true)
                    } else {
                        self.logger.debug("Sign in failed")
                        completion(false)
                    }
                }
            }
        }
        DispatchQueue.main.async(execute: workItem)
    }
    
    /**
     Check if we have a saved auth state from previous sessions.
     If so, restore it; if not, user must log in.
     */
    func restorePreviousSignInIfAvailable() {
        logger.debug("Attempting to restore previous Google sign-in.")
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let error = error {
                self?.logger.error("Failed to restore sign in: \(error.localizedDescription)")
                return
            }
            guard let self = self else { return }
            if let user = user {
                self.currentAuthorization = user
                Task {
                    let auth = user.fetcherAuthorizer
                    self.service.authorizer = auth
                    self.logger.info("Successfully restored previous sign in.")
                }
            }
        }
    }
    
    /**
     Start the Google OAuth sign-in flow if needed.
     Provide a SwiftUI or UIKit context for presenting the authentication.
     */
    private func signIn(completion: @escaping (Bool) -> Void) {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let rootViewController = scene?.windows.first?.rootViewController ?? UIViewController()
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] signInResult, error in
            if let error = error {
                self?.logger.error("Sign in failed: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let signInResult = signInResult else {
                self?.logger.error("Sign in error: no user object returned.")
                completion(false)
                return
            }
            
            guard let self = self else { return }
            self.currentAuthorization = signInResult.user
            self.service.authorizer = signInResult.user.fetcherAuthorizer
            self.logger.info("Successfully signed in with Google. User: \(signInResult.user.userID ?? "N/A")")
            completion(true)
        }
    }
    
    /**
     Check if we have valid auth:
     - If not, prompt signIn
     - If yes, proceed
     
     Must be called on main actor or ensure main thread usage for signIn because it triggers UI.
     */
    func ensureAuthorized(presentingViewController: UIViewController) async throws {
        logger.debug("ensureAuthorized called - Checking for existing auth.")
        if currentAuthorization == nil {
            logger.debug("No currentAuthorization, so calling signIn() now.")
            return try await withCheckedThrowingContinuation { continuation in
                signIn { success in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "CalendarIntegrationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sign in"]))
                    }
                }
            }
        } else {
            logger.debug("Already authorized - continuing.")
        }
    }
    
    /**
     Finds open time slots within a given day range using the official GTLRCalendarQuery_Freebusy.
     
     - Parameter desiredDurationInMinutes: Duration that user wants to block off
     - Returns: A list of Date intervals representing free time windows
     */
    func findFreeTime(durationMinutes: Int, completion: @escaping (Result<[DateInterval], Error>) -> Void) {
        self.logger.info("🔍 Finding free time slots of \(durationMinutes) minutes in next 7 days")
        
        let now = Date()
        let calendar = Calendar.current
        guard let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now) else {
            self.logger.error("❌ Could not compute next 7 days from now.")
            completion(.failure(NSError(domain: "CalendarIntegrationManager",
                                     code: -2,
                                     userInfo: [NSLocalizedDescriptionKey: "Could not compute next 7 days from now"])))
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        
        // Build a FreeBusyRequest object using generic GTLRObject
        let freeBusyReq = GTLRObject()
        freeBusyReq.json = [
            "timeMin": dateFormatter.string(from: now),
            "timeMax": dateFormatter.string(from: sevenDaysFromNow),
            "timeZone": TimeZone.current.identifier,
            "items": [["id": "primary"]]
        ]
        
        // Create query using generic GTLRQuery
        let query = GTLRQuery(
            pathURITemplate: "calendar/v3/freeBusy",
            httpMethod: "POST",
            pathParameterNames: []
        )
        query.bodyObject = freeBusyReq
        query.expectedObjectClass = GTLRObject.self
        
        self.logger.debug("📤 Executing Calendar FreeBusy query")
        
        service.executeQuery(query) { [weak self] (ticket, result, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Failed to fetch free/busy: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let response = result as? GTLRObject,
                  let jsonDict = response.json as? [String: Any],
                  let calendars = jsonDict["calendars"] as? [String: [String: Any]],
                  let primaryFB = calendars["primary"],
                  let busyPeriods = primaryFB["busy"] as? [[String: String]] else {
                let unknownErr = NSError(domain: "CalendarIntegrationManager",
                                       code: -3,
                                       userInfo: [NSLocalizedDescriptionKey: "Invalid free/busy response format."])
                self.logger.error("❌ FreeBusy response was not in expected format or missing 'primary' calendar.")
                completion(.failure(unknownErr))
                return
            }
            
            var busyIntervals: [DateInterval] = []
            
            for period in busyPeriods {
                guard let startStr = period["start"],
                      let endStr = period["end"],
                      let startDate = dateFormatter.date(from: startStr),
                      let endDate = dateFormatter.date(from: endStr) else {
                    continue
                }
                busyIntervals.append(DateInterval(start: startDate, end: endDate))
            }
            
            let freeSlots = self.findFreeSlots(
                between: busyIntervals,
                from: now,
                to: sevenDaysFromNow,
                minimumDuration: TimeInterval(durationMinutes * 60)
            )
            self.logger.info("✅ Found \(freeSlots.count) available time slots")
            completion(.success(freeSlots))
        }
    }
    
    private func findFreeSlots(between busyPeriods: [DateInterval],
                               from startDate: Date,
                               to endDate: Date,
                               minimumDuration: TimeInterval) -> [DateInterval] {
        logger.debug("Determining free slots from \(startDate) to \(endDate), given busy intervals. total busy intervals=\(busyPeriods.count)")
        var freeSlots: [DateInterval] = []
        var currentStart = startDate
        
        // Sort busy periods by start time
        let sortedBusy = busyPeriods.sorted { $0.start < $1.start }
        
        for busy in sortedBusy {
            let gap = busy.start.timeIntervalSince(currentStart)
            if gap >= minimumDuration {
                freeSlots.append(DateInterval(start: currentStart, duration: gap))
            }
            // Move currentStart to the end of this busy block if that is further in time
            if busy.end > currentStart {
                currentStart = busy.end
            }
        }
        
        // Finally, check the gap until endDate
        let finalGap = endDate.timeIntervalSince(currentStart)
        if finalGap >= minimumDuration {
            freeSlots.append(DateInterval(start: currentStart, duration: finalGap))
        }
        
        logger.debug("Returning \(freeSlots.count) free slots to caller.")
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
    func createEvent(title: String, description: String, startDate: Date, durationMinutes: Int, completion: @escaping (Result<String, Error>) -> Void) {
        self.logger.debug("Creating calendar event: '\(title)' starting at \(startDate) for \(durationMinutes) minutes.")
        
        let endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        
        // Build the event object using generic GTLRObject
        let event = GTLRObject()
        event.json = [
            "summary": title,
            "description": description,
            "start": [
                "dateTime": dateFormatter.string(from: startDate),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": dateFormatter.string(from: endDate),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        // Create insert query using generic GTLRQuery
        let query = GTLRQuery(
            pathURITemplate: "calendar/v3/calendars/{calendarId}/events",
            httpMethod: "POST",
            pathParameterNames: ["calendarId"]
        )
        query.additionalURLQueryParameters = ["calendarId": "primary"]
        query.bodyObject = event
        query.expectedObjectClass = GTLRObject.self
        
        self.logger.debug("Executing event insert query now.")
        service.executeQuery(query) { [weak self] ticket, result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to create calendar event: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let createdEvent = result as? GTLRObject,
                  let json = createdEvent.json as? [String: Any],
                  let eventId = json["id"] as? String else {
                let invalidRespError = NSError(domain: "CalendarIntegrationManager",
                                             code: -2,
                                             userInfo: [NSLocalizedDescriptionKey: "Invalid event response or missing event ID"])
                completion(.failure(invalidRespError))
                return
            }
            self.logger.info("Successfully created calendar event with ID: \(eventId)")
            completion(.success(eventId))
        }
    }
} 