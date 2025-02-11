import Foundation
import UserNotifications
import OSLog

/**
 NotificationManager handles local notification permission requests and scheduling.
 
 Thoroughly logs each operation for clarity.
 */
class NotificationManager: ObservableObject {
    
    static let shared = NotificationManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.productivitytalk", category: "NotificationManager")
    
    private init() {
        logger.debug("NotificationManager initialized.")
    }
    
    /**
     Request local notification authorization if not already granted.
     - Completion returns a Bool: `true` if authorized, `false` otherwise.
     */
    func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        logger.debug("Requesting local notification authorization if needed.")
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                // Request
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        self.logger.error("Failed requesting authorization: \(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    self.logger.debug("Notification authorization result: \(granted)")
                    completion(granted)
                }
            case .denied:
                self.logger.debug("Notification authorization denied previously.")
                completion(false)
            case .authorized, .provisional, .ephemeral:
                self.logger.debug("Notification authorization already granted.")
                completion(true)
            @unknown default:
                self.logger.debug("Unknown authorization status encountered.")
                completion(false)
            }
        }
    }
    
    /**
     Schedule a local notification at the specified date/time with the given message.
     
     - Parameter date: The date/time to fire the notification
     - Parameter message: The short text to display in the notification
     - Parameter videoId: (Optional) Ties back to a particular video. Could be used for future expansions or to open a certain screen.
     */
    func scheduleNotification(at date: Date, message: String, videoId: String? = nil) {
        logger.debug("Scheduling notification at \(date) with message: \(message)")
        
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Video Reminder"
        content.body = message
        content.sound = .default
        
        // Add any relevant userInfo
        if let videoId = videoId {
            content.userInfo = ["videoId": videoId]
        }
        
        // Trigger date
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        // Unique request identifier
        let requestId = UUID().uuidString
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        
        // Schedule
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Failed to schedule local notification: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification scheduled with ID: \(requestId) at \(date)")
            }
        }
    }
} 