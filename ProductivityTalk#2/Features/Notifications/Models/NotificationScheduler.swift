import Foundation
import UserNotifications
import os.log

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Notifications")
    
    private init() {
        logger.debug("NotificationScheduler initialized")
    }
    
    /// Request permission to display local notifications
    func requestNotificationPermissions() async throws {
        logger.debug("Requesting notification permissions")
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        if !granted {
            logger.error("User denied notification permissions")
            throw NSError(domain: "Notifications", 
                         code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Notification permissions are required to schedule reminders"])
        }
        logger.info("Notification permissions granted")
    }
    
    /// Schedule a daily notification at a given hour and minute with the given message
    func scheduleDailyNotification(hour: Int, minute: Int, message: String) async throws {
        logger.debug("Scheduling daily notification for \(hour):\(minute) with message: \(message)")
        
        // Clear existing notifications to avoid duplicates
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "ProductivityTalk Reminder"
        content.body = message
        content.sound = .default
        content.badge = 1
        
        // Configure trigger for daily repeat
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "ProductivityTalkDailyNotification",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            logger.info("Successfully scheduled daily notification")
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Cancel all pending notifications
    func cancelAllNotifications() {
        logger.debug("Cancelling all pending notifications")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        logger.info("All pending notifications cancelled")
    }
    
    /// Check if notifications are enabled
    func checkNotificationStatus() async -> Bool {
        logger.debug("Checking notification status")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let isEnabled = settings.authorizationStatus == .authorized
        logger.debug("Notifications enabled: \(isEnabled)")
        return isEnabled
    }
} 