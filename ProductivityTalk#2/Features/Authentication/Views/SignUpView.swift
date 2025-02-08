import SwiftUI
import UIKit

struct CustomTextField: View {
    let iconName: String
    let placeholder: String
    let isSecure: Bool
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: iconName)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboardType)
        }
        .padding()
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SignUpView: View {
    @StateObject private var viewModel = SignUpViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
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
                
                ScrollView {
                    VStack(spacing: 25) {
                        // App Logo/Icon
                        Image(systemName: "brain.head.profile")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.blue)
                            .padding(.top, 40)
                        
                        Text("Create Account")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 20)
                        
                        VStack(spacing: 20) {
                            CustomTextField(
                                iconName: "person",
                                placeholder: "Username",
                                isSecure: false,
                                text: $viewModel.username,
                                contentType: .username
                            )
                            
                            CustomTextField(
                                iconName: "lock",
                                placeholder: "Password",
                                isSecure: true,
                                text: $viewModel.password,
                                contentType: .newPassword
                            )
                            
                            CustomTextField(
                                iconName: "lock.shield",
                                placeholder: "Confirm Password",
                                isSecure: true,
                                text: $viewModel.confirmPassword,
                                contentType: .newPassword
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Sign Up Button
                        Button(action: signUp) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 5)
                                }
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                viewModel.isValid && !viewModel.isLoading ?
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [.gray, .gray]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                        }
                        .disabled(!viewModel.isValid || viewModel.isLoading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Sign In Link
                        Button(action: { dismiss() }) {
                            HStack {
                                Text("Already have an account?")
                                    .foregroundColor(.gray)
                                Text("Sign In")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .fullScreenCover(isPresented: $viewModel.isAuthenticated) {
                MainTabView()
            }
        }
    }
    
    private func signUp() {
        Task {
            await viewModel.signUp()
        }
    }
}

#Preview {
    SignUpView()
} 