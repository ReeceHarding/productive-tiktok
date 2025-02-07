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
    
    private let authManager = AuthenticationManager.shared
    
    var isValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    func signIn() async {
        guard isValid else {
            print("❌ SignIn: Form validation failed")
            showError = true
            errorMessage = "Please fill in all fields"
            return
        }
        
        isLoading = true
        print("🔐 SignIn: Starting sign in process for email: \(email)")
        
        do {
            try await authManager.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            print("✅ SignIn: Successfully signed in user")
            
        } catch let error as AuthError {
            print("❌ SignIn: Failed with AuthError: \(error.description)")
            showError = true
            errorMessage = error.description
            
        } catch {
            print("❌ SignIn: Failed with unknown error: \(error.localizedDescription)")
            showError = true
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
    
    func resetPassword() async {
        guard !email.isEmpty else {
            print("❌ SignIn: No email provided for password reset")
            showError = true
            errorMessage = "Please enter your email address"
            return
        }
        
        isLoading = true
        print("🔐 SignIn: Starting password reset for email: \(email)")
        
        do {
            try await authManager.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            print("✅ SignIn: Successfully sent password reset email")
            showError = true // Using error alert for success message
            errorMessage = "Password reset email sent. Please check your inbox."
            
        } catch {
            print("❌ SignIn: Password reset failed: \(error.localizedDescription)")
            showError = true
            errorMessage = "Failed to send password reset email. Please try again."
        }
        
        isLoading = false
    }
} 