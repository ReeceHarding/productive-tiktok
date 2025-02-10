import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class SignInViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var showResetAlert = false
    @Published var errorMessage: String?
    @Published private(set) var validationMessage = ""
    @Published private(set) var biometricType: BiometricType = .none
    @Published var showBiometricAlert = false
    
    // MARK: - Private Properties
    private let authManager = AuthenticationManager.shared
    private let biometricService = BiometricAuthService.shared
    private var validationTask: Task<Void, Never>?
    private let validationState: ValidationState
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var isValid: Bool {
        isValidEmail(email) && password.count >= 6
    }
    
    // MARK: - Initialization
    init() {
        self.validationState = ValidationState()
        LoggingService.authentication("Initializing SignInViewModel", component: "Authentication")
        
        // Initialize biometric type asynchronously using a weak self capture to avoid a retain cycle.
        Task { [weak self] in
            guard let self = self else { return }
            self.biometricType = self.biometricService.biometricType
            LoggingService.debug("SignIn: Initialized with biometric type: \(self.biometricType.description)", component: "Authentication")
        }
        
        // Setup validation publishers with weak self in closures.
        setupValidationPublishers()
    }
    
    deinit {
        validationTask?.cancel()
        cancellables.removeAll()
        Task { [weak self] in
            guard let self = self else { return }
            await self.validationState.cancelAll()
        }
    }
    
    // MARK: - Private Methods
    private func setupValidationPublishers() {
        Publishers.CombineLatest($email, $password)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] email, password in
                guard let self = self else { return }
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.validateInputs(email: email, password: password)
                }
            }
            .store(in: &cancellables)
    }
    
    private func validateInputs(email: String, password: String) async {
        let emailIsValid = isValidEmail(email)
        let passwordIsValid = password.count >= 6
        
        let newMessage: String
        if email.isEmpty && password.isEmpty {
            newMessage = ""
        } else if !emailIsValid && email.count > 0 {
            newMessage = "Please enter a valid email address"
        } else if !passwordIsValid && password.count > 0 {
            newMessage = "Password must be at least 6 characters"
        } else {
            newMessage = ""
        }
        
        // Update validation message on the main thread.
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            if self.validationMessage != newMessage {
                self.validationMessage = newMessage
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Public Methods
    func updateValidation() async {
        await validationState.trigger()
    }
    
    func checkBiometricAuth() async {
        LoggingService.debug("SignIn: Checking biometric authentication", component: "Authentication")
        if biometricService.isBiometricLoginEnabled {
            // Delay biometric prompt to avoid view update cycle.
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await authenticateWithBiometrics()
        }
    }
    
    func signIn() async {
        guard isValid else {
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                LoggingService.error("SignIn: Form validation failed", component: "Authentication")
                self.showError = true
                self.errorMessage = "Please fill in all fields correctly"
            }
            return
        }
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
        }
        LoggingService.debug("SignIn: Starting sign in process for email: \(email)", component: "Authentication")
        
        do {
            try await authManager.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            LoggingService.success("SignIn: Successfully signed in user", component: "Authentication")
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // After successful sign in, ask user if they want to enable biometric login.
                if self.biometricService.canUseBiometrics() && !self.biometricService.isBiometricLoginEnabled {
                    self.showBiometricAlert = true
                }
            }
            
        } catch let error as AuthError {
            LoggingService.error("SignIn: Failed with AuthError: \(error.description)", component: "Authentication")
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.showError = true
                self.errorMessage = error.description
            }
            
        } catch {
            LoggingService.error("SignIn: Failed with unknown error: \(error.localizedDescription)", component: "Authentication")
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.showError = true
                self.errorMessage = "An unexpected error occurred. Please try again."
            }
        }
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
        }
    }
    
    func authenticateWithBiometrics() async {
        LoggingService.debug("SignIn: Starting biometric authentication", component: "Authentication")
        guard biometricService.canUseBiometrics() else {
            LoggingService.error("SignIn: Biometrics not available", component: "Authentication")
            return
        }
        
        do {
            try await biometricService.authenticateWithBiometrics()
            
            if let credentials = try biometricService.retrieveBiometricCredentials() {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.email = credentials.email
                    self.password = credentials.password
                }
                await signIn()
            }
        } catch BiometricError.userCancel, BiometricError.userFallback {
            // User chose to use password instead—do nothing.
            LoggingService.debug("SignIn: User chose to use password", component: "Authentication")
        } catch {
            LoggingService.error("SignIn: Biometric authentication failed: \(error.localizedDescription)", component: "Authentication")
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.showError = true
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func enableBiometricLogin() {
        do {
            try biometricService.saveBiometricCredentials(email: email, password: password)
            LoggingService.success("SignIn: Successfully enabled biometric login", component: "Authentication")
        } catch {
            LoggingService.error("SignIn: Failed to enable biometric login: \(error.localizedDescription)", component: "Authentication")
            Task { @MainActor in
                showError = true
                errorMessage = "Failed to enable \(biometricType.description). Please try again."
            }
        }
    }
    
    func resetPassword() async {
        guard !email.isEmpty else {
            await MainActor.run {
                LoggingService.error("SignIn: No email provided for password reset", component: "Authentication")
                showError = true
                errorMessage = "Please enter your email address"
            }
            return
        }
        
        guard isValidEmail(email) else {
            await MainActor.run {
                LoggingService.error("SignIn: Invalid email format for password reset", component: "Authentication")
                showError = true
                errorMessage = "Please enter a valid email address"
            }
            return
        }
        
        await MainActor.run { isLoading = true }
        LoggingService.debug("SignIn: Starting password reset for email: \(email)", component: "Authentication")
        
        do {
            try await authManager.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            LoggingService.success("SignIn: Successfully sent password reset email", component: "Authentication")
            await MainActor.run { showResetAlert = true }
            
        } catch {
            LoggingService.error("SignIn: Password reset failed: \(error.localizedDescription)", component: "Authentication")
            await MainActor.run {
                showError = true
                errorMessage = "Failed to send password reset email. Please try again."
            }
        }
        
        await MainActor.run { isLoading = false }
    }
}

// MARK: - Validation State Management
private actor ValidationState {
    private var nextId = 0
    private var callbacks: [Int: @Sendable () async -> Void] = [:]
    
    func register(_ callback: @escaping @Sendable () async -> Void) -> Int {
        let id = nextId
        nextId += 1
        callbacks[id] = callback
        return id
    }
    
    func unregister(_ id: Int) {
        callbacks.removeValue(forKey: id)
    }
    
    func trigger() async {
        for callback in callbacks.values {
            await callback()
        }
    }
    
    func cancelAll() async {
        callbacks.removeAll()
    }
} 