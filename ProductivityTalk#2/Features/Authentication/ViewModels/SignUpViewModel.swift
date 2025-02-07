import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SignUpViewModel: ObservableObject {
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    
    private let authManager = AuthenticationManager.shared
    
    var isValid: Bool {
        !username.isEmpty &&
        !email.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        password == confirmPassword &&
        password.count >= 6
    }
    
    func signUp() async {
        guard isValid else {
            print("❌ SignUp: Form validation failed")
            showError = true
            errorMessage = "Please fill in all fields correctly"
            return
        }
        
        isLoading = true
        print("🔐 SignUp: Starting sign up process for email: \(email)")
        
        do {
            try await authManager.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            print("✅ SignUp: Successfully signed up user")
            
        } catch let error as AuthError {
            print("❌ SignUp: Failed with AuthError: \(error.description)")
            showError = true
            errorMessage = error.description
            
        } catch {
            print("❌ SignUp: Failed with unknown error: \(error.localizedDescription)")
            showError = true
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
} 