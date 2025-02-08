import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @StateObject private var secondBrainViewModel = SecondBrainViewModel()
    @State private var showSignOutAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header
                    VStack(spacing: 16) {
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
                            .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 2))
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .foregroundColor(.gray)
                        }
                        
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
                            
                            Button("Edit Profile") {
                                viewModel.showEditProfile = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                    .padding()
                    
                    // Stats
                    HStack(spacing: 40) {
                        VStack {
                            Text(viewModel.formatNumber(viewModel.user?.totalSecondBrainSaves ?? 0))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Insights")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text(viewModel.formatNumber(viewModel.user?.totalQuotesSaved ?? 0))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Quotes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text(viewModel.formatNumber(viewModel.user?.totalTranscriptsSaved ?? 0))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Transcripts")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Recent Activity
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recent Activity")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if let error = viewModel.error {
                            Text(error)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            // Add recent activity items here
                            Text("No recent activity")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $viewModel.showEditProfile) {
                EditProfileView(viewModel: viewModel)
            }
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
            .task {
                await viewModel.loadUserData()
                await secondBrainViewModel.updateStatistics()
            }
            .refreshable {
                await viewModel.loadUserData()
                await secondBrainViewModel.updateStatistics()
            }
        }
    }
}

#Preview {
    ProfileView()
} 