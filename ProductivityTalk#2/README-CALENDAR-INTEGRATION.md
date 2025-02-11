# Updated Calendar Integration

This document merges our new approach (with GoogleAPIClientForRESTCore) into the existing code. Follow the steps below:

1. Prerequisites:
- Google Cloud project with Calendar API enabled.
- OAuth credentials in Info.plist (GIDClientID).
- GoogleSignIn pod or Swift package set up.

2. Integration:
- Use CalendarIntegrationManager.shared from anywhere in your SwiftUI code.
- ensureAuthorized(...) to prompt sign in if needed.
- findFreeTime or createCalendarEvent for scheduling or free/busy checks.

3. Sample:
```swift
Task {
  do {
    try await CalendarIntegrationManager.shared.ensureAuthorized(presentingViewController: UIHostingController(rootView: self))
    let intervals = try await CalendarIntegrationManager.shared.findFreeTime(desiredDurationInMinutes: 60)
    print("Available intervals:", intervals)
  } catch {
    print("Failed: \(error)")
  }
}
```

4. ViewModel:
- For a new event, call createCalendarEvent(title:description:startDate:durationMinutes:).
- Logging is in CalendarIntegrationManager. Watch Xcode console.

Done! This is the official reference for the new approach to Calendar integration. 