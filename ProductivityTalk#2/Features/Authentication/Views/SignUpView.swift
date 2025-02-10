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
    @Environment(\.scenePhase) private var scenePhase
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
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
                        // App Logo/Icon with animation
                        Image(systemName: "brain.head.profile")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.blue)
                            .padding(.top, 40)
                            .symbolEffect(.bounce, options: .repeating)
                            .accessibilityLabel("App Logo")
                        
                        Text("Create Account")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 20)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(spacing: 20) {
                            CustomTextField(
                                iconName: "person",
                                placeholder: "Username",
                                isSecure: false,
                                text: $viewModel.username,
                                contentType: .username
                            )
                            .onChange(of: viewModel.username) { _ in
                                impactGenerator.impactOccurred(intensity: 0.3)
                            }
                            
                            CustomTextField(
                                iconName: "lock",
                                placeholder: "Password",
                                isSecure: true,
                                text: $viewModel.password,
                                contentType: .newPassword
                            )
                            .onChange(of: viewModel.password) { _ in
                                impactGenerator.impactOccurred(intensity: 0.3)
                            }
                            
                            CustomTextField(
                                iconName: "lock.shield",
                                placeholder: "Confirm Password",
                                isSecure: true,
                                text: $viewModel.confirmPassword,
                                contentType: .newPassword
                            )
                            .onChange(of: viewModel.confirmPassword) { _ in
                                impactGenerator.impactOccurred(intensity: 0.3)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Password Requirements
                        if !viewModel.password.isEmpty {
                            PasswordRequirementsView(password: viewModel.password)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }
                        
                        // Validation Messages
                        if !viewModel.validationMessage.isEmpty {
                            Text(viewModel.validationMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }
                        
                        // Sign Up Button
                        Button(action: {
                            impactGenerator.impactOccurred(intensity: 0.6)
                            signUp()
                        }) {
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
                        Button(action: { 
                            impactGenerator.impactOccurred(intensity: 0.5)
                            dismiss()
                        }) {
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
                Button("OK", role: .cancel) {
                    notificationGenerator.notificationOccurred(.error)
                }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .fullScreenCover(isPresented: $viewModel.isAuthenticated) {
                MainTabView()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    notificationGenerator.prepare()
                    impactGenerator.prepare()
                }
            }
        }
    }
    
    private func signUp() {
        Task {
            await viewModel.signUp()
        }
    }
}

struct PasswordRequirementsView: View {
    let password: String
    
    private var hasMinLength: Bool { password.count >= 6 }
    private var hasUppercase: Bool { password.contains(where: { $0.isUppercase }) }
    private var hasLowercase: Bool { password.contains(where: { $0.isLowercase }) }
    private var hasNumber: Bool { password.contains(where: { $0.isNumber }) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password Requirements")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            RequirementRow(text: "At least 6 characters", isMet: hasMinLength)
            RequirementRow(text: "Contains uppercase letter", isMet: hasUppercase)
            RequirementRow(text: "Contains lowercase letter", isMet: hasLowercase)
            RequirementRow(text: "Contains number", isMet: hasNumber)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.8))
        .cornerRadius(12)
    }
}

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SignUpView()
} 