import Foundation
import SwiftUI
import os.log

@MainActor
final class NotificationSettingsViewModel: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationSettings")
    private let scheduler = NotificationScheduler.shared
    
    @Published var selectedTimeSegment = 0  // 0=Morning, 1=Midday, 2=Evening
    @Published var recommendedMessage = ""
    @Published var isLoadingMessage = false
    @Published var errorMessage: String?
    @Published var isNotificationsEnabled = false
    
    @AppStorage("dailyNotificationMessage") var storedMessage: String = ""
    @AppStorage("dailyNotificationHour") var storedHour: Int = 9
    @AppStorage("dailyNotificationMinute") var storedMinute: Int = 0
    
    let timeOptions = ["Morning", "Midday", "Evening"]
    let defaultHours = [9, 12, 18]  // 9AM, 12PM, 6PM
    
    init() {
        logger.debug("NotificationSettingsViewModel initialized")
        Task {
            await self.checkNotificationStatus()
            self.restoreStoredTimeSegment()
        }
    }
    
    func generateRecommendedMessage() async {
        self.isLoadingMessage = true
        self.errorMessage = nil
        self.recommendedMessage = ""
        
        do {
            logger.debug("Generating recommended message for time segment: \(self.selectedTimeSegment)")
            
            // Simulate an LLM call with a delay
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let timeOfDay = timeOptions[self.selectedTimeSegment].lowercased()
            self.recommendedMessage = "Time to review your learning insights and put them into practice! Have a productive \(timeOfDay)! 🎯"
            
            logger.debug("Generated message: \(self.recommendedMessage)")
        } catch {
            logger.error("Failed to generate message: \(error.localizedDescription)")
            self.errorMessage = "Failed to generate message: \(error.localizedDescription)"
        }
        
        self.isLoadingMessage = false
    }
    
    func scheduleNotification() async {
        do {
            logger.debug("Attempting to schedule notification")
            
            // Request permission if needed
            try await scheduler.requestNotificationPermissions()
            
            // Get hour & minute from selected time segment
            let hour = defaultHours[self.selectedTimeSegment]
            let minute = 0
            
            // Schedule the notification
            try await scheduler.scheduleDailyNotification(
                hour: hour,
                minute: minute,
                message: self.recommendedMessage
            )
            
            // Save settings
            self.storedMessage = self.recommendedMessage
            self.storedHour = hour
            self.storedMinute = minute
            
            logger.info("Successfully scheduled notification for \(hour):\(minute)")
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
    
    func cancelNotifications() {
        logger.debug("Cancelling all notifications")
        scheduler.cancelAllNotifications()
        
        // Clear stored settings
        self.storedMessage = ""
        self.storedHour = 9
        self.storedMinute = 0
        
        logger.info("All notifications cancelled and settings cleared")
    }
    
    private func checkNotificationStatus() async {
        self.isNotificationsEnabled = await scheduler.checkNotificationStatus()
        logger.debug("Notification status checked: \(self.isNotificationsEnabled)")
    }
    
    private func restoreStoredTimeSegment() {
        // Set the UI segment based on stored hour
        if self.storedHour == 9 && self.storedMinute == 0 {
            self.selectedTimeSegment = 0
        } else if self.storedHour == 12 {
            self.selectedTimeSegment = 1
        } else if self.storedHour == 18 {
            self.selectedTimeSegment = 2
        }
        logger.debug("Restored time segment to: \(self.selectedTimeSegment)")
    }
} 