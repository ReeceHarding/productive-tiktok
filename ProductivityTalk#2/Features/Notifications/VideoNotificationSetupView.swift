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
    @State private var showSuccessAlert = false
    @State private var isEditingMessage = false
    @State private var hasChangedMessage = false
    @State private var showSettingsAlert = false
    @State private var messageHeight: CGFloat = 100
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // For logging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.productivitytalk", category: "VideoNotificationSetup")
    
    // Access managers
    @StateObject private var notificationManager = NotificationManager.shared
    
    // MARK: - UI Components
    
    private var messageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if isEditingMessage || hasChangedMessage {
                    TextEditor(text: $proposedMessage)
                        .frame(minHeight: messageHeight)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ViewHeightKey.self, value: proxy.size.height)
                        })
                        .onPreferenceChange(ViewHeightKey.self) { height in
                            messageHeight = max(100, height)
                        }
                        .onChange(of: proposedMessage) { _ in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hasChangedMessage = true
                            }
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .accessibilityLabel("Notification message")
                        .accessibilityHint("Enter the message you want to receive as a reminder")
                } else {
                    Text(proposedMessage)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .frame(minHeight: 100)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isEditingMessage = true
                            }
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Tap to edit notification message")
                }
                
                if !isEditingMessage && !hasChangedMessage {
                    Text("Tap to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
        } header: {
            Label("Notification Message", systemImage: "bell.badge")
                .textCase(nil)
                .font(.headline)
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
        }
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : .white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var timeSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                    DatePicker("Reminder Time", selection: $proposedDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .onChange(of: proposedDate) { _ in
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                }
                .padding(.vertical, 8)
                
                // Show relative time
                Text(relativeTimeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }
        } header: {
            Text("When to Remind You")
                .textCase(nil)
                .font(.headline)
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
        }
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : .white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var scheduleButton: some View {
        Button(action: scheduleTapped) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Scheduling...")
                } else {
                    Image(systemName: "bell.badge.fill")
                        .imageScale(.large)
                    Text("Set Reminder")
                        .fontWeight(.semibold)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isLoading ? Color.blue.opacity(0.8) : Color.blue)
        .foregroundColor(.white)
        .cornerRadius(16)
        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        .disabled(isLoading || proposedMessage.isEmpty)
        .opacity(proposedMessage.isEmpty ? 0.6 : 1.0)
        .accessibilityLabel(isLoading ? "Scheduling reminder" : "Set reminder")
        .accessibilityHint("Double tap to schedule the reminder")
    }
    
    private var relativeTimeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: proposedDate, relativeTo: Date())
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if let errorMessage = errorMessage {
                            ErrorBanner(message: errorMessage)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        VStack(spacing: 16) {
                            messageSection
                                .padding(.horizontal)
                            
                            timeSection
                                .padding(.horizontal)
                            
                            scheduleButton
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical)
                }
                .scrollDismissesKeyboard(.immediately)
                
                if isLoading && proposedMessage.isEmpty {
                    LoadingOverlay()
                        .transition(.opacity)
                }
                
                // Toast
                if showToast {
                    ToastView(message: toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle("Set Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Haptic feedback
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismissView()
                    }
                }
                
                if isEditingMessage {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isEditingMessage = false
                            }
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                }
            }
            #endif
            .alert("Reminder Set!", isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismissView()
                }
            } message: {
                Text("We'll remind you \(relativeTimeDescription)")
            }
            .alert("Enable Notifications", isPresented: $showSettingsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
            } message: {
                Text("Please enable notifications in Settings to receive reminders.")
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
        
        guard !proposedMessage.isEmpty else {
            showToast(message: "Please enter a reminder message")
            return
        }
        
        isLoading = true
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Make sure we have permission
        notificationManager.requestAuthorizationIfNeeded { (granted: Bool) in
            DispatchQueue.main.async {
                self.isLoading = false
                if granted {
                    self.notificationManager.scheduleNotification(at: self.proposedDate, message: self.proposedMessage, videoId: self.videoId)
                    self.logger.info("Notification scheduled. Showing success alert.")
                    withAnimation {
                        self.showSuccessAlert = true
                    }
                } else {
                    self.logger.warning("User did not grant local notification permission.")
                    self.showSettingsAlert = true
                }
            }
        }
    }
    
    private func showToast(message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showToast = true
        }
        // Hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showToast = false
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
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.proposedMessage = message
                    self.proposedDate = recommendedTime
                    self.isLoading = false
                }
            }
            logger.debug("Got GPT proposal => \(message), date=\(recommendedTime)")
        } catch {
            logger.error("Failed GPT call for notification. \(error.localizedDescription)")
            await MainActor.run {
                withAnimation {
                    self.isLoading = false
                    self.errorMessage = "Could not generate a recommended notification. You can still edit manually."
                    // Provide fallback
                    self.proposedMessage = "Your reminder from the video!"
                    self.proposedDate = Date().addingTimeInterval(60*60*8) // 8 hours from now
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .foregroundColor(.white)
            Text(message)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .cornerRadius(12)
        .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

struct LoadingOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .transition(.opacity)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text("Generating reminder...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : .white)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading, generating reminder")
    }
}

struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
            .shadow(radius: 10)
            .padding(.bottom, 32)
    }
}

// MARK: - Preview
struct VideoNotificationSetupView_Previews: PreviewProvider {
    static var previews: some View {
        VideoNotificationSetupView(
            videoId: "preview-id",
            originalTranscript: "Sample transcript for preview"
        )
    }
} 