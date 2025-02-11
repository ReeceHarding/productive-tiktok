import SwiftUI
import OSLog
import UIKit
#if os(iOS)
import UserNotifications
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
    
    @State private var proposedMessage: String = ""
    @State private var proposedDate: Date = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // For logging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.productivitytalk", category: "VideoNotificationSetup")
    
    // Access managers
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Notification Message")) {
                    TextField("Enter your reminder", text: $proposedMessage)
                }
                
                Section(header: Text("Time")) {
                    DatePicker("Choose Time", selection: $proposedDate, displayedComponents: .hourAndMinute)
                }
                
                Section {
                    Button(action: {
                        scheduleTapped()
                    }) {
                        Text("Schedule Notification")
                    }
                }
            }
            .navigationTitle("Set Notification")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismissView()
                    }
                }
            }
            #endif
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        ProgressView("Loading...")
                            .scaleEffect(1.2)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(12)
                    }
                }
            }
        }
        .task {
            await generateProposalIfNeeded()
        }
    }
    
    private func dismissView() {
        logger.debug("Dismissing VideoNotificationSetupView.")
        #if os(iOS)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.dismiss(animated: true)
        }
        #endif
    }
    
    private func scheduleTapped() {
        logger.debug("User tapped schedule with message='\(proposedMessage)', date=\(proposedDate)")
        isLoading = true
        // Make sure we have permission
        notificationManager.requestAuthorizationIfNeeded { (granted: Bool) in
            DispatchQueue.main.async {
                self.isLoading = false
                if granted {
                    self.notificationManager.scheduleNotification(at: self.proposedDate, message: self.proposedMessage, videoId: self.videoId)
                    self.logger.info("Notification scheduled. Dismissing setup view.")
                    self.dismissView()
                } else {
                    self.logger.warning("User did not grant local notification permission.")
                    self.errorMessage = "Please enable notifications in Settings."
                }
            }
        }
    }
    
    // Retrieve GPT proposal if needed
    private func generateProposalIfNeeded() async {
        guard proposedMessage.isEmpty else {
            logger.debug("Proposal already populated. Skipping GPT call.")
            return
        }
        logger.debug("Fetching GPT-based proposal for transcript of length: \(originalTranscript.count).")
        isLoading = true
        do {
            let (message, recommendedTime) = try await NotificationLLMService.shared.generateNotificationProposal(transcript: originalTranscript)
            DispatchQueue.main.async {
                self.proposedMessage = message
                self.proposedDate = recommendedTime
                self.isLoading = false
            }
            logger.debug("Got GPT proposal => \(message), date=\(recommendedTime)")
        } catch {
            logger.error("Failed GPT call for notification. \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Could not generate a recommended notification. You can still edit manually."
                // Provide fallback
                self.proposedMessage = "Your reminder from the video!"
                self.proposedDate = Date().addingTimeInterval(60*60*8) // 8 hours from now
            }
        }
    }
} 