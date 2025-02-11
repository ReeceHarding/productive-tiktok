import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @StateObject private var viewModel = NotificationSettingsViewModel()
    
    var body: some View {
        Form {
            Section {
                if !viewModel.isNotificationsEnabled {
                    notificationPermissionPrompt
                }
            }
            
            Section(header: Text("Notification Time")) {
                Picker("Time of Day", selection: $viewModel.selectedTimeSegment) {
                    ForEach(viewModel.timeOptions.indices, id: \.self) { idx in
                        Text(viewModel.timeOptions[idx])
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Text("Recommended Message")) {
                if viewModel.isLoadingMessage {
                    ProgressView("Generating message...")
                } else if !viewModel.recommendedMessage.isEmpty {
                    TextEditor(text: $viewModel.recommendedMessage)
                        .frame(height: 100)
                } else {
                    Text("No message yet. Tap Generate to get a suggestion.")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    Task {
                        await viewModel.generateRecommendedMessage()
                    }
                }) {
                    Label("Generate Message", systemImage: "wand.and.stars")
                }
                .disabled(viewModel.isLoadingMessage)
            }
            
            Section {
                Button(action: {
                    Task {
                        await viewModel.scheduleNotification()
                    }
                }) {
                    Label("Schedule Daily Notification", systemImage: "bell.badge.fill")
                }
                .disabled(viewModel.isLoadingMessage || viewModel.recommendedMessage.isEmpty)
                
                if !viewModel.storedMessage.isEmpty {
                    Button(role: .destructive, action: {
                        viewModel.cancelNotifications()
                    }) {
                        Label("Cancel Notifications", systemImage: "bell.slash.fill")
                    }
                }
            }
            
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            if !viewModel.storedMessage.isEmpty {
                Section(header: Text("Current Daily Notification")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(viewModel.storedMessage)
                            .font(.body)
                        
                        Divider()
                        
                        Text("Time:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%02d:%02d", viewModel.storedHour, viewModel.storedMinute))
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Notifications")
    }
    
    private var notificationPermissionPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            
            Text("Enable Notifications")
                .font(.headline)
            
            Text("Get daily reminders to review your learning insights and put them into practice.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await viewModel.scheduleNotification()
                }
            }) {
                Text("Enable Notifications")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        NotificationSettingsView()
    }
} 