import SwiftUI
import UIKit

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Content based on current step
                switch viewModel.state.currentStep {
                case .welcome:
                    welcomeStep
                case .secondBrain:
                    secondBrainStep
                case .calendar:
                    calendarStep
                case .completed:
                    EmptyView()
                }
                
                Spacer()
                
                // Navigation buttons
                HStack {
                    Button(action: {
                        impactGenerator.impactOccurred(intensity: 0.5)
                        viewModel.skipOnboarding()
                        dismiss()
                    }) {
                        Text("Skip")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        impactGenerator.impactOccurred(intensity: 0.6)
                        viewModel.nextStep()
                        if viewModel.state.currentStep == .completed {
                            dismiss()
                        }
                    }) {
                        Text(viewModel.state.currentStep == .calendar ? "Get Started" : "Next")
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            notificationGenerator.prepare()
            impactGenerator.prepare()
        }
    }
    
    // MARK: - Step Views
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Welcome to ProductivityTalk!")
                .font(.title)
                .bold()
            
            Text("Let's show you around and help you make the most of your experience.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    private var secondBrainStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Your Second Brain")
                .font(.title)
                .bold()
            
            Text("Tap the brain icon to save key insights from videos to your Second Brain. Build your knowledge library effortlessly!")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            // Example UI
            HStack {
                Image(systemName: "brain")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Tap to save")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
        }
    }
    
    private var calendarStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Turn Knowledge Into Action")
                .font(.title)
                .bold()
            
            Text("Schedule events directly from videos to put your learning into practice. Knowledge becomes power when applied!")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            // Example UI
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Schedule event")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
        }
    }
} 