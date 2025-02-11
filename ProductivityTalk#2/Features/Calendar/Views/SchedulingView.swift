import Foundation
import SwiftUI
import OSLog

/**
 SchedulingView provides a UI for scheduling events based on video content.
 It integrates with CalendarLLMService to generate event proposals and
 CalendarIntegrationManager to find available time slots and create events.
 */
struct SchedulingView: View {
    let transcript: String
    let videoTitle: String
    
    @StateObject private var viewModel = SchedulingViewModel(calendarManager: CalendarIntegrationManager.shared)
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTimeOfDay = TimeOfDay.morning
    @State private var customPrompt = ""
    @State private var showingTimeSlots = false
    @State private var selectedInterval: DateInterval?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    enum TimeOfDay: String, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case anytime = "Anytime"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Picker("Time of Day", selection: $selectedTimeOfDay) {
                        ForEach(TimeOfDay.allCases, id: \.self) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                    TextField("Custom Prompt (optional)", text: $customPrompt)
                }
                
                // Proposed event details
                Section(header: Text("Proposed Event")) {
                    if let proposal = viewModel.eventProposal {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(proposal.title)
                                .font(.headline)
                            Text(proposal.description)
                                .font(.subheadline)
                            Text("Duration: \(proposal.durationMinutes) minutes")
                                .font(.footnote)
                        }
                        Button(action: {
                            Task {
                                await findAvailableTimes()
                            }
                        }) {
                            Text("Find Available Times")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    } else {
                        Text("No proposal yet. Tap 'Generate Proposal'")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Time slots
                if showingTimeSlots && !viewModel.availableTimeSlots.isEmpty {
                    Section(header: Text("Available Time Slots")) {
                        ForEach(viewModel.availableTimeSlots, id: \.start) { slot in
                            Button(action: {
                                self.selectedInterval = slot
                                self.scheduleIfConfirmed()
                            }) {
                                VStack(alignment: .leading) {
                                    Text(shortDate(slot.start))
                                        .font(.headline)
                                    Text("\(shortTime(slot.start)) - \(shortTime(slot.end))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Schedule from \(videoTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate Proposal") {
                        Task { await generateProposal() }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.2)
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
    }
    
    private func generateProposal() async {
        isLoading = true
        do {
            try await viewModel.generateEventProposal(
                transcript: transcript,
                timeOfDay: selectedTimeOfDay.rawValue.lowercased(),
                userPrompt: customPrompt
            )
        } catch {
            errorMessage = "Failed generating proposal: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private func findAvailableTimes() async {
        guard let proposal = viewModel.eventProposal else { return }
        isLoading = true
        do {
            try await viewModel.findAvailableTimeSlots(forDuration: proposal.durationMinutes)
            self.showingTimeSlots = true
        } catch {
            errorMessage = "Failed to find time slots: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private func scheduleIfConfirmed() {
        guard let proposal = viewModel.eventProposal,
              let timeSlot = selectedInterval else {
            return
        }
        // Confirm scheduling
        Task {
            isLoading = true
            do {
                try await viewModel.scheduleEvent(
                    title: proposal.title,
                    description: proposal.description,
                    startTime: timeSlot.start,
                    durationMinutes: proposal.durationMinutes
                )
                dismiss() // close
            } catch {
                errorMessage = "Error scheduling: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
    
    private func shortTime(_ date: Date) -> String {
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        return tf.string(from: date)
    }
}

struct EventConfirmationView: View {
    let title: String
    let description: String
    let startTime: Date
    let durationMinutes: Int
    let onConfirm: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headline)
                        
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Start Time: \(formatDateTime(startTime))")
                            .font(.subheadline)
                        
                        Text("Duration: \(durationMinutes) minutes")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Confirm Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Schedule") {
                    onConfirm()
                    dismiss()
                }
            )
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SchedulingView(
        transcript: "Sample transcript discussing a potential meeting next week",
        videoTitle: "Team Planning Session"
    )
} 