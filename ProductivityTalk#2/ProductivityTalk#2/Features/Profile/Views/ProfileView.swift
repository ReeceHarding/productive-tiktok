import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    Text("Your Profile")
                        .font(.system(size: 34, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Text("Manage your account information")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    // Profile Picture Section
                    VStack(spacing: 16) {
                        if let user = viewModel.user {
                            AsyncImage(url: URL(string: user.profilePicURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                            .shadow(radius: 10)
                        }
                        
                        Button(action: { viewModel.showImagePicker = true }) {
                            Label("Change Picture", systemImage: "camera.fill")
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.black)
                                .cornerRadius(25)
                        }
                    }
                    .padding(.vertical)
                    
                    // User Information Form
                    VStack(spacing: 24) {
                        // Username Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .foregroundColor(.gray)
                            
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.gray)
                                Text(viewModel.user?.username ?? "johndoe")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .foregroundColor(.gray)
                            
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.gray)
                                Text(viewModel.user?.email ?? "john.doe@example.com")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .foregroundColor(.gray)
                            
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.gray)
                                Text("••••••••")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Stats Section
                    if let user = viewModel.user {
                        VStack(spacing: 24) {
                            Text("Your Stats")
                                .font(.title2)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                StatCard(
                                    title: "Second Brain",
                                    value: viewModel.formatNumber(user.totalSecondBrainSaves),
                                    subtitle: "Total Saves"
                                )
                                
                                StatCard(
                                    title: "Current Streak",
                                    value: "\(user.currentStreak)",
                                    subtitle: "Days"
                                )
                                
                                StatCard(
                                    title: "Videos",
                                    value: viewModel.formatNumber(user.totalVideosUploaded),
                                    subtitle: "Uploaded"
                                )
                                
                                StatCard(
                                    title: "Engagement",
                                    value: String(format: "%.1f%%", user.videoEngagementRate * 100),
                                    subtitle: "Rate"
                                )
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Edit Profile Button
                    Button(action: { viewModel.showEditProfile = true }) {
                        Text("Edit Profile")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.vertical)
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGray6))
            .task {
                await viewModel.loadUserData()
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
        .cornerRadius(12)
    }
}

#Preview {
    ProfileView()
} 