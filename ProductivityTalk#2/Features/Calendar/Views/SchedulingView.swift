import Foundation
import SwiftUI

/**
 SchedulingView provides a UI for scheduling events based on video content.
 It integrates with CalendarLLMService to generate event proposals and
 CalendarIntegrationManager to find available time slots and create events.
 */
struct SchedulingView: View {
    @StateObject private var viewModel = SchedulingViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let transcript: String
    let videoTitle: String
    
    // Time of day preference
    @State private var selectedTimeOfDay = TimeOfDay.morning
    @State private var customPrompt = ""
    @State private var showingEventDetails = false
    @State private var selectedTimeSlot: DateInterval?
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
                Section(header: Text("Event Preferences")) {
                    Picker("Preferred Time", selection: $selectedTimeOfDay) {
                        ForEach(TimeOfDay.allCases, id: \.self) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                    
                    TextField("Custom Instructions (Optional)", text: $customPrompt)
                }
                
                Section(header: Text("Generated Event")) {
                    if let proposal = viewModel.eventProposal {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(proposal.title)
                                .font(.headline)
                            
                            Text(proposal.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Duration: \(proposal.durationMinutes) minutes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        Button("Find Available Times") {
                            Task {
                                await findAvailableTimes()
                            }
                        }
                        .disabled(isLoading)
                    }
                }
                
                if !viewModel.availableTimeSlots.isEmpty {
                    Section(header: Text("Available Time Slots")) {
                        ForEach(viewModel.availableTimeSlots, id: \.start) { slot in
                            Button(action: {
                                selectedTimeSlot = slot
                                showingEventDetails = true
                            }) {
                                VStack(alignment: .leading) {
                                    Text(formatDate(slot.start))
                                        .font(.headline)
                                    Text("\(formatTime(slot.start)) - \(formatTime(slot.end))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Schedule Event")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .sheet(isPresented: $showingEventDetails) {
                if let proposal = viewModel.eventProposal,
                   let timeSlot = selectedTimeSlot {
                    EventConfirmationView(
                        title: proposal.title,
                        description: proposal.description,
                        startTime: timeSlot.start,
                        durationMinutes: proposal.durationMinutes,
                        onConfirm: { 
                            Task {
                                await scheduleEvent()
                            }
                        }
                    )
                }
            }
            .task {
                await generateEventProposal()
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
    }
    
    private func generateEventProposal() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await viewModel.generateEventProposal(
                transcript: transcript,
                timeOfDay: selectedTimeOfDay.rawValue,
                userPrompt: customPrompt
            )
        } catch {
            errorMessage = "Failed to generate event proposal: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func findAvailableTimes() async {
        guard let proposal = viewModel.eventProposal else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await viewModel.findAvailableTimeSlots(forDuration: proposal.durationMinutes)
        } catch {
            errorMessage = "Failed to find available times: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func scheduleEvent() async {
        guard let proposal = viewModel.eventProposal,
              let timeSlot = selectedTimeSlot else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await viewModel.scheduleEvent(
                title: proposal.title,
                description: proposal.description,
                startTime: timeSlot.start,
                durationMinutes: proposal.durationMinutes
            )
            dismiss()
        } catch {
            errorMessage = "Failed to schedule event: \(error.localizedDescription)"
            showingEventDetails = false
        }
        
        isLoading = false
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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