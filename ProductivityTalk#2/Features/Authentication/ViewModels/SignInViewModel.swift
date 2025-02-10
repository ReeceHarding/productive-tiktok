import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SignInViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var showResetAlert = false
    @Published var errorMessage: String?
    @Published private(set) var validationMessage = ""
    @Published private(set) var biometricType: BiometricType = .none
    @Published var showBiometricAlert = false
    
    private let authManager = AuthenticationManager.shared
    private let biometricService = BiometricAuthService.shared
    
    init() {
        biometricType = biometricService.biometricType
        if biometricService.isBiometricLoginEnabled {
            Task {
                await authenticateWithBiometrics()
            }
        }
    }
    
    var isValid: Bool {
        let emailIsValid = isValidEmail(email)
        let passwordIsValid = password.count >= 6
        
        // Update validation message
        if email.isEmpty && password.isEmpty {
            validationMessage = ""
        } else if !emailIsValid && email.count > 0 {
            validationMessage = "Please enter a valid email address"
        } else if !passwordIsValid && password.count > 0 {
            validationMessage = "Password must be at least 6 characters"
        } else {
            validationMessage = ""
        }
        
        return emailIsValid && passwordIsValid
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    func signIn() async {
        guard isValid else {
            LoggingService.error("❌ SignIn: Form validation failed", component: "Authentication")
            showError = true
            errorMessage = "Please fill in all fields correctly"
            return
        }
        
        isLoading = true
        LoggingService.debug("🔐 SignIn: Starting sign in process for email: \(email)", component: "Authentication")
        
        do {
            try await authManager.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            LoggingService.success("✅ SignIn: Successfully signed in user", component: "Authentication")
            
            // After successful sign in, ask user if they want to enable biometric login
            if biometricService.canUseBiometrics() && !biometricService.isBiometricLoginEnabled {
                showBiometricAlert = true
            }
            
        } catch let error as AuthError {
            LoggingService.error("❌ SignIn: Failed with AuthError: \(error.description)", component: "Authentication")
            showError = true
            errorMessage = error.description
            
        } catch {
            LoggingService.error("❌ SignIn: Failed with unknown error: \(error.localizedDescription)", component: "Authentication")
            showError = true
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
    
    func authenticateWithBiometrics() async {
        guard biometricService.canUseBiometrics() else {
            LoggingService.error("❌ SignIn: Biometrics not available", component: "Authentication")
            return
        }
        
        do {
            try await biometricService.authenticateWithBiometrics()
            
            if let credentials = try biometricService.retrieveBiometricCredentials() {
                email = credentials.email
                password = credentials.password
                await signIn()
            }
        } catch BiometricError.userCancel, BiometricError.userFallback {
            // User chose to use password instead - do nothing
            LoggingService.debug("👤 SignIn: User chose to use password", component: "Authentication")
        } catch {
            LoggingService.error("❌ SignIn: Biometric authentication failed: \(error.localizedDescription)", component: "Authentication")
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func enableBiometricLogin() {
        do {
            try biometricService.saveBiometricCredentials(email: email, password: password)
            LoggingService.success("✅ SignIn: Successfully enabled biometric login", component: "Authentication")
        } catch {
            LoggingService.error("❌ SignIn: Failed to enable biometric login: \(error.localizedDescription)", component: "Authentication")
            showError = true
            errorMessage = "Failed to enable \(biometricType.description). Please try again."
        }
    }
    
    func resetPassword() async {
        guard !email.isEmpty else {
            LoggingService.error("❌ SignIn: No email provided for password reset", component: "Authentication")
            showError = true
            errorMessage = "Please enter your email address"
            return
        }
        
        guard isValidEmail(email) else {
            LoggingService.error("❌ SignIn: Invalid email format for password reset", component: "Authentication")
            showError = true
            errorMessage = "Please enter a valid email address"
            return
        }
        
        isLoading = true
        LoggingService.debug("🔐 SignIn: Starting password reset for email: \(email)", component: "Authentication")
        
        do {
            try await authManager.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            LoggingService.success("✅ SignIn: Successfully sent password reset email", component: "Authentication")
            showResetAlert = true
            
        } catch {
            LoggingService.error("❌ SignIn: Password reset failed: \(error.localizedDescription)", component: "Authentication")
            showError = true
            errorMessage = "Failed to send password reset email. Please try again."
        }
        
        isLoading = false
    }
} 