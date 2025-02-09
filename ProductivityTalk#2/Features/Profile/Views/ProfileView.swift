import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSignOutAlert = false
    
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
                    VStack(spacing: 24) {
                        // Profile Header
                        VStack(spacing: 16) {
                            // Profile Picture
                            PhotosPicker(selection: $viewModel.selectedItem,
                                       matching: .images) {
                                if let profilePicURL = viewModel.user?.profilePicURL,
                                   let url = URL(string: profilePicURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // User Info
                            VStack(spacing: 8) {
                                Text(viewModel.user?.username ?? "Username")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                if let bio = viewModel.user?.bio {
                                    Text(bio)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                
                                Button(action: {
                                    viewModel.showEditProfile = true
                                }) {
                                    Text("Edit Profile")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.blue, .purple]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(10)
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .systemBackground).opacity(0.8))
                        .cornerRadius(20)
                        .shadow(radius: 5)
                        .padding()
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSignOutAlert = true }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        await viewModel.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $viewModel.showEditProfile) {
                EditProfileView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadUserData()
            }
            .refreshable {
                await viewModel.loadUserData()
            }
        }
    }
}

#Preview {
    ProfileView()
} 