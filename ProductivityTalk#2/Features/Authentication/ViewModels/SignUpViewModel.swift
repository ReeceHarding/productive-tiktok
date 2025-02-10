import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SignUpViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    @Published private(set) var validationMessage = ""
    
    private let authManager = AuthenticationManager.shared
    
    var isValid: Bool {
        let usernameIsValid = username.count >= 3 && username.count <= 30
        let passwordIsValid = isPasswordValid(password)
        let passwordsMatch = password == confirmPassword
        
        // Update validation message
        if username.isEmpty && password.isEmpty && confirmPassword.isEmpty {
            validationMessage = ""
        } else if !usernameIsValid && username.count > 0 {
            validationMessage = "Username must be between 3 and 30 characters"
        } else if !passwordIsValid && password.count > 0 {
            validationMessage = "Password doesn't meet requirements"
        } else if !passwordsMatch && confirmPassword.count > 0 {
            validationMessage = "Passwords don't match"
        } else {
            validationMessage = ""
        }
        
        return usernameIsValid && passwordIsValid && passwordsMatch
    }
    
    private func isPasswordValid(_ password: String) -> Bool {
        let minLength = password.count >= 6
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        
        return minLength && hasUppercase && hasLowercase && hasNumber
    }
    
    func signUp() async {
        guard isValid else {
            LoggingService.error("❌ SignUp: Form validation failed", component: "Authentication")
            showError = true
            errorMessage = "Please fill in all fields correctly"
            return
        }
        
        isLoading = true
        LoggingService.debug("🔐 SignUp: Starting sign up process for username: \(username)", component: "Authentication")
        
        do {
            // Generate a unique email based on username
            let generatedEmail = "\(username.lowercased())_\(UUID().uuidString)@productivitytalk.app"
            
            try await authManager.signUp(
                email: generatedEmail,
                password: password,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            LoggingService.success("✅ SignUp: Successfully signed up user", component: "Authentication")
            isAuthenticated = true
            
        } catch let error as AuthError {
            LoggingService.error("❌ SignUp: Failed with AuthError: \(error.description)", component: "Authentication")
            showError = true
            errorMessage = error.description
            
        } catch {
            LoggingService.error("❌ SignUp: Failed with unknown error: \(error.localizedDescription)", component: "Authentication")
            showError = true
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
} 