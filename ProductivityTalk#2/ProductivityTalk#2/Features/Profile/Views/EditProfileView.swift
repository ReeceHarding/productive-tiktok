import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    
    @State private var username: String
    @State private var email: String
    @State private var bio: String
    
    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        _username = State(initialValue: viewModel.user?.username ?? "")
        _email = State(initialValue: viewModel.user?.email ?? "")
        _bio = State(initialValue: viewModel.user?.bio ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Picture")) {
                    PhotosPicker(selection: $viewModel.selectedItem,
                               matching: .images) {
                        HStack {
                            Text("Change Profile Picture")
                            Spacer()
                            Image(systemName: "photo.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Section(header: Text("Basic Information")) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("About")) {
                    TextEditor(text: $bio)
                        .frame(height: 100)
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
                            await viewModel.updateProfile(
                                username: username,
                                email: email,
                                bio: bio
                            )
                            dismiss()
                        }
                    }
                    .disabled(username.isEmpty || email.isEmpty)
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