import Foundation

struct OnboardingState: Codable {
    var hasCompletedOnboarding: Bool
    var currentStep: OnboardingStep
    
    enum OnboardingStep: Int, Codable {
        case welcome
        case secondBrain
        case calendar
        case completed
    }
    
    static var `default`: OnboardingState {
        OnboardingState(hasCompletedOnboarding: false, currentStep: .welcome)
    }
    
    static func load() -> OnboardingState {
        guard let data = UserDefaults.standard.data(forKey: "onboardingState"),
              let state = try? JSONDecoder().decode(OnboardingState.self, from: data) else {
            return .default
        }
        return state
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "onboardingState")
        }
    }
} 