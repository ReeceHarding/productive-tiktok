import Foundation
import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published private(set) var state: OnboardingState
    @Published var showOnboarding = false
    
    init() {
        self.state = OnboardingState.load()
        LoggingService.debug("Initialized OnboardingViewModel with state: \(state.currentStep)", component: "Onboarding")
    }
    
    func startOnboarding() {
        guard !state.hasCompletedOnboarding else { return }
        state.currentStep = .welcome
        showOnboarding = true
        LoggingService.debug("Starting onboarding flow", component: "Onboarding")
    }
    
    func nextStep() {
        switch state.currentStep {
        case .welcome:
            state.currentStep = .secondBrain
        case .secondBrain:
            state.currentStep = .notifications
        case .notifications:
            completeOnboarding()
        case .completed:
            break
        }
        LoggingService.debug("Moving to onboarding step: \(state.currentStep)", component: "Onboarding")
        state.save()
    }
    
    func completeOnboarding() {
        state.hasCompletedOnboarding = true
        state.currentStep = .completed
        showOnboarding = false
        state.save()
        LoggingService.success("Completed onboarding flow", component: "Onboarding")
    }
    
    func skipOnboarding() {
        completeOnboarding()
        LoggingService.debug("Skipped onboarding flow", component: "Onboarding")
    }
} 