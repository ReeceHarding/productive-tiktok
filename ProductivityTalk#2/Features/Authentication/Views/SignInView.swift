import SwiftUI

struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    @State private var showSignUp = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Sign In")) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                }
                
                Section {
                    Button(action: signIn) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.isValid || viewModel.isLoading)
                    
                    Button("Forgot Password?") {
                        Task {
                            await viewModel.resetPassword()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section {
                    Button("Don't have an account? Sign Up") {
                        showSignUp = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Welcome Back")
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