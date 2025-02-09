import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    
    @State private var username: String
    @State private var bio: String
    
    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        _username = State(initialValue: viewModel.user?.username ?? "")
        _bio = State(initialValue: viewModel.user?.bio ?? "")
    }
    
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
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            TextField("Username", text: $username)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bio")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            TextEditor(text: $bio)
                                .frame(height: 100)
                                .padding(4)
                                .background(Color(uiColor: .systemBackground))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .systemBackground).opacity(0.8))
                    .cornerRadius(16)
                    .shadow(radius: 5)
                    .padding()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.updateProfile(username: username, bio: bio)
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
        }
    }
} 