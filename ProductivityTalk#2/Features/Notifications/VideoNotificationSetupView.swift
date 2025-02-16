import SwiftUI
import Foundation
import os

#if os(iOS)
import UserNotifications
import UIKit
#endif

/**
 VideoNotificationSetupView displays:
 1) GPT-suggested notification text
 2) Proposed time
 The user can edit both, then schedule the notification if they confirm.
 
 Thoroughly logs each operation for clarity.
 */
struct VideoNotificationSetupView: View {
    let videoId: String
    let originalTranscript: String
    
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var message: String = ""
    @State private var selectedTime: Date = Date()
    @State private var isGeneratingProposal = false
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) var dismiss
    
    init(videoId: String, originalTranscript: String) {
        self.videoId = videoId
        self.originalTranscript = originalTranscript
        LoggingService.debug("🔔 Initializing notification setup for video \(videoId)", component: "NotificationSetup")
        LoggingService.debug("📝 Transcript length: \(originalTranscript.count) characters", component: "NotificationSetup")
    }
    
    var body: some View {
        NavigationView {
            Form {
                if showError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Notification Message")) {
                    TextField("Enter your reminder", text: $message)
                        .onChange(of: message) { newValue in
                            LoggingService.debug("User edited message to: \(newValue)", component: "NotificationSetup")
                        }
                }
                
                Section(header: Text("Time")) {
                    DatePicker("Choose Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        #else
                        .datePickerStyle(.graphical)
                        #endif
                        .onChange(of: selectedTime) { newValue in
                            LoggingService.debug("User selected new time: \(newValue)", component: "NotificationSetup")
                        }
                }
                
                Section {
                    Button(action: {
                        LoggingService.debug("Schedule button tapped", component: "NotificationSetup")
                        Task {
                            await scheduleTapped()
                        }
                    }) {
                        HStack {
                            Text("Schedule Notification")
                            if isGeneratingProposal {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isGeneratingProposal)
                }
            }
            .navigationTitle("Set Notification")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        LoggingService.debug("Cancel button tapped", component: "NotificationSetup")
                        dismiss()
                    }
                }
            }
            #endif
            .onAppear {
                LoggingService.debug("🎬 NotificationSetupView appeared for video \(videoId)", component: "NotificationSetup")
                generateProposalIfNeeded()
            }
        }
    }
    
    private func scheduleTapped() async {
        LoggingService.debug("🕐 Scheduling notification for video \(videoId) at \(selectedTime)", component: "NotificationSetup")
        
        guard !message.isEmpty else {
            LoggingService.error("❌ Cannot schedule - message is empty", component: "NotificationSetup")
            errorMessage = "Please enter a notification message"
            showError = true
            return
        }
        
        await MainActor.run { isGeneratingProposal = true }
        
        Task {
            do {
                try await notificationManager.requestAuthorizationIfNeeded { granted in
                    if !granted {
                        Task { @MainActor in
                            self.errorMessage = "Notification permissions not granted"
                            self.showError = true
                            self.isGeneratingProposal = false
                        }
                        return
                    }
                }
                try await notificationManager.scheduleNotification(
                    at: selectedTime,
                    message: message,
                    videoId: videoId
                )
                LoggingService.success("✅ Successfully scheduled notification", component: "NotificationSetup")
                dismiss()
            } catch {
                LoggingService.error("❌ Failed to schedule notification: \(error.localizedDescription)", component: "NotificationSetup")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func generateProposalIfNeeded() {
        guard message.isEmpty else {
            LoggingService.debug("⏭️ Skipping proposal generation - message already set", component: "NotificationSetup")
            return
        }
        
        LoggingService.debug("🤖 Starting proposal generation for video \(videoId)", component: "NotificationSetup")
        isGeneratingProposal = true
        
        Task {
            do {
                let (proposedMessage, proposedTime) = try await NotificationLLMService.shared.generateNotificationProposal(
                    transcript: originalTranscript
                )
                await MainActor.run {
                    message = proposedMessage
                    selectedTime = proposedTime
                    isGeneratingProposal = false
                }
                LoggingService.success("✅ Generated notification proposal: \(proposedMessage)", component: "NotificationSetup")
            } catch {
                LoggingService.error("❌ Failed to generate proposal: \(error.localizedDescription)", component: "NotificationSetup")
                await MainActor.run {
                    isGeneratingProposal = false
                    errorMessage = "Failed to generate notification message. Please try again or enter your own message."
                    showError = true
                }
            }
        }
    }
} 