import SwiftUI
import UIKit

struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    @State private var showSignUp = false
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
                        
                        Text("Welcome Back")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 20)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(spacing: 20) {
                            CustomTextField(
                                iconName: "envelope",
                                placeholder: "Email",
                                isSecure: false,
                                text: $viewModel.email,
                                contentType: .emailAddress,
                                keyboardType: .emailAddress
                            )
                            .onChange(of: viewModel.email) { _ in
                                impactGenerator.impactOccurred(intensity: 0.3)
                                Task { @MainActor in
                                    await viewModel.updateValidation()
                                }
                            }
                            
                            CustomTextField(
                                iconName: "lock",
                                placeholder: "Password",
                                isSecure: true,
                                text: $viewModel.password,
                                contentType: .password
                            )
                            .onChange(of: viewModel.password) { _ in
                                impactGenerator.impactOccurred(intensity: 0.3)
                                Task { @MainActor in
                                    await viewModel.updateValidation()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Validation Messages
                        if !viewModel.validationMessage.isEmpty {
                            Text(viewModel.validationMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }
                        
                        // Sign In Button
                        Button(action: {
                            impactGenerator.impactOccurred(intensity: 0.6)
                            Task {
                                await viewModel.signIn()
                            }
                        }) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 5)
                                }
                                Text("Sign In")
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
                        
                        // Biometric Login Button
                        if viewModel.biometricType != .none {
                            Button(action: {
                                impactGenerator.impactOccurred(intensity: 0.6)
                                Task {
                                    await viewModel.authenticateWithBiometrics()
                                }
                            }) {
                                HStack {
                                    Image(systemName: viewModel.biometricType == .faceID ? "faceid" : "touchid")
                                        .font(.system(size: 20))
                                    Text("Sign in with \(viewModel.biometricType.description)")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemBackground))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                        
                        // Forgot Password Button
                        Button(action: { 
                            impactGenerator.impactOccurred(intensity: 0.4)
                            Task {
                                await viewModel.resetPassword()
                            }
                        }) {
                            Text("Forgot Password?")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 5)
                        
                        // Sign Up Link
                        Button(action: { 
                            impactGenerator.impactOccurred(intensity: 0.5)
                            showSignUp = true 
                        }) {
                            HStack {
                                Text("Don't have an account?")
                                    .foregroundColor(.gray)
                                Text("Sign Up")
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
        }
        .task {
            // Initialize haptic feedback generators and check biometric auth
            notificationGenerator.prepare()
            impactGenerator.prepare()
            await viewModel.checkBiometricAuth()
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .onDisappear {
                    // Reset validation state when returning from sign up
                    Task { @MainActor in
                        await viewModel.updateValidation()
                    }
                }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                notificationGenerator.notificationOccurred(.error)
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .alert("Enable \(viewModel.biometricType.description)?", isPresented: $viewModel.showBiometricAlert) {
            Button("Not Now", role: .cancel) {}
            Button("Enable") {
                notificationGenerator.notificationOccurred(.success)
                viewModel.enableBiometricLogin()
            }
        } message: {
            Text("Would you like to enable \(viewModel.biometricType.description) for faster sign in?")
        }
        .alert("Password Reset", isPresented: $viewModel.showResetAlert) {
            Button("OK", role: .cancel) {
                notificationGenerator.notificationOccurred(.success)
            }
        } message: {
            Text("A password reset link has been sent to your email")
        }
    }
}

#Preview {
    SignInView()
} 