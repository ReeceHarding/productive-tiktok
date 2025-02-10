import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: ProfileViewModel
    
    @State private var username: String
    @State private var bio: String
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
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
                            Label("Username", systemImage: "person")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            TextField("Username", text: $username)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .onChange(of: username) { _ in
                                    impactGenerator.impactOccurred(intensity: 0.3)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Bio", systemImage: "text.quote")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $bio)
                                .frame(height: 100)
                                .padding(12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .onChange(of: bio) { _ in
                                    impactGenerator.impactOccurred(intensity: 0.3)
                                }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground).opacity(0.8))
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    )
                    .padding()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        impactGenerator.impactOccurred(intensity: 0.5)
                        dismiss()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        impactGenerator.impactOccurred(intensity: 0.6)
                        Task {
                            await viewModel.updateProfile(username: username, bio: bio)
                            notificationGenerator.notificationOccurred(.success)
                            dismiss()
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isLoading || username.isEmpty)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    notificationGenerator.notificationOccurred(.error)
                    viewModel.clearError()
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
            .task {
                notificationGenerator.prepare()
                impactGenerator.prepare()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    notificationGenerator.prepare()
                    impactGenerator.prepare()
                }
            }
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

#Preview {
    EditProfileView(viewModel: ProfileViewModel())
} 