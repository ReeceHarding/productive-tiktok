import SwiftUI

struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    @State private var showSignUp = false
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
                        
                        Text("Welcome Back")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 20)
                        
                        VStack(spacing: 20) {
                            CustomTextField(
                                iconName: "envelope",
                                placeholder: "Email",
                                isSecure: false,
                                text: $viewModel.email,
                                contentType: .emailAddress,
                                keyboardType: .emailAddress
                            )
                            
                            CustomTextField(
                                iconName: "lock",
                                placeholder: "Password",
                                isSecure: true,
                                text: $viewModel.password,
                                contentType: .password
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Sign In Button
                        Button(action: signIn) {
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
                        
                        // Forgot Password Button
                        Button(action: { 
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
                        Button(action: { showSignUp = true }) {
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
            .sheet(isPresented: $showSignUp) {
                SignUpView()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .alert("Password Reset", isPresented: $viewModel.showResetAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("If an account exists with this email, you will receive a password reset link.")
            }
        }
    }
    
    private func signIn() {
        Task {
            await viewModel.signIn()
        }
    }
}

#Preview {
    SignInView()
} 