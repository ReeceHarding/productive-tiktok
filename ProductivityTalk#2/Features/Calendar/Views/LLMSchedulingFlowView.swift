import SwiftUI
import EventKit

@_exported import class EventKit.EKEventStore
@_exported import class EventKit.EKEvent

public struct LLMSchedulingFlowView: View {
    let transcript: String
    @StateObject private var viewModel: CalendarSchedulingViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(transcript: String) {
        self.transcript = transcript
        self._viewModel = StateObject(wrappedValue: CalendarSchedulingViewModel(transcript: transcript))
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Time of Day Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("When would you like to schedule this?")
                        .font(.headline)
                    
                    Picker("Time of Day", selection: $viewModel.selectedTimeOfDay) {
                        Text("Select a time").tag(Optional<CalendarSchedulingViewModel.TimeOfDayOption>.none)
                        ForEach(CalendarSchedulingViewModel.TimeOfDayOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(Optional(option))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                if viewModel.isLoading {
                    ProgressView("Generating suggestions...")
                        .progressViewStyle(.circular)
                } else {
                    // Generated Event Details
                    if !viewModel.generatedTitle.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Suggested Event")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.generatedTitle)
                                    .font(.title3)
                                    .bold()
                                
                                Text(viewModel.generatedDescription)
                                    .foregroundColor(.secondary)
                                
                                Text("Duration: \(viewModel.generatedDurationMinutes) minutes")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 2)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Scheduled Time Display
                    if let start = viewModel.scheduledStart,
                       let end = viewModel.scheduledEnd {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scheduled Time")
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: "calendar")
                                Text(start, style: .date)
                            }
                            
                            HStack {
                                Image(systemName: "clock")
                                Text(start, style: .time)
                                Text("-")
                                Text(end, style: .time)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 2)
                        .padding(.horizontal)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    if viewModel.selectedTimeOfDay != nil {
                        if viewModel.generatedTitle.isEmpty {
                            Button {
                                Task {
                                    await viewModel.generateEventSuggestion()
                                }
                            } label: {
                                Text("Generate Event Details")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if viewModel.scheduledStart == nil {
                            Button {
                                Task {
                                    await viewModel.findFreeSlot()
                                }
                            } label: {
                                Text("Find Available Time")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                Task {
                                    do {
                                        try await viewModel.requestCalendarAccess()
                                        try await viewModel.createLocalCalendarEvent()
                                        dismiss()
                                    } catch {
                                        // Error handling is already done in the ViewModel
                                    }
                                }
                            } label: {
                                Text("Schedule Event")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Schedule Event")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    do {
                        try await viewModel.requestCalendarAccess()
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

#Preview {
    LLMSchedulingFlowView(transcript: "Example transcript for testing the scheduling flow.")
} 